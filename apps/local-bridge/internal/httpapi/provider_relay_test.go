package httpapi

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestProviderRelayWorkerCompletesPolledJob(t *testing.T) {
	var completed providerRelayCompleteRequest
	var forwardedModel string
	var registered registerProviderRequest
	var registerCalls int
	localProviderID, localProviderName := localProviderIdentity()
	localMemberID, localMemberName := localMemberIdentity()

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/models" {
			writeJSON(w, http.StatusOK, map[string]any{"data": []map[string]any{{"id": "qwen2.5-coder:32b"}}})
			return
		}
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected backend path %s", r.URL.Path)
		}
		var req chatCompletionsRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode backend request: %v", err)
		}
		if req.ReasoningEffort != "low" {
			t.Fatalf("expected reasoning_effort to reach provider inference backend, got %q", req.ReasoningEffort)
		}
		if string(req.Reasoning) != `{"budget_tokens":512}` {
			t.Fatalf("expected reasoning control to reach provider inference backend, got %s", string(req.Reasoning))
		}
		if string(req.Think) != `false` {
			t.Fatalf("expected think control to reach provider inference backend, got %s", string(req.Think))
		}
		forwardedModel = req.Model
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"REMOTE_PROVIDER_OK"}}]}`))
	}))
	defer backend.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/providers/relay/poll":
			writeJSON(w, http.StatusOK, providerRelayPollResponse{
				JobID:         "relay-000001",
				SessionID:     "sess-000001",
				ResolvedModel: "qwen2.5-coder:32b",
				Request:       json.RawMessage(`{"model":"best","stream":false,"reasoning_effort":"low","reasoning":{"budget_tokens":512},"think":false,"messages":[{"role":"user","content":"hello"}]}`),
			})
		case "/admin/v1/providers/relay/complete":
			if err := json.NewDecoder(r.Body).Decode(&completed); err != nil {
				t.Fatalf("decode complete request: %v", err)
			}
			writeJSON(w, http.StatusAccepted, providerRelayCompleteResponse{
				Status: "completed",
				JobID:  completed.JobID,
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:              localProviderID,
						Name:            localProviderName,
						SwarmID:         "swarm-alpha",
						OwnerMemberID:   localMemberID,
						OwnerMemberName: localMemberName,
						Status:          "available",
						Modes:           []string{"share", "both"},
						Slots:           slots{Free: 1, Total: 1},
						Models: []model{
							{
								ID:         "qwen2.5-coder:32b",
								Name:       "Qwen2.5 Coder 32B",
								SlotsFree:  1,
								SlotsTotal: 1,
							},
						},
					},
				},
			})
		case "/admin/v1/providers/register":
			registerCalls++
			if err := json.NewDecoder(r.Body).Decode(&registered); err != nil {
				t.Fatalf("decode register request: %v", err)
			}
			writeJSON(w, http.StatusCreated, registerProviderResponse{
				Status:   "registered",
				Provider: registered.Provider,
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		OllamaURL:                 backend.URL,
		InferenceHTTPClient:       backend.Client(),
		EnableProviderRelayWorker: false,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	handled, err := service.pollProviderRelayOnce(context.Background())
	if err != nil {
		t.Fatalf("poll provider relay once: %v", err)
	}
	if !handled {
		t.Fatal("expected provider relay worker to handle one job")
	}
	if forwardedModel != "qwen2.5-coder:32b" {
		t.Fatalf("expected resolved model to be forwarded, got %q", forwardedModel)
	}
	if completed.JobID != "relay-000001" {
		t.Fatalf("expected relay completion job id, got %+v", completed)
	}
	body, err := base64.StdEncoding.DecodeString(completed.BodyBase64)
	if err != nil {
		t.Fatalf("decode completed body: %v", err)
	}
	if !bytes.Contains(body, []byte("REMOTE_PROVIDER_OK")) {
		t.Fatalf("expected completed relay payload, got %s", string(body))
	}
	metrics := service.shareMetrics.snapshotValue()
	if metrics.ServedSessions != 1 {
		t.Fatalf("expected one served session in share metrics, got %+v", metrics)
	}
	if metrics.UploadedTokensEstimate <= 0 {
		t.Fatalf("expected uploaded token estimate in share metrics, got %+v", metrics)
	}
	if metrics.RecentUploadedTokensPS != 0 {
		t.Fatalf("expected non-streaming completion not to create recent uploaded throughput, got %+v", metrics)
	}
	if metrics.LastServedModel != "qwen2.5-coder:32b" {
		t.Fatalf("expected last served model to be recorded, got %+v", metrics)
	}
	if registerCalls < 2 {
		t.Fatalf("expected active and final provider metric syncs, got %d", registerCalls)
	}
	if registered.Provider.ServedSessions != 1 {
		t.Fatalf("expected served sessions to sync to coordinator, got %+v", registered.Provider)
	}
	if registered.Provider.UploadedTokensEstimate <= 0 {
		t.Fatalf("expected uploaded token estimate to sync to coordinator, got %+v", registered.Provider)
	}
	if registered.Provider.OwnerMemberID != localMemberID || registered.Provider.OwnerMemberName != localMemberName {
		t.Fatalf("expected owner identity in synced provider, got %+v", registered.Provider)
	}
}

func TestProviderRelayWorkerRecordsFailureAndSyncsProviderMetrics(t *testing.T) {
	var completed providerRelayCompleteRequest
	var registered registerProviderRequest
	var registerCalls int
	localProviderID, localProviderName := localProviderIdentity()
	localMemberID, localMemberName := localMemberIdentity()

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/models" {
			writeJSON(w, http.StatusOK, map[string]any{"data": []map[string]any{{"id": "qwen2.5-coder:32b"}}})
			return
		}
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected backend path %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadGateway)
		_, _ = w.Write([]byte(`{"error":{"code":"INFERENCE_UNAVAILABLE","message":"backend failed"}}`))
	}))
	defer backend.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/providers/relay/poll":
			writeJSON(w, http.StatusOK, providerRelayPollResponse{
				JobID:         "relay-failure-001",
				SessionID:     "sess-failure-001",
				ResolvedModel: "qwen2.5-coder:32b",
				Request:       json.RawMessage(`{"model":"best","stream":false,"messages":[{"role":"user","content":"hello"}]}`),
			})
		case "/admin/v1/providers/relay/complete":
			if err := json.NewDecoder(r.Body).Decode(&completed); err != nil {
				t.Fatalf("decode complete request: %v", err)
			}
			writeJSON(w, http.StatusAccepted, providerRelayCompleteResponse{
				Status: "completed",
				JobID:  completed.JobID,
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:              localProviderID,
						Name:            localProviderName,
						SwarmID:         "swarm-alpha",
						OwnerMemberID:   localMemberID,
						OwnerMemberName: localMemberName,
						Status:          "available",
						Modes:           []string{"share", "both"},
						Slots:           slots{Free: 1, Total: 1},
						Models: []model{
							{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1},
						},
					},
				},
			})
		case "/admin/v1/providers/register":
			registerCalls++
			if err := json.NewDecoder(r.Body).Decode(&registered); err != nil {
				t.Fatalf("decode register request: %v", err)
			}
			writeJSON(w, http.StatusCreated, registerProviderResponse{
				Status:   "registered",
				Provider: registered.Provider,
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		OllamaURL:                 backend.URL,
		InferenceHTTPClient:       backend.Client(),
		EnableProviderRelayWorker: false,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	handled, err := service.pollProviderRelayOnce(context.Background())
	if err != nil {
		t.Fatalf("poll provider relay once: %v", err)
	}
	if !handled {
		t.Fatal("expected provider relay worker to handle one failed job")
	}
	if completed.JobID != "relay-failure-001" || completed.StatusCode != http.StatusBadGateway {
		t.Fatalf("expected failed relay completion, got %+v", completed)
	}
	metrics := service.shareMetrics.snapshotValue()
	if metrics.FailedSessions != 1 {
		t.Fatalf("expected one failed session in share metrics, got %+v", metrics)
	}
	if metrics.ServedSessions != 0 {
		t.Fatalf("did not expect successful served session count on failure, got %+v", metrics)
	}
	if registerCalls < 2 {
		t.Fatalf("expected active and final provider metric syncs on failure, got %d", registerCalls)
	}
	if registered.Provider.FailedSessions != 1 {
		t.Fatalf("expected failed sessions to sync to coordinator, got %+v", registered.Provider)
	}
}

func TestProviderRelayWorkerHydratesOnlyMacsArtifact(t *testing.T) {
	var completed providerRelayCompleteRequest
	var forwardedPrompt string
	var artifactPresent bool
	localProviderID, localProviderName := localProviderIdentity()
	localMemberID, localMemberName := localMemberIdentity()
	artifactPayload := testOnlyMacsArtifactPayload(t, map[string]string{
		"docs/2 - MASTER CONTENT CREATION.md": "# Creation\nGrounded pipeline steps.\n",
	})
	requestBody, err := json.Marshal(chatCompletionsRequest{
		Model:            "best",
		Stream:           false,
		OnlyMacsArtifact: artifactPayload,
		Messages: []chatMessage{{
			Role:    "user",
			Content: "Review these pipeline docs.",
		}},
	})
	if err != nil {
		t.Fatalf("marshal relay request: %v", err)
	}

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/models" {
			writeJSON(w, http.StatusOK, map[string]any{"data": []map[string]any{{"id": "qwen2.5-coder:32b"}}})
			return
		}
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected backend path %s", r.URL.Path)
		}
		var req chatCompletionsRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode backend request: %v", err)
		}
		artifactPresent = req.OnlyMacsArtifact != nil
		if len(req.Messages) > 0 {
			forwardedPrompt = req.Messages[0].Content
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"REMOTE_PROVIDER_ARTIFACT_OK"}}]}`))
	}))
	defer backend.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/providers/relay/poll":
			writeJSON(w, http.StatusOK, providerRelayPollResponse{
				JobID:         "relay-artifact-001",
				SessionID:     "sess-artifact-001",
				ResolvedModel: "qwen2.5-coder:32b",
				Request:       requestBody,
			})
		case "/admin/v1/providers/relay/complete":
			if err := json.NewDecoder(r.Body).Decode(&completed); err != nil {
				t.Fatalf("decode complete request: %v", err)
			}
			writeJSON(w, http.StatusAccepted, providerRelayCompleteResponse{
				Status: "completed",
				JobID:  completed.JobID,
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:              localProviderID,
						Name:            localProviderName,
						SwarmID:         "swarm-alpha",
						OwnerMemberID:   localMemberID,
						OwnerMemberName: localMemberName,
						Status:          "available",
						Modes:           []string{"share", "both"},
						Slots:           slots{Free: 1, Total: 1},
						Models: []model{
							{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1},
						},
					},
				},
			})
		case "/admin/v1/providers/register":
			writeJSON(w, http.StatusCreated, registerProviderResponse{
				Status: "registered",
				Provider: provider{
					ID:              localProviderID,
					Name:            localProviderName,
					OwnerMemberID:   localMemberID,
					OwnerMemberName: localMemberName,
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		OllamaURL:                 backend.URL,
		InferenceHTTPClient:       backend.Client(),
		EnableProviderRelayWorker: false,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	handled, err := service.pollProviderRelayOnce(context.Background())
	if err != nil {
		t.Fatalf("poll provider relay once: %v", err)
	}
	if !handled {
		t.Fatal("expected provider relay worker to handle artifact job")
	}
	if artifactPresent {
		t.Fatalf("expected artifact to be consumed before backend inference")
	}
	if !strings.Contains(forwardedPrompt, "MASTER CONTENT CREATION") {
		t.Fatalf("expected hydrated artifact content in prompt, got %q", forwardedPrompt)
	}
	body, err := base64.StdEncoding.DecodeString(completed.BodyBase64)
	if err != nil {
		t.Fatalf("decode completed body: %v", err)
	}
	if !bytes.Contains(body, []byte("REMOTE_PROVIDER_ARTIFACT_OK")) {
		t.Fatalf("expected relay completion body, got %s", string(body))
	}
}

func TestProviderRelayWorkerExecutesCodexToolAgainstArtifactWorkspace(t *testing.T) {
	tempDir := t.TempDir()
	originalPath := os.Getenv("PATH")
	t.Cleanup(func() {
		_ = os.Setenv("PATH", originalPath)
	})

	codexPath := filepath.Join(tempDir, "codex")
	script := `#!/bin/sh
output=""
workdir=""
while [ $# -gt 0 ]; do
  case "$1" in
    exec)
      shift
      ;;
    -C)
      workdir="$2"
      shift 2
      ;;
    -o)
      output="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$workdir/generated"
printf '{"status":"remote"}\n' > "$workdir/generated/review.json"
printf 'remote codex review complete\n' > "$output"
`
	if err := os.WriteFile(codexPath, []byte(script), 0o755); err != nil {
		t.Fatalf("write fake codex: %v", err)
	}
	if err := os.Setenv("PATH", tempDir+string(os.PathListSeparator)+originalPath); err != nil {
		t.Fatalf("set PATH: %v", err)
	}

	var completed providerRelayCompleteRequest
	localProviderID, localProviderName := localProviderIdentity()
	localMemberID, localMemberName := localMemberIdentity()

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/models" {
			t.Fatalf("unexpected backend path %s", r.URL.Path)
		}
		writeJSON(w, http.StatusOK, map[string]any{"data": []map[string]any{{"id": "qwen2.5-coder:32b"}}})
	}))
	defer backend.Close()

	artifactPayload := testOnlyMacsArtifactPayload(t, map[string]string{
		"docs/2 - MASTER CONTENT CREATION.md": "# Creation\nGrounded pipeline steps.\n",
	})
	artifactPayload.Manifest.ToolName = "Codex"
	requestBody, err := json.Marshal(chatCompletionsRequest{
		Model:            "best",
		Stream:           false,
		OnlyMacsArtifact: artifactPayload,
		Messages: []chatMessage{{
			Role:    "user",
			Content: "Review these pipeline docs and generate a JSON note.",
		}},
	})
	if err != nil {
		t.Fatalf("marshal relay request: %v", err)
	}

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/providers/relay/poll":
			writeJSON(w, http.StatusOK, providerRelayPollResponse{
				JobID:         "relay-tool-001",
				SessionID:     "sess-tool-001",
				ResolvedModel: "qwen2.5-coder:32b",
				Request:       requestBody,
			})
		case "/admin/v1/providers/relay/complete":
			if err := json.NewDecoder(r.Body).Decode(&completed); err != nil {
				t.Fatalf("decode complete request: %v", err)
			}
			writeJSON(w, http.StatusAccepted, providerRelayCompleteResponse{
				Status: "completed",
				JobID:  completed.JobID,
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:              localProviderID,
						Name:            localProviderName,
						SwarmID:         "swarm-alpha",
						OwnerMemberID:   localMemberID,
						OwnerMemberName: localMemberName,
						Status:          "available",
						Modes:           []string{"share", "both"},
						Slots:           slots{Free: 1, Total: 1},
						Models: []model{
							{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1},
						},
					},
				},
			})
		case "/admin/v1/providers/register":
			writeJSON(w, http.StatusCreated, registerProviderResponse{
				Status: "registered",
				Provider: provider{
					ID:              localProviderID,
					Name:            localProviderName,
					OwnerMemberID:   localMemberID,
					OwnerMemberName: localMemberName,
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		OllamaURL:                 backend.URL,
		InferenceHTTPClient:       backend.Client(),
		EnableProviderRelayWorker: false,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	handled, err := service.pollProviderRelayOnce(context.Background())
	if err != nil {
		t.Fatalf("poll provider relay once: %v", err)
	}
	if !handled {
		t.Fatal("expected provider relay worker to handle tool relay job")
	}
	body, err := base64.StdEncoding.DecodeString(completed.BodyBase64)
	if err != nil {
		t.Fatalf("decode completed body: %v", err)
	}
	if !bytes.Contains(body, []byte("remote codex review complete")) {
		t.Fatalf("expected codex output in relay body, got %s", string(body))
	}
	if !bytes.Contains(body, []byte("generated/review.json")) {
		t.Fatalf("expected generated file summary in relay body, got %s", string(body))
	}
}

func TestProviderRelayWorkerFallsBackToArtifactHydrationWhenCodexWorkspaceExecFails(t *testing.T) {
	originalLookPath := onlyMacsExecLookPath
	onlyMacsExecLookPath = func(file string) (string, error) {
		return "", os.ErrNotExist
	}
	t.Cleanup(func() {
		onlyMacsExecLookPath = originalLookPath
	})

	var completed providerRelayCompleteRequest
	var forwardedPrompt string
	localProviderID, localProviderName := localProviderIdentity()
	localMemberID, localMemberName := localMemberIdentity()
	artifactPayload := testOnlyMacsArtifactPayload(t, map[string]string{
		"docs/2 - MASTER CONTENT CREATION.md": "# Creation\nGrounded pipeline steps.\n",
	})
	artifactPayload.Manifest.ToolName = "Codex"
	requestBody, err := json.Marshal(chatCompletionsRequest{
		Model:            "best",
		Stream:           false,
		OnlyMacsArtifact: artifactPayload,
		Messages: []chatMessage{{
			Role:    "user",
			Content: "Review these pipeline docs.",
		}},
	})
	if err != nil {
		t.Fatalf("marshal relay request: %v", err)
	}

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/models" {
			writeJSON(w, http.StatusOK, map[string]any{"data": []map[string]any{{"id": "qwen2.5-coder:32b"}}})
			return
		}
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected backend path %s", r.URL.Path)
		}
		var req chatCompletionsRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode backend request: %v", err)
		}
		if req.OnlyMacsArtifact != nil {
			t.Fatal("expected artifact to be consumed before backend fallback inference")
		}
		if len(req.Messages) > 0 {
			forwardedPrompt = req.Messages[0].Content
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"RELAY_FALLBACK_OK"}}]}`))
	}))
	defer backend.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/providers/relay/poll":
			writeJSON(w, http.StatusOK, providerRelayPollResponse{
				JobID:         "relay-tool-fallback-001",
				SessionID:     "sess-tool-fallback-001",
				ResolvedModel: "qwen2.5-coder:32b",
				Request:       requestBody,
			})
		case "/admin/v1/providers/relay/complete":
			if err := json.NewDecoder(r.Body).Decode(&completed); err != nil {
				t.Fatalf("decode complete request: %v", err)
			}
			writeJSON(w, http.StatusAccepted, providerRelayCompleteResponse{
				Status: "completed",
				JobID:  completed.JobID,
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:              localProviderID,
						Name:            localProviderName,
						SwarmID:         "swarm-alpha",
						OwnerMemberID:   localMemberID,
						OwnerMemberName: localMemberName,
						Status:          "available",
						Modes:           []string{"share", "both"},
						Slots:           slots{Free: 1, Total: 1},
						Models: []model{
							{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1},
						},
					},
				},
			})
		case "/admin/v1/providers/register":
			writeJSON(w, http.StatusCreated, registerProviderResponse{
				Status: "registered",
				Provider: provider{
					ID:              localProviderID,
					Name:            localProviderName,
					OwnerMemberID:   localMemberID,
					OwnerMemberName: localMemberName,
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		OllamaURL:                 backend.URL,
		InferenceHTTPClient:       backend.Client(),
		EnableProviderRelayWorker: false,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	handled, err := service.pollProviderRelayOnce(context.Background())
	if err != nil {
		t.Fatalf("poll provider relay once: %v", err)
	}
	if !handled {
		t.Fatal("expected provider relay worker to handle fallback tool relay job")
	}
	if !strings.Contains(forwardedPrompt, "MASTER CONTENT CREATION") {
		t.Fatalf("expected hydrated artifact content in fallback prompt, got %q", forwardedPrompt)
	}
	body, err := base64.StdEncoding.DecodeString(completed.BodyBase64)
	if err != nil {
		t.Fatalf("decode completed body: %v", err)
	}
	if !bytes.Contains(body, []byte("RELAY_FALLBACK_OK")) {
		t.Fatalf("expected fallback relay body, got %s", string(body))
	}
	if completed.StatusCode != http.StatusOK {
		t.Fatalf("expected relay fallback to succeed, got %+v", completed)
	}
}

func TestProviderRelayWorkerStreamsPolledJob(t *testing.T) {
	var chunkRequests []providerRelayChunkRequest
	var completed providerRelayCompleteRequest
	var registered registerProviderRequest
	var registerCalls int
	localProviderID, localProviderName := localProviderIdentity()
	localMemberID, localMemberName := localMemberIdentity()

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/models" {
			writeJSON(w, http.StatusOK, map[string]any{"data": []map[string]any{{"id": "qwen2.5-coder:32b"}}})
			return
		}
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected backend path %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("data: {\"choices\":[{\"delta\":{\"content\":\"REMOTE_\"}}]}\n\n"))
		_, _ = w.Write([]byte("data: {\"choices\":[{\"delta\":{\"content\":\"STREAM\"}}]}\n\n"))
		_, _ = w.Write([]byte("data: [DONE]\n\n"))
	}))
	defer backend.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/providers/relay/poll":
			writeJSON(w, http.StatusOK, providerRelayPollResponse{
				JobID:         "relay-stream-001",
				SessionID:     "sess-stream-001",
				ResolvedModel: "qwen2.5-coder:32b",
				Stream:        true,
				Request:       json.RawMessage(`{"model":"best","stream":true,"messages":[{"role":"user","content":"hello"}]}`),
			})
		case "/admin/v1/providers/relay/chunk":
			var req providerRelayChunkRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode chunk request: %v", err)
			}
			chunkRequests = append(chunkRequests, req)
			writeJSON(w, http.StatusAccepted, providerRelayChunkResponse{
				Status: "queued",
				JobID:  req.JobID,
			})
		case "/admin/v1/providers/relay/complete":
			if err := json.NewDecoder(r.Body).Decode(&completed); err != nil {
				t.Fatalf("decode complete request: %v", err)
			}
			writeJSON(w, http.StatusAccepted, providerRelayCompleteResponse{
				Status: "completed",
				JobID:  completed.JobID,
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:              localProviderID,
						Name:            localProviderName,
						SwarmID:         "swarm-alpha",
						OwnerMemberID:   localMemberID,
						OwnerMemberName: localMemberName,
						Status:          "available",
						Modes:           []string{"share", "both"},
						Slots:           slots{Free: 1, Total: 1},
						Models: []model{
							{
								ID:         "qwen2.5-coder:32b",
								Name:       "Qwen2.5 Coder 32B",
								SlotsFree:  1,
								SlotsTotal: 1,
							},
						},
					},
				},
			})
		case "/admin/v1/providers/register":
			registerCalls++
			if err := json.NewDecoder(r.Body).Decode(&registered); err != nil {
				t.Fatalf("decode register request: %v", err)
			}
			writeJSON(w, http.StatusCreated, registerProviderResponse{
				Status:   "registered",
				Provider: registered.Provider,
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		OllamaURL:                 backend.URL,
		InferenceHTTPClient:       backend.Client(),
		EnableProviderRelayWorker: false,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	handled, err := service.pollProviderRelayOnce(context.Background())
	if err != nil {
		t.Fatalf("poll provider relay once: %v", err)
	}
	if !handled {
		t.Fatal("expected provider relay worker to handle one stream job")
	}
	if len(chunkRequests) == 0 {
		t.Fatal("expected at least one streamed chunk")
	}
	if chunkRequests[0].ContentType != "text/event-stream" {
		t.Fatalf("expected event-stream chunk content type, got %q", chunkRequests[0].ContentType)
	}
	if completed.JobID != "relay-stream-001" {
		t.Fatalf("expected relay completion job id, got %+v", completed)
	}
	if completed.ContentType != "text/event-stream" {
		t.Fatalf("expected event-stream completion content type, got %q", completed.ContentType)
	}
	metrics := service.shareMetrics.snapshotValue()
	if metrics.ServedSessions != 1 || metrics.ServedStreamSessions != 1 {
		t.Fatalf("expected streamed share metrics to be recorded, got %+v", metrics)
	}
	if metrics.UploadedTokensEstimate <= 0 {
		t.Fatalf("expected uploaded token estimate in streamed metrics, got %+v", metrics)
	}
	if metrics.RecentUploadedTokensPS <= 0 {
		t.Fatalf("expected streamed throughput in share metrics, got %+v", metrics)
	}
	if registerCalls < 2 {
		t.Fatalf("expected active and final provider metric syncs, got %d", registerCalls)
	}
	if registered.Provider.ServedSessions != 1 {
		t.Fatalf("expected served sessions to sync to coordinator, got %+v", registered.Provider)
	}
	if registered.Provider.UploadedTokensEstimate <= 0 {
		t.Fatalf("expected uploaded token estimate to sync to coordinator, got %+v", registered.Provider)
	}
}

func TestProviderRelayWorkerReconcilesCapacityWhenStreamCompletionIsGone(t *testing.T) {
	var registered registerProviderRequest
	var registerCalls int
	localProviderID, localProviderName := localProviderIdentity()
	localMemberID, localMemberName := localMemberIdentity()

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/models" {
			writeJSON(w, http.StatusOK, map[string]any{"data": []map[string]any{{"id": "qwen2.5-coder:32b"}}})
			return
		}
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected backend path %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("data: {\"choices\":[{\"delta\":{\"content\":\"REMOTE_DONE\"}}]}\n\n"))
		_, _ = w.Write([]byte("data: [DONE]\n\n"))
	}))
	defer backend.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/providers/relay/poll":
			writeJSON(w, http.StatusOK, providerRelayPollResponse{
				JobID:         "relay-stream-gone-001",
				SessionID:     "sess-stream-gone-001",
				ResolvedModel: "qwen2.5-coder:32b",
				Stream:        true,
				Request:       json.RawMessage(`{"model":"best","stream":true,"messages":[{"role":"user","content":"hello"}]}`),
			})
		case "/admin/v1/providers/relay/chunk":
			writeJSON(w, http.StatusAccepted, providerRelayChunkResponse{
				Status: "queued",
				JobID:  "relay-stream-gone-001",
			})
		case "/admin/v1/providers/relay/complete":
			writeJSON(w, http.StatusNotFound, map[string]any{
				"error": map[string]any{"code": "RELAY_JOB_NOT_FOUND"},
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:              localProviderID,
						Name:            localProviderName,
						SwarmID:         "swarm-alpha",
						OwnerMemberID:   localMemberID,
						OwnerMemberName: localMemberName,
						Status:          "busy",
						Modes:           []string{"share", "both"},
						ActiveSessions:  1,
						Slots:           slots{Free: 0, Total: 1},
						Models: []model{
							{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 0, SlotsTotal: 1},
						},
					},
				},
			})
		case "/admin/v1/providers/register":
			registerCalls++
			if err := json.NewDecoder(r.Body).Decode(&registered); err != nil {
				t.Fatalf("decode register request: %v", err)
			}
			writeJSON(w, http.StatusCreated, registerProviderResponse{
				Status:   "registered",
				Provider: registered.Provider,
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		OllamaURL:                 backend.URL,
		InferenceHTTPClient:       backend.Client(),
		EnableProviderRelayWorker: false,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	handled, err := service.pollProviderRelayOnce(context.Background())
	if err != nil {
		t.Fatalf("poll provider relay once: %v", err)
	}
	if !handled {
		t.Fatal("expected provider relay worker to handle one stream job")
	}
	if service.shareMetrics.activeSessionCount() != 0 {
		t.Fatalf("expected local active relay count to clear, got %d", service.shareMetrics.activeSessionCount())
	}
	if registerCalls < 2 {
		t.Fatalf("expected active and final provider capacity reconciles, got %d", registerCalls)
	}
	if registered.Provider.ActiveSessions != 0 || registered.Provider.Slots.Free != 1 || registered.Provider.Models[0].SlotsFree != 1 {
		t.Fatalf("expected capacity reconcile to publish free provider, got %+v", registered.Provider)
	}
}

func TestProviderRelayWorkerSendsHeartbeatWhileStreamIsSilent(t *testing.T) {
	oldInterval := providerRelayHeartbeatInterval
	providerRelayHeartbeatInterval = 5 * time.Millisecond
	defer func() {
		providerRelayHeartbeatInterval = oldInterval
	}()

	chunkBodies := make(chan string, 16)
	var completed providerRelayCompleteRequest
	localProviderID, localProviderName := localProviderIdentity()
	localMemberID, localMemberName := localMemberIdentity()

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/models" {
			writeJSON(w, http.StatusOK, map[string]any{"data": []map[string]any{{"id": "qwen2.5-coder:32b"}}})
			return
		}
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected backend path %s", r.URL.Path)
		}
		time.Sleep(25 * time.Millisecond)
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("data: {\"choices\":[{\"delta\":{\"content\":\"REMOTE_DELAYED\"}}]}\n\n"))
		_, _ = w.Write([]byte("data: [DONE]\n\n"))
	}))
	defer backend.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/providers/relay/poll":
			writeJSON(w, http.StatusOK, providerRelayPollResponse{
				JobID:         "relay-heartbeat-001",
				SessionID:     "sess-heartbeat-001",
				ResolvedModel: "qwen2.5-coder:32b",
				Stream:        true,
				Request:       json.RawMessage(`{"model":"best","stream":true,"messages":[{"role":"user","content":"hello"}]}`),
			})
		case "/admin/v1/providers/relay/chunk":
			var req providerRelayChunkRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode chunk request: %v", err)
			}
			body, err := base64.StdEncoding.DecodeString(req.BodyBase64)
			if err != nil {
				t.Fatalf("decode chunk body: %v", err)
			}
			chunkBodies <- string(body)
			writeJSON(w, http.StatusAccepted, providerRelayChunkResponse{
				Status: "queued",
				JobID:  req.JobID,
			})
		case "/admin/v1/providers/relay/complete":
			if err := json.NewDecoder(r.Body).Decode(&completed); err != nil {
				t.Fatalf("decode complete request: %v", err)
			}
			writeJSON(w, http.StatusAccepted, providerRelayCompleteResponse{
				Status: "completed",
				JobID:  completed.JobID,
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:              localProviderID,
						Name:            localProviderName,
						SwarmID:         "swarm-alpha",
						OwnerMemberID:   localMemberID,
						OwnerMemberName: localMemberName,
						Status:          "available",
						Modes:           []string{"share", "both"},
						Slots:           slots{Free: 1, Total: 1},
						Models: []model{
							{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1},
						},
					},
				},
			})
		case "/admin/v1/providers/register":
			writeJSON(w, http.StatusCreated, registerProviderResponse{Status: "registered"})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		OllamaURL:                 backend.URL,
		InferenceHTTPClient:       backend.Client(),
		EnableProviderRelayWorker: false,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	handled, err := service.pollProviderRelayOnce(context.Background())
	if err != nil {
		t.Fatalf("poll provider relay once: %v", err)
	}
	if !handled {
		t.Fatal("expected provider relay worker to handle one stream job")
	}
	if completed.JobID != "relay-heartbeat-001" {
		t.Fatalf("expected heartbeat relay completion, got %+v", completed)
	}

	seenHeartbeat := false
	seenContent := false
	for len(chunkBodies) > 0 {
		body := <-chunkBodies
		if strings.Contains(body, "onlymacs heartbeat") {
			seenHeartbeat = true
		}
		if strings.Contains(body, "REMOTE_DELAYED") {
			seenContent = true
		}
	}
	if !seenHeartbeat {
		t.Fatal("expected heartbeat chunks while the provider stream was silent")
	}
	if !seenContent {
		t.Fatal("expected final provider stream content after heartbeat")
	}
}

func TestProviderRelayWorkerHeartbeatCancelsAbandonedSilentStream(t *testing.T) {
	oldInterval := providerRelayHeartbeatInterval
	providerRelayHeartbeatInterval = 5 * time.Millisecond
	defer func() {
		providerRelayHeartbeatInterval = oldInterval
	}()

	backendCanceled := make(chan struct{})
	var backendCancelOnce sync.Once
	var registered registerProviderRequest
	var registerCalls int
	localProviderID, localProviderName := localProviderIdentity()
	localMemberID, localMemberName := localMemberIdentity()

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/models" {
			writeJSON(w, http.StatusOK, map[string]any{"data": []map[string]any{{"id": "qwen2.5-coder:32b"}}})
			return
		}
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected backend path %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(http.StatusOK)
		if flusher, ok := w.(http.Flusher); ok {
			flusher.Flush()
		}
		<-r.Context().Done()
		backendCancelOnce.Do(func() {
			close(backendCanceled)
		})
	}))
	defer backend.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/providers/relay/poll":
			writeJSON(w, http.StatusOK, providerRelayPollResponse{
				JobID:         "relay-abandoned-silent-001",
				SessionID:     "sess-abandoned-silent-001",
				ResolvedModel: "qwen2.5-coder:32b",
				Stream:        true,
				Request:       json.RawMessage(`{"model":"best","stream":true,"messages":[{"role":"user","content":"hello"}]}`),
			})
		case "/admin/v1/providers/relay/chunk":
			writeJSON(w, http.StatusNotFound, map[string]any{
				"error": map[string]any{"code": "RELAY_JOB_NOT_FOUND"},
			})
		case "/admin/v1/providers/relay/complete":
			writeJSON(w, http.StatusNotFound, map[string]any{
				"error": map[string]any{"code": "RELAY_JOB_NOT_FOUND"},
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:              localProviderID,
						Name:            localProviderName,
						SwarmID:         "swarm-alpha",
						OwnerMemberID:   localMemberID,
						OwnerMemberName: localMemberName,
						Status:          "busy",
						Modes:           []string{"share", "both"},
						ActiveSessions:  1,
						Slots:           slots{Free: 0, Total: 1},
						Models: []model{
							{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 0, SlotsTotal: 1},
						},
					},
				},
			})
		case "/admin/v1/providers/register":
			registerCalls++
			if err := json.NewDecoder(r.Body).Decode(&registered); err != nil {
				t.Fatalf("decode register request: %v", err)
			}
			writeJSON(w, http.StatusCreated, registerProviderResponse{
				Status:   "registered",
				Provider: registered.Provider,
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		OllamaURL:                 backend.URL,
		InferenceHTTPClient:       backend.Client(),
		EnableProviderRelayWorker: false,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	done := make(chan error, 1)
	go func() {
		handled, err := service.pollProviderRelayOnce(context.Background())
		if err != nil {
			done <- err
			return
		}
		if !handled {
			done <- errors.New("provider relay worker did not handle abandoned job")
			return
		}
		done <- nil
	}()

	select {
	case <-backendCanceled:
	case <-time.After(250 * time.Millisecond):
		t.Fatal("expected heartbeat rejection to cancel the silent upstream inference request")
	}

	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("poll provider relay once: %v", err)
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("expected provider relay worker to exit after heartbeat cancellation")
	}
	if service.shareMetrics.activeSessionCount() != 0 {
		t.Fatalf("expected local active relay count to clear, got %d", service.shareMetrics.activeSessionCount())
	}
	if registerCalls < 2 {
		t.Fatalf("expected active and final provider capacity reconciles, got %d", registerCalls)
	}
	if registered.Provider.ActiveSessions != 0 || registered.Provider.Slots.Free != 1 || registered.Provider.Models[0].SlotsFree != 1 {
		t.Fatalf("expected heartbeat-cancelled relay to publish free provider, got %+v", registered.Provider)
	}
}

func TestRemoteRelayChatCompletion(t *testing.T) {
	var reserveCalls int
	var releaseCalls int
	var relayCalls int

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/sessions/reserve":
			reserveCalls++
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-remote-001",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:32b",
				Provider: preflightProvider{
					ID:             "charles-m5",
					Name:           "Charles's Mac Studio",
					Status:         "available",
					ActiveSessions: 1,
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/relay/execute":
			relayCalls++
			writeJSON(w, http.StatusOK, relayExecuteResponse{
				JobID:       "relay-remote-001",
				StatusCode:  http.StatusOK,
				ContentType: "application/json",
				BodyBase64:  base64.StdEncoding.EncodeToString([]byte(`{"choices":[{"message":{"role":"assistant","content":"REMOTE_OK"}}]}`)),
			})
		case "/admin/v1/sessions/release":
			releaseCalls++
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "sess-remote-001",
				Status:    "released",
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", strings.NewReader(`{"model":"best-available","stream":false,"messages":[{"role":"user","content":"Reply with REMOTE_OK exactly."}]}`))
	rec := httptest.NewRecorder()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		CannedChat:                false,
		EnableProviderRelayWorker: false,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, rec.Code)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte("REMOTE_OK")) {
		t.Fatalf("expected remote relay body, got %s", rec.Body.String())
	}
	if reserveCalls != 1 {
		t.Fatalf("expected 1 reserve call, got %d", reserveCalls)
	}
	if relayCalls != 1 {
		t.Fatalf("expected 1 relay execute call, got %d", relayCalls)
	}
	if releaseCalls != 0 {
		t.Fatalf("expected remote relay completion to own release instead of the requester bridge, got %d release calls", releaseCalls)
	}
}

func TestRemoteRelayChatCompletionForwardsRequestedAvoidAndExcludeProviders(t *testing.T) {
	var reserveReq reserveSessionRequest
	localProviderID, _ := localProviderIdentity()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/sessions/reserve":
			if err := json.NewDecoder(r.Body).Decode(&reserveReq); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-requested-route-lists",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:32b",
				Provider: preflightProvider{
					ID:             "charles-m5",
					Name:           "Charles's Mac Studio",
					Status:         "available",
					ActiveSessions: 1,
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/relay/execute":
			writeJSON(w, http.StatusOK, relayExecuteResponse{
				JobID:       "relay-requested-route-lists",
				StatusCode:  http.StatusOK,
				ContentType: "application/json",
				BodyBase64:  base64.StdEncoding.EncodeToString([]byte(`{"choices":[{"message":{"role":"assistant","content":"ROUTE_LISTS_OK"}}]}`)),
			})
		case "/admin/v1/sessions/release":
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "sess-requested-route-lists",
				Status:    "released",
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", strings.NewReader(`{"model":"","stream":false,"route_scope":"swarm","prefer_remote":true,"avoid_provider_ids":[" provider-old ","provider-old"],"exclude_provider_ids":["provider-bad"],"messages":[{"role":"user","content":"Reply with ROUTE_LISTS_OK exactly."}]}`))
	rec := httptest.NewRecorder()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		CannedChat:                false,
		EnableProviderRelayWorker: false,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if got := strings.Join(reserveReq.AvoidProviderIDs, ","); got != "provider-old" {
		t.Fatalf("expected requested avoid provider to be normalized and forwarded, got %+v", reserveReq.AvoidProviderIDs)
	}
	if got := strings.Join(reserveReq.ExcludeProviderIDs, ","); got != localProviderID+",provider-bad" {
		t.Fatalf("expected route and requested exclude providers to be forwarded, got %+v", reserveReq.ExcludeProviderIDs)
	}
}

func TestRemoteRelayChatCompletionForwardsReasoningControlsToCoordinator(t *testing.T) {
	var relayedReq chatCompletionsRequest

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/sessions/reserve":
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-reasoning-controls",
				Status:        "reserved",
				ResolvedModel: "qwen3.6:35b-a3b-q8_0",
				Provider: preflightProvider{
					ID:             "charles-m5",
					Name:           "Charles's Mac Studio",
					Status:         "available",
					ActiveSessions: 1,
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/relay/execute":
			var relayReq relayExecuteRequest
			if err := json.NewDecoder(r.Body).Decode(&relayReq); err != nil {
				t.Fatalf("decode relay execute request: %v", err)
			}
			if err := json.Unmarshal(relayReq.Request, &relayedReq); err != nil {
				t.Fatalf("decode relayed chat request: %v", err)
			}
			writeJSON(w, http.StatusOK, relayExecuteResponse{
				JobID:       "relay-reasoning-controls",
				StatusCode:  http.StatusOK,
				ContentType: "application/json",
				BodyBase64:  base64.StdEncoding.EncodeToString([]byte(`{"choices":[{"message":{"role":"assistant","content":"REASONING_CONTROLS_OK"}}]}`)),
			})
		case "/admin/v1/sessions/release":
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "sess-reasoning-controls",
				Status:    "released",
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", strings.NewReader(`{"model":"qwen3.6:35b-a3b-q8_0","stream":false,"route_scope":"swarm","prefer_remote":true,"reasoning_effort":"low","reasoning":{"budget_tokens":1024},"think":false,"messages":[{"role":"user","content":"Reply with REASONING_CONTROLS_OK exactly."}]}`))
	rec := httptest.NewRecorder()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		CannedChat:                false,
		EnableProviderRelayWorker: false,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if relayedReq.ReasoningEffort != "low" {
		t.Fatalf("expected reasoning_effort to reach coordinator relay, got %q", relayedReq.ReasoningEffort)
	}
	if string(relayedReq.Reasoning) != `{"budget_tokens":1024}` {
		t.Fatalf("expected reasoning control to reach coordinator relay, got %s", string(relayedReq.Reasoning))
	}
	if string(relayedReq.Think) != `false` {
		t.Fatalf("expected think control to reach coordinator relay, got %s", string(relayedReq.Think))
	}
}

func TestRemoteRelayChatCompletionRemoteFirstExcludesLocalProvider(t *testing.T) {
	localProviderID, _ := localProviderIdentity()
	var reserveReq reserveSessionRequest

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/sessions/reserve":
			if err := json.NewDecoder(r.Body).Decode(&reserveReq); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-remote-first-001",
				Status:        "reserved",
				ResolvedModel: "gemma3:27b",
				Provider: preflightProvider{
					ID:             "charles-m5",
					Name:           "Charles's Mac Studio",
					Status:         "available",
					ActiveSessions: 1,
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/relay/execute":
			writeJSON(w, http.StatusOK, relayExecuteResponse{
				JobID:       "relay-remote-first-001",
				StatusCode:  http.StatusOK,
				ContentType: "application/json",
				BodyBase64:  base64.StdEncoding.EncodeToString([]byte(`{"choices":[{"message":{"role":"assistant","content":"REMOTE_FIRST_OK"}}]}`)),
			})
		case "/admin/v1/sessions/release":
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "sess-remote-first-001",
				Status:    "released",
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", strings.NewReader(`{"model":"","stream":false,"route_scope":"swarm","prefer_remote":true,"messages":[{"role":"user","content":"Reply with REMOTE_FIRST_OK exactly."}]}`))
	rec := httptest.NewRecorder()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		CannedChat:                false,
		EnableProviderRelayWorker: false,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte("REMOTE_FIRST_OK")) {
		t.Fatalf("expected remote-first relay body, got %s", rec.Body.String())
	}
	if len(reserveReq.ExcludeProviderIDs) != 1 || reserveReq.ExcludeProviderIDs[0] != localProviderID {
		t.Fatalf("expected remote-first to exclude local provider %q, got %+v", localProviderID, reserveReq)
	}
}

func TestRemoteRelayChatCompletionStream(t *testing.T) {
	var reserveCalls int
	var releaseCalls int
	var relayCalls int

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/sessions/reserve":
			reserveCalls++
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-remote-stream-001",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:32b",
				Provider: preflightProvider{
					ID:             "charles-m5",
					Name:           "Charles's Mac Studio",
					Status:         "available",
					ActiveSessions: 1,
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/relay/execute":
			relayCalls++
			w.Header().Set("Content-Type", "text/event-stream")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("data: {\"choices\":[{\"delta\":{\"content\":\"REMOTE_\"}}]}\n\n"))
			_, _ = w.Write([]byte("data: {\"choices\":[{\"delta\":{\"content\":\"STREAM_OK\"}}]}\n\n"))
			_, _ = w.Write([]byte("data: [DONE]\n\n"))
		case "/admin/v1/sessions/release":
			releaseCalls++
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "sess-remote-stream-001",
				Status:    "released",
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", strings.NewReader(`{"model":"best-available","stream":true,"messages":[{"role":"user","content":"Reply with REMOTE_STREAM_OK exactly."}]}`))
	rec := httptest.NewRecorder()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		CannedChat:                false,
		EnableProviderRelayWorker: false,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, rec.Code)
	}
	if contentType := rec.Header().Get("Content-Type"); !strings.Contains(contentType, "text/event-stream") {
		t.Fatalf("expected event-stream content type, got %q", contentType)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"content":"REMOTE_"`)) {
		t.Fatalf("expected first remote stream delta, got %s", rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"content":"STREAM_OK"`)) {
		t.Fatalf("expected remote stream relay body, got %s", rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte("[DONE]")) {
		t.Fatalf("expected DONE marker, got %s", rec.Body.String())
	}
	if reserveCalls != 1 {
		t.Fatalf("expected 1 reserve call, got %d", reserveCalls)
	}
	if relayCalls != 1 {
		t.Fatalf("expected 1 relay execute call, got %d", relayCalls)
	}
	if releaseCalls != 0 {
		t.Fatalf("expected remote relay completion to own release instead of the requester bridge, got %d release calls", releaseCalls)
	}
}

func TestSoftRemotePreferenceAvoidsLocalProviderButFallsBackCleanly(t *testing.T) {
	localProviderID, _ := localProviderIdentity()
	var reserveReq reserveSessionRequest

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/sessions/reserve":
			if err := json.NewDecoder(r.Body).Decode(&reserveReq); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-soft-remote-001",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:14b",
				Provider: preflightProvider{
					ID:             "charles-m5",
					Name:           "Charles's Mac Studio",
					Status:         "available",
					ActiveSessions: 1,
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/relay/execute":
			writeJSON(w, http.StatusOK, relayExecuteResponse{
				JobID:       "relay-soft-remote-001",
				StatusCode:  http.StatusOK,
				ContentType: "application/json",
				BodyBase64:  base64.StdEncoding.EncodeToString([]byte(`{"choices":[{"message":{"role":"assistant","content":"SOFT_REMOTE_OK"}}]}`)),
			})
		case "/admin/v1/sessions/release":
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "sess-soft-remote-001",
				Status:    "released",
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", strings.NewReader(`{"model":"","stream":false,"route_scope":"swarm","prefer_remote_soft":true,"messages":[{"role":"user","content":"Reply with SOFT_REMOTE_OK exactly."}]}`))
	rec := httptest.NewRecorder()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		CannedChat:                false,
		EnableProviderRelayWorker: false,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte("SOFT_REMOTE_OK")) {
		t.Fatalf("expected soft-remote relay body, got %s", rec.Body.String())
	}
	if len(reserveReq.AvoidProviderIDs) != 1 || reserveReq.AvoidProviderIDs[0] != localProviderID {
		t.Fatalf("expected soft remote preference to avoid local provider %q, got %+v", localProviderID, reserveReq)
	}
	if len(reserveReq.ExcludeProviderIDs) != 0 {
		t.Fatalf("expected soft remote preference not to exclude local provider entirely, got %+v", reserveReq)
	}
}

func TestRemoteRelayChatTrustedOnlyPreservesRouteScope(t *testing.T) {
	var reserveReq reserveSessionRequest

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/sessions/reserve":
			if err := json.NewDecoder(r.Body).Decode(&reserveReq); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-remote-trusted-001",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:32b",
				Provider: preflightProvider{
					ID:             "kevin-macbook",
					Name:           "Kevin's MacBook Pro",
					Status:         "available",
					ActiveSessions: 1,
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/relay/execute":
			writeJSON(w, http.StatusOK, relayExecuteResponse{
				JobID:       "relay-trusted-001",
				StatusCode:  http.StatusOK,
				ContentType: "application/json",
				BodyBase64:  base64.StdEncoding.EncodeToString([]byte(`{"choices":[{"message":{"role":"assistant","content":"TRUSTED_ONLY_OK"}}]}`)),
			})
		case "/admin/v1/sessions/release":
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "sess-remote-trusted-001",
				Status:    "released",
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", strings.NewReader(`{"model":"","stream":false,"route_scope":"trusted_only","messages":[{"role":"user","content":"Reply with TRUSTED_ONLY_OK exactly."}]}`))
	rec := httptest.NewRecorder()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		RelayHTTPClient:           coordinator.Client(),
		CannedChat:                false,
		EnableProviderRelayWorker: false,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, rec.Code)
	}
	if reserveReq.RouteScope != "trusted_only" {
		t.Fatalf("expected trusted_only route scope, got %+v", reserveReq)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte("TRUSTED_ONLY_OK")) {
		t.Fatalf("expected remote relay body, got %s", rec.Body.String())
	}
}
