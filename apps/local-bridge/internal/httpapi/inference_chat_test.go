package httpapi

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestLocalInferenceProxyStream(t *testing.T) {
	var reserveCalls int
	var releaseCalls int
	var reservedModel string
	var forwardedModel string
	var forwardedPrompt string
	localProviderID, _ := localProviderIdentity()

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected backend path %s", r.URL.Path)
		}

		var req chatCompletionsRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode backend request: %v", err)
		}
		forwardedModel = req.Model
		if len(req.Messages) > 0 {
			forwardedPrompt = req.Messages[0].Content
		}

		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("data: {\"choices\":[{\"delta\":{\"content\":\"ONLYMACS_SMOKE_OK\"}}]}\n\n"))
		_, _ = w.Write([]byte("data: [DONE]\n\n"))
	}))
	defer backend.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/sessions/reserve":
			reserveCalls++
			var req reserveSessionRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
			reservedModel = req.Model
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-000001",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:32b",
				Provider: preflightProvider{
					ID:             localProviderID,
					Name:           "This Mac",
					Status:         "available",
					ActiveSessions: 1,
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/sessions/release":
			releaseCalls++
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "sess-000001",
				Status:    "released",
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", strings.NewReader(`{"model":"best-available","stream":true,"messages":[{"role":"user","content":"Reply with ONLYMACS_SMOKE_OK exactly."}]}`))
	rec := httptest.NewRecorder()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		CannedChat:          false,
		OllamaURL:           backend.URL,
		InferenceHTTPClient: backend.Client(),
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
	if !bytes.Contains(rec.Body.Bytes(), []byte("ONLYMACS_SMOKE_OK")) {
		t.Fatalf("expected proxied stream content, got %s", rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte("[DONE]")) {
		t.Fatalf("expected DONE marker, got %s", rec.Body.String())
	}
	if forwardedModel != "qwen2.5-coder:32b" {
		t.Fatalf("expected resolved model to be forwarded, got %q", forwardedModel)
	}
	if reservedModel != "" {
		t.Fatalf("expected best-available alias to be resolved as coordinator best available, got %q", reservedModel)
	}
	if forwardedPrompt != "Reply with ONLYMACS_SMOKE_OK exactly." {
		t.Fatalf("expected prompt to survive proxy, got %q", forwardedPrompt)
	}
	if reserveCalls != 1 {
		t.Fatalf("expected 1 reserve call, got %d", reserveCalls)
	}
	if releaseCalls != 1 {
		t.Fatalf("expected 1 release call, got %d", releaseCalls)
	}
}

func TestLocalInferenceProxyStreamHydratesOnlyMacsArtifact(t *testing.T) {
	var reserveCalls int
	var releaseCalls int
	var forwardedModel string
	var forwardedPrompt string
	var artifactPresent bool
	localProviderID, _ := localProviderIdentity()

	artifactPayload := testOnlyMacsArtifactPayload(t, map[string]string{
		"docs/1 - MASTER LANGUAGE INTAKE.md": "# Intake\nReal pipeline guidance here.\n",
	})

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected backend path %s", r.URL.Path)
		}

		var req chatCompletionsRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode backend request: %v", err)
		}
		forwardedModel = req.Model
		artifactPresent = req.OnlyMacsArtifact != nil
		if len(req.Messages) > 0 {
			forwardedPrompt = req.Messages[0].Content
		}

		w.Header().Set("Content-Type", "text/event-stream")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("data: {\"choices\":[{\"delta\":{\"content\":\"ONLYMACS_ARTIFACT_OK\"}}]}\n\n"))
		_, _ = w.Write([]byte("data: [DONE]\n\n"))
	}))
	defer backend.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/sessions/reserve":
			reserveCalls++
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-artifact-001",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:32b",
				Provider: preflightProvider{
					ID:             localProviderID,
					Name:           "This Mac",
					Status:         "available",
					ActiveSessions: 1,
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/sessions/release":
			releaseCalls++
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "sess-artifact-001",
				Status:    "released",
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	body, err := json.Marshal(chatCompletionsRequest{
		Model:            "best-available",
		Stream:           true,
		OnlyMacsArtifact: artifactPayload,
		Messages: []chatMessage{{
			Role:    "user",
			Content: "Review the pipeline docs in this project.",
		}},
	})
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", bytes.NewReader(body))
	rec := httptest.NewRecorder()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		CannedChat:          false,
		OllamaURL:           backend.URL,
		InferenceHTTPClient: backend.Client(),
	})

	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, rec.Code)
	}
	if artifactPresent {
		t.Fatalf("expected artifact to be consumed before upstream inference")
	}
	if !strings.Contains(forwardedPrompt, "MASTER LANGUAGE INTAKE") {
		t.Fatalf("expected hydrated file context in forwarded prompt, got %q", forwardedPrompt)
	}
	if !strings.Contains(forwardedPrompt, "OnlyMacs trusted file bundle") {
		t.Fatalf("expected artifact header in forwarded prompt, got %q", forwardedPrompt)
	}
	if !strings.Contains(forwardedPrompt, "Return these sections in this order: Findings, Open Questions, Referenced Files") {
		t.Fatalf("expected grounded review contract in forwarded prompt, got %q", forwardedPrompt)
	}
	if !strings.Contains(forwardedPrompt, "Evidence line") {
		t.Fatalf("expected evidence requirement in forwarded prompt, got %q", forwardedPrompt)
	}
	if !strings.Contains(forwardedPrompt, "docs/example/path.md:12-18") {
		t.Fatalf("expected line-aware evidence requirement in forwarded prompt, got %q", forwardedPrompt)
	}
	if !strings.Contains(forwardedPrompt, "Master Docs, then Overview, then Source, then Config, then Scripts") {
		t.Fatalf("expected category weighting guidance in forwarded prompt, got %q", forwardedPrompt)
	}
	if forwardedModel != "qwen2.5-coder:32b" {
		t.Fatalf("expected resolved model to be forwarded, got %q", forwardedModel)
	}
	if reserveCalls != 1 || releaseCalls != 1 {
		t.Fatalf("expected one reserve and one release call, got reserve=%d release=%d", reserveCalls, releaseCalls)
	}
}

func TestLocalInferenceForwardsReasoningControlsThroughArtifactHydration(t *testing.T) {
	var forwarded chatCompletionsRequest
	artifactPayload := testOnlyMacsArtifactPayload(t, map[string]string{
		"docs/README.md": "# Overview\nApproved context\n",
	})

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if err := json.NewDecoder(r.Body).Decode(&forwarded); err != nil {
			t.Fatalf("decode backend request: %v", err)
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"OK"}}]}`))
	}))
	defer backend.Close()

	client := &inferenceClient{
		baseURL:    backend.URL,
		httpClient: backend.Client(),
	}
	_, _, _, err := client.executeChatCompletions(context.Background(), chatCompletionsRequest{
		Model:            "best-available",
		Stream:           false,
		ReasoningEffort:  "high",
		Reasoning:        json.RawMessage(`{"budget_tokens":2048}`),
		Think:            json.RawMessage(`true`),
		OnlyMacsArtifact: artifactPayload,
		Messages: []chatMessage{{
			Role:    "user",
			Content: "Review these docs.",
		}},
	}, "qwen3.6:35b-a3b-q8_0")
	if err != nil {
		t.Fatalf("execute chat completions: %v", err)
	}
	if forwarded.ReasoningEffort != "high" {
		t.Fatalf("expected reasoning_effort to reach upstream, got %q", forwarded.ReasoningEffort)
	}
	if string(forwarded.Reasoning) != `{"budget_tokens":2048}` {
		t.Fatalf("expected reasoning object to reach upstream unchanged, got %s", string(forwarded.Reasoning))
	}
	if string(forwarded.Think) != `true` {
		t.Fatalf("expected think control to reach upstream unchanged, got %s", string(forwarded.Think))
	}
	if forwarded.OnlyMacsArtifact != nil {
		t.Fatalf("expected artifact to be consumed before upstream inference")
	}
	if len(forwarded.Messages) == 0 || !strings.Contains(forwarded.Messages[0].Content, "OnlyMacs trusted file bundle") {
		t.Fatalf("expected hydrated artifact context to survive forwarding, got %+v", forwarded.Messages)
	}
}

func TestLocalInferenceExecutesCodexToolAgainstArtifactWorkspace(t *testing.T) {
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
printf '{"lesson":"hello"}\n' > "$workdir/generated/result.json"
printf 'repo-specific review complete\n' > "$output"
`
	if err := os.WriteFile(codexPath, []byte(script), 0o755); err != nil {
		t.Fatalf("write fake codex: %v", err)
	}
	if err := os.Setenv("PATH", tempDir+string(os.PathListSeparator)+originalPath); err != nil {
		t.Fatalf("set PATH: %v", err)
	}

	artifactPayload := testOnlyMacsArtifactPayload(t, map[string]string{
		"docs/1 - MASTER LANGUAGE INTAKE.md": "# Intake\nReal pipeline guidance here.\n",
	})
	artifactPayload.Manifest.ToolName = "Codex"

	client := &inferenceClient{}
	statusCode, headers, body, err := client.executeChatCompletions(context.Background(), chatCompletionsRequest{
		Model:            "best-available",
		Stream:           false,
		OnlyMacsArtifact: artifactPayload,
		Messages: []chatMessage{{
			Role:    "user",
			Content: "Review the pipeline docs and generate a JSON artifact.",
		}},
	}, "ignored")
	if err != nil {
		t.Fatalf("execute chat completions: %v", err)
	}
	if statusCode != http.StatusOK {
		t.Fatalf("expected status 200, got %d", statusCode)
	}
	if got := headers.Get("Content-Type"); got != "application/json" {
		t.Fatalf("expected application/json content type, got %q", got)
	}
	assistantContent := extractOnlyMacsAssistantContent(body)
	if !strings.Contains(assistantContent, "repo-specific review complete") {
		t.Fatalf("expected tool result in response body, got %s", assistantContent)
	}
	if !strings.Contains(assistantContent, "generated/result.json") {
		t.Fatalf("expected generated file summary in response body, got %s", assistantContent)
	}
	if !strings.Contains(assistantContent, "\"lesson\":\"hello\"") {
		t.Fatalf("expected generated file contents in response body, got %s", assistantContent)
	}
}

func TestRenderOnlyMacsArtifactContextUsesTaskSpecificContracts(t *testing.T) {
	cases := []struct {
		name             string
		requestIntent    string
		outputContract   string
		requiredSections []string
		wantContains     []string
	}{
		{
			name:             "code_review",
			requestIntent:    "grounded_code_review",
			outputContract:   "code_review_findings",
			requiredSections: []string{"Findings", "Missing Tests", "Referenced Files"},
			wantContains: []string{
				"Grounded code review contract",
				"Return these sections in this order: Findings, Missing Tests, Referenced Files",
				"Weight stronger evidence first. Prefer Source, then Config, then Overview",
			},
		},
		{
			name:             "generation",
			requestIntent:    "grounded_generation",
			outputContract:   "proposed_outputs",
			requiredSections: []string{"Proposed Output", "Open Questions", "Referenced Files"},
			wantContains: []string{
				"Grounded generation contract",
				"Return these sections in this order: Proposed Output, Open Questions, Referenced Files",
				"Target: path/to/output.ext",
			},
		},
		{
			name:             "transform",
			requestIntent:    "grounded_transform",
			outputContract:   "proposed_changes",
			requiredSections: []string{"Proposed Changes", "Open Questions", "Referenced Files"},
			wantContains: []string{
				"Grounded transform contract",
				"Return these sections in this order: Proposed Changes, Open Questions, Referenced Files",
				"Change: one concise sentence describing the edit.",
			},
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			payload := testOnlyMacsArtifactPayload(t, map[string]string{
				"docs/README.md": "# Overview\nApproved context\n",
			})
			payload.Manifest.RequestIntent = tc.requestIntent
			payload.Manifest.OutputContract = tc.outputContract
			payload.Manifest.RequiredSections = tc.requiredSections

			rootDir, cleanup, err := stageOnlyMacsArtifact(payload)
			if err != nil {
				t.Fatalf("stage artifact: %v", err)
			}
			defer cleanup()

			rendered := renderOnlyMacsArtifactContext(payload, rootDir)
			for _, snippet := range tc.wantContains {
				if !strings.Contains(rendered, snippet) {
					t.Fatalf("expected rendered context to contain %q, got %q", snippet, rendered)
				}
			}
		})
	}
}

func TestLocalInferenceFallsBackToArtifactHydrationWhenCodexWorkspaceExecFails(t *testing.T) {
	originalLookPath := onlyMacsExecLookPath
	onlyMacsExecLookPath = func(file string) (string, error) {
		return "", os.ErrNotExist
	}
	t.Cleanup(func() {
		onlyMacsExecLookPath = originalLookPath
	})

	var forwardedPrompt string
	artifactPayload := testOnlyMacsArtifactPayload(t, map[string]string{
		"docs/1 - MASTER LANGUAGE INTAKE.md": "# Intake\nGrounded pipeline guidance here.\n",
	})
	artifactPayload.Manifest.ToolName = "Codex"

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req chatCompletionsRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode backend request: %v", err)
		}
		if req.OnlyMacsArtifact != nil {
			t.Fatal("expected artifact to be consumed before fallback inference")
		}
		if len(req.Messages) > 0 {
			forwardedPrompt = req.Messages[0].Content
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"FALLBACK_ARTIFACT_OK"}}]}`))
	}))
	defer backend.Close()

	client := &inferenceClient{
		baseURL:    backend.URL,
		httpClient: backend.Client(),
	}
	statusCode, headers, body, err := client.executeChatCompletions(context.Background(), chatCompletionsRequest{
		Model:            "best-available",
		Stream:           false,
		OnlyMacsArtifact: artifactPayload,
		Messages: []chatMessage{{
			Role:    "user",
			Content: "Review these pipeline docs.",
		}},
	}, "qwen2.5-coder:32b")
	if err != nil {
		t.Fatalf("execute chat completions: %v", err)
	}
	if statusCode != http.StatusOK {
		t.Fatalf("expected status 200, got %d", statusCode)
	}
	if got := headers.Get("Content-Type"); got != "application/json" {
		t.Fatalf("expected application/json content type, got %q", got)
	}
	if !strings.Contains(forwardedPrompt, "OnlyMacs trusted file bundle") {
		t.Fatalf("expected fallback prompt to include approved-file context, got %q", forwardedPrompt)
	}
	if !strings.Contains(forwardedPrompt, "MASTER LANGUAGE INTAKE") {
		t.Fatalf("expected fallback prompt to include approved file contents, got %q", forwardedPrompt)
	}
	if !strings.Contains(forwardedPrompt, "Referenced Files") {
		t.Fatalf("expected fallback prompt to require referenced files, got %q", forwardedPrompt)
	}
	if !bytes.Contains(body, []byte("FALLBACK_ARTIFACT_OK")) {
		t.Fatalf("expected backend fallback response, got %s", string(body))
	}
}

func TestOnlyMacsArtifactManifestDecodesCamelCaseKeys(t *testing.T) {
	payloadJSON := `{
		"export_mode":"trusted_review_full",
		"bundle_base64":"ZmFrZQ==",
		"bundle_sha256":"abc",
		"manifest":{
			"schema":"context_capsule.v2",
			"capsuleID":"capsule-camel",
			"id":"artifact-camel",
			"requestID":"request-camel",
			"createdAt":"2026-04-18T12:00:00Z",
			"expiresAt":"2026-04-18T12:30:00Z",
			"workspaceRoot":"/tmp/workspace",
			"workspaceRootLabel":"workspace",
			"workspaceFingerprint":"abc12345",
			"routeScope":"trusted_only",
			"trustTier":"private_trusted",
			"absolutePathsIncluded":true,
			"swarmName":"Friends",
			"toolName":"Codex",
			"promptSummary":"Review the pipeline docs.",
			"requestIntent":"grounded_review",
			"exportMode":"trusted_review_full",
			"outputContract":"categorized_findings",
			"requiredSections":["Findings","Open Questions","Referenced Files"],
			"groundingRules":["Base every material claim only on the approved files in this bundle."],
			"permissions":{
				"allowContextRequests":true,
				"maxContextRequestRounds":2,
				"allowSourceMutation":false,
				"allowStagedMutation":false,
				"allowOutputArtifacts":true
			},
			"budgets":{
				"max_file_bytes":180000,
				"max_total_bytes":480000,
				"max_scan_bytes":200000,
				"requires_full_files":true,
				"allow_trimming":false
			},
			"contextPacks":[
				{
					"id":"docs-review",
					"description":"Readable docs, READMEs, guides, and prompts for doc-grounded review tasks.",
					"scope":"public_safe",
					"source":"built_in",
					"matchedFiles":["docs/README.md"]
				}
			],
			"files":[
				{
					"path":"/tmp/workspace/docs/README.md",
					"relativePath":"docs/README.md",
					"category":"Docs",
					"selectionReason":"Project overview and usage notes",
					"isRecommended":true,
					"reviewPriority":94,
					"evidenceHints":["Overview","Usage notes"],
					"evidenceAnchors":[
						{"kind":"heading","lineStart":4,"lineEnd":4,"text":"Overview"},
						{"kind":"snippet","lineStart":12,"lineEnd":12,"text":"Usage notes"}
					],
					"originalBytes":1200,
					"exportedBytes":900,
					"status":"trimmed",
					"reason":"trimmed for preview",
					"sha256":"abc123"
				}
			],
			"blocked":[
				{
					"relativePath":".env",
					"status":"blocked",
					"reason":"This looks like a secret or credential file."
				}
			],
			"warnings":["trimmed"],
			"approval":{
				"approvalRequired":true,
				"requestedAt":"2026-04-18T12:00:00Z",
				"approvedAt":"2026-04-18T12:00:30Z",
				"selectedCount":2,
				"exportableCount":1
			},
			"totalSelectedBytes":1200,
			"totalExportBytes":900
		}
	}`

	var payload onlyMacsArtifactPayload
	if err := json.Unmarshal([]byte(payloadJSON), &payload); err != nil {
		t.Fatalf("decode artifact payload: %v", err)
	}

	if payload.Manifest.WorkspaceRoot != "/tmp/workspace" {
		t.Fatalf("expected workspace root to decode from camelCase, got %q", payload.Manifest.WorkspaceRoot)
	}
	if payload.Manifest.Schema != "context_capsule.v2" {
		t.Fatalf("expected schema to decode, got %q", payload.Manifest.Schema)
	}
	if payload.Manifest.CapsuleID != "capsule-camel" {
		t.Fatalf("expected capsule id to decode, got %q", payload.Manifest.CapsuleID)
	}
	if payload.Manifest.RequestID != "request-camel" {
		t.Fatalf("expected request id to decode, got %q", payload.Manifest.RequestID)
	}
	if payload.Manifest.ExpiresAt != "2026-04-18T12:30:00Z" {
		t.Fatalf("expected expiresAt to decode from camelCase, got %q", payload.Manifest.ExpiresAt)
	}
	if payload.Manifest.WorkspaceRootLabel != "workspace" {
		t.Fatalf("expected workspace label to decode, got %q", payload.Manifest.WorkspaceRootLabel)
	}
	if payload.Manifest.WorkspaceFingerprint != "abc12345" {
		t.Fatalf("expected workspace fingerprint to decode, got %q", payload.Manifest.WorkspaceFingerprint)
	}
	if payload.Manifest.TrustTier != "private_trusted" {
		t.Fatalf("expected trust tier to decode, got %q", payload.Manifest.TrustTier)
	}
	if !payload.Manifest.AbsolutePathsIncluded {
		t.Fatalf("expected absolute path flag to decode")
	}
	if payload.Manifest.ToolName != "Codex" {
		t.Fatalf("expected tool name to decode from camelCase, got %q", payload.Manifest.ToolName)
	}
	if payload.Manifest.RequestIntent != "grounded_review" {
		t.Fatalf("expected request intent to decode from camelCase, got %q", payload.Manifest.RequestIntent)
	}
	if payload.Manifest.OutputContract != "categorized_findings" {
		t.Fatalf("expected output contract to decode from camelCase, got %q", payload.Manifest.OutputContract)
	}
	if payload.Manifest.TotalExportBytes != 900 {
		t.Fatalf("expected total export bytes to decode from camelCase, got %d", payload.Manifest.TotalExportBytes)
	}
	if len(payload.Manifest.RequiredSections) != 3 {
		t.Fatalf("expected required sections to decode from camelCase, got %#v", payload.Manifest.RequiredSections)
	}
	if len(payload.Manifest.Files) != 1 {
		t.Fatalf("expected one manifest file, got %d", len(payload.Manifest.Files))
	}
	if payload.Manifest.Files[0].RelativePath != "docs/README.md" {
		t.Fatalf("expected relative path to decode from camelCase, got %q", payload.Manifest.Files[0].RelativePath)
	}
	if payload.Manifest.Files[0].Category != "Docs" {
		t.Fatalf("expected category to decode, got %q", payload.Manifest.Files[0].Category)
	}
	if payload.Manifest.Files[0].SelectionReason != "Project overview and usage notes" {
		t.Fatalf("expected selection reason to decode, got %q", payload.Manifest.Files[0].SelectionReason)
	}
	if !payload.Manifest.Files[0].IsRecommended {
		t.Fatalf("expected recommended flag to decode")
	}
	if payload.Manifest.Files[0].ReviewPriority != 94 {
		t.Fatalf("expected review priority to decode from camelCase, got %d", payload.Manifest.Files[0].ReviewPriority)
	}
	if len(payload.Manifest.Files[0].EvidenceHints) != 2 {
		t.Fatalf("expected evidence hints to decode from camelCase, got %#v", payload.Manifest.Files[0].EvidenceHints)
	}
	if len(payload.Manifest.Files[0].EvidenceAnchors) != 2 {
		t.Fatalf("expected evidence anchors to decode from camelCase, got %#v", payload.Manifest.Files[0].EvidenceAnchors)
	}
	if payload.Manifest.Files[0].EvidenceAnchors[0].LineStart != 4 {
		t.Fatalf("expected evidence anchor line start to decode from camelCase, got %d", payload.Manifest.Files[0].EvidenceAnchors[0].LineStart)
	}
	if payload.Manifest.Files[0].ExportedBytes != 900 {
		t.Fatalf("expected exported bytes to decode from camelCase, got %d", payload.Manifest.Files[0].ExportedBytes)
	}
	if len(payload.Manifest.ContextPacks) != 1 || payload.Manifest.ContextPacks[0].ID != "docs-review" {
		t.Fatalf("expected context packs to decode from camelCase, got %#v", payload.Manifest.ContextPacks)
	}
	if len(payload.Manifest.Blocked) != 1 || payload.Manifest.Blocked[0].RelativePath != ".env" {
		t.Fatalf("expected blocked files to decode, got %#v", payload.Manifest.Blocked)
	}
	if !payload.Manifest.Approval.ApprovalRequired {
		t.Fatalf("expected approval metadata to decode, got %#v", payload.Manifest.Approval)
	}
}

func TestStageOnlyMacsArtifactRejectsExpiredCapsule(t *testing.T) {
	artifact := testOnlyMacsArtifactPayload(t, map[string]string{
		"docs/README.md": "# Overview\ncontent\n",
	})
	artifact.Manifest.ExpiresAt = time.Now().Add(-time.Minute).UTC().Format(time.RFC3339)
	if _, cleanup, err := stageOnlyMacsArtifact(artifact); err == nil {
		cleanup()
		t.Fatalf("expected expired capsule to fail")
	}
}

func TestStageOnlyMacsArtifactRejectsManifestMismatch(t *testing.T) {
	artifact := testOnlyMacsArtifactPayload(t, map[string]string{
		"docs/README.md": "# Overview\ncontent\n",
	})
	artifact.Manifest.Files = append(artifact.Manifest.Files, onlyMacsArtifactManifestFile{
		RelativePath: "docs/MISSING.md",
		Status:       onlyMacsArtifactFileReady,
	})
	if _, cleanup, err := stageOnlyMacsArtifact(artifact); err == nil {
		cleanup()
		t.Fatalf("expected manifest mismatch to fail")
	}
}

func testOnlyMacsArtifactPayload(t *testing.T, files map[string]string) *onlyMacsArtifactPayload {
	t.Helper()

	var tarBuffer bytes.Buffer
	gzipWriter := gzip.NewWriter(&tarBuffer)
	tarWriter := tar.NewWriter(gzipWriter)

	root := "bundle-request-test"
	manifestFiles := make([]onlyMacsArtifactManifestFile, 0, len(files))
	for relativePath, content := range files {
		fullPath := root + "/" + relativePath
		if err := tarWriter.WriteHeader(&tar.Header{
			Name:     fullPath,
			Mode:     0o600,
			Size:     int64(len(content)),
			Typeflag: tar.TypeReg,
		}); err != nil {
			t.Fatalf("write tar header: %v", err)
		}
		if _, err := tarWriter.Write([]byte(content)); err != nil {
			t.Fatalf("write tar content: %v", err)
		}
		sum := sha256.Sum256([]byte(content))
		manifestFiles = append(manifestFiles, onlyMacsArtifactManifestFile{
			RelativePath:    relativePath,
			Category:        "Master Docs",
			SelectionReason: "Core pipeline contract",
			IsRecommended:   true,
			ReviewPriority:  320,
			EvidenceHints:   []string{"Pipeline contract", "Step 2"},
			EvidenceAnchors: []onlyMacsArtifactEvidenceAnchor{
				{Kind: "heading", LineStart: 1, LineEnd: 1, Text: "Intake"},
				{Kind: "snippet", LineStart: 2, LineEnd: 2, Text: "Grounded pipeline guidance here."},
			},
			OriginalBytes: len(content),
			ExportedBytes: len(content),
			Status:        "ready",
			SHA256:        hex.EncodeToString(sum[:]),
		})
	}
	manifestBytes, err := json.Marshal(onlyMacsArtifactManifest{
		Schema:                "context_capsule.v2",
		CapsuleID:             "capsule-test",
		ID:                    "artifact-test",
		RequestID:             "request-test",
		CreatedAt:             "2026-04-19T00:00:00Z",
		ExpiresAt:             "2999-04-19T00:30:00Z",
		WorkspaceRootLabel:    "bundle-request-test",
		WorkspaceFingerprint:  "abc12345",
		TrustTier:             "private_trusted",
		AbsolutePathsIncluded: true,
		PromptSummary:         "Review the pipeline docs in this project.",
		RequestIntent:         "grounded_review",
		ExportMode:            "trusted_review_full",
		OutputContract:        "categorized_findings",
		RequiredSections:      []string{"Findings", "Open Questions", "Referenced Files"},
		GroundingRules:        []string{"Base every material claim only on the approved files in this bundle."},
		Permissions: onlyMacsArtifactPermissions{
			AllowContextRequests:    true,
			MaxContextRequestRounds: 2,
			AllowOutputArtifacts:    true,
		},
		Budgets: onlyMacsArtifactBudgets{
			MaxFileBytes:      180000,
			MaxTotalBytes:     480000,
			MaxScanBytes:      200000,
			RequiresFullFiles: true,
		},
		Files:              manifestFiles,
		TotalSelectedBytes: len(strings.Join(mapValues(files), "")),
		TotalExportBytes:   len(strings.Join(mapValues(files), "")),
	})
	if err != nil {
		t.Fatalf("marshal manifest: %v", err)
	}
	if err := tarWriter.WriteHeader(&tar.Header{
		Name:     root + "/manifest.json",
		Mode:     0o600,
		Size:     int64(len(manifestBytes)),
		Typeflag: tar.TypeReg,
	}); err != nil {
		t.Fatalf("write manifest header: %v", err)
	}
	if _, err := tarWriter.Write(manifestBytes); err != nil {
		t.Fatalf("write manifest: %v", err)
	}
	if err := tarWriter.Close(); err != nil {
		t.Fatalf("close tar writer: %v", err)
	}
	if err := gzipWriter.Close(); err != nil {
		t.Fatalf("close gzip writer: %v", err)
	}

	bundle := tarBuffer.Bytes()
	sum := sha256.Sum256(bundle)
	return &onlyMacsArtifactPayload{
		ExportMode:   "trusted_review_full",
		BundleBase64: base64.StdEncoding.EncodeToString(bundle),
		BundleSHA256: hex.EncodeToString(sum[:]),
		Manifest: onlyMacsArtifactManifest{
			Schema:                "context_capsule.v2",
			CapsuleID:             "capsule-test",
			ID:                    "artifact-test",
			RequestID:             "request-test",
			CreatedAt:             "2026-04-19T00:00:00Z",
			ExpiresAt:             "2999-04-19T00:30:00Z",
			WorkspaceRootLabel:    "bundle-request-test",
			WorkspaceFingerprint:  "abc12345",
			TrustTier:             "private_trusted",
			AbsolutePathsIncluded: true,
			PromptSummary:         "Review the pipeline docs in this project.",
			RequestIntent:         "grounded_review",
			ExportMode:            "trusted_review_full",
			OutputContract:        "categorized_findings",
			RequiredSections:      []string{"Findings", "Open Questions", "Referenced Files"},
			GroundingRules:        []string{"Base every material claim only on the approved files in this bundle."},
			Permissions: onlyMacsArtifactPermissions{
				AllowContextRequests:    true,
				MaxContextRequestRounds: 2,
				AllowOutputArtifacts:    true,
			},
			Budgets: onlyMacsArtifactBudgets{
				MaxFileBytes:      180000,
				MaxTotalBytes:     480000,
				MaxScanBytes:      200000,
				RequiresFullFiles: true,
			},
			Files:              manifestFiles,
			TotalSelectedBytes: len(strings.Join(mapValues(files), "")),
			TotalExportBytes:   len(strings.Join(mapValues(files), "")),
		},
	}
}

func mapValues(files map[string]string) []string {
	values := make([]string, 0, len(files))
	for _, content := range files {
		values = append(values, content)
	}
	return values
}
