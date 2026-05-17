package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

func TestRuntimeStoreMigratesLegacyActivePoolID(t *testing.T) {
	path := filepath.Join(t.TempDir(), "runtime.json")
	if err := os.WriteFile(path, []byte(`{"mode":"both","active_pool_id":"pool-000001"}`), 0o600); err != nil {
		t.Fatalf("write legacy runtime: %v", err)
	}

	store := newRuntimeStore(path)
	runtime := store.Get()
	if runtime.Mode != "both" || runtime.ActiveSwarmID != "swarm-000001" {
		t.Fatalf("expected legacy active pool to migrate, got %+v", runtime)
	}

	store.Set(runtime)
	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read migrated runtime: %v", err)
	}
	if strings.Contains(string(body), "active_pool_id") || !strings.Contains(string(body), "active_swarm_id") {
		t.Fatalf("expected persisted runtime to use swarm key only, got %s", string(body))
	}
}

func TestRuntimeStoreDefaultsFreshInstallsToPublicSharing(t *testing.T) {
	store := newRuntimeStore(filepath.Join(t.TempDir(), "runtime.json"))
	runtime := store.Get()
	if runtime.Mode != "both" || runtime.ActiveSwarmID != defaultPublicSwarmID {
		t.Fatalf("expected fresh runtime to auto-share on public swarm, got %+v", runtime)
	}
}

func TestRuntimeStoreFillsMissingModeWithPublicSharingDefault(t *testing.T) {
	path := filepath.Join(t.TempDir(), "runtime.json")
	if err := os.WriteFile(path, []byte(`{"active_swarm_id":"swarm-public"}`), 0o600); err != nil {
		t.Fatalf("write runtime without mode: %v", err)
	}

	store := newRuntimeStore(path)
	runtime := store.Get()
	if runtime.Mode != "both" || runtime.ActiveSwarmID != defaultPublicSwarmID {
		t.Fatalf("expected missing mode to inherit public sharing default, got %+v", runtime)
	}
}

func TestCoordinatorCredentialStorePersistsBesideRuntimeState(t *testing.T) {
	runtimePath := filepath.Join(t.TempDir(), "runtime.json")
	store := newCoordinatorCredentialStore(runtimePath)
	store.remember(coordinatorCredentials{
		Requester: &coordinatorTokenResponse{
			Token:    "requester-token",
			Scope:    "requester",
			SwarmID:  "swarm-private",
			MemberID: "member-owner",
		},
		Provider: &coordinatorTokenResponse{
			Token:      "provider-token",
			Scope:      "provider",
			ProviderID: "provider-owner",
		},
	})

	credentialPath := coordinatorCredentialPath(runtimePath)
	if credentialPath == runtimePath {
		t.Fatalf("expected credentials to be stored outside runtime state")
	}
	body, err := os.ReadFile(credentialPath)
	if err != nil {
		t.Fatalf("read persisted credentials: %v", err)
	}
	if !strings.Contains(string(body), "requester-token") || !strings.Contains(string(body), "provider-token") {
		t.Fatalf("expected credential file to contain saved tokens, got %s", string(body))
	}

	reloaded := newCoordinatorCredentialStore(runtimePath)
	if got := reloaded.requesterToken("swarm-private", "member-owner"); got != "requester-token" {
		t.Fatalf("expected reloaded requester token, got %q", got)
	}
	if got := reloaded.providerToken("provider-owner"); got != "provider-token" {
		t.Fatalf("expected reloaded provider token, got %q", got)
	}

	reloaded.rememberToken(coordinatorTokenResponse{
		Token:    "requester-token-rotated",
		Scope:    "requester",
		SwarmID:  "swarm-private",
		MemberID: "member-owner",
	})
	if got := newCoordinatorCredentialStore(runtimePath).requesterToken("swarm-private", "member-owner"); got != "requester-token-rotated" {
		t.Fatalf("expected rotated requester token to persist, got %q", got)
	}
}

func TestCoordinatorProxyChoosesScopedJobBoardToken(t *testing.T) {
	runtimePath := filepath.Join(t.TempDir(), "runtime.json")
	store := newCoordinatorCredentialStore(runtimePath)
	store.remember(coordinatorCredentials{
		Requester: &coordinatorTokenResponse{
			Token:    "requester-token",
			Scope:    "requester",
			SwarmID:  "swarm-private",
			MemberID: "member-owner",
		},
		Provider: &coordinatorTokenResponse{
			Token:      "provider-token",
			Scope:      "provider",
			ProviderID: "provider-owner",
		},
	})
	client := &coordinatorClient{credentials: store}

	createBody := []byte(`{"swarm_id":"swarm-private","requester_member_id":"member-owner"}`)
	if got := client.proxyToken(http.MethodPost, "/admin/v1/jobs", createBody); got != "requester-token" {
		t.Fatalf("expected requester token for job create, got %q", got)
	}

	claimBody := []byte(`{"member_id":"member-worker","provider_id":"provider-owner","max_tickets":1}`)
	if got := client.proxyToken(http.MethodPost, "/admin/v1/jobs/job-1/tickets/claim", claimBody); got != "provider-token" {
		t.Fatalf("expected provider token for job claim, got %q", got)
	}

	updateBody := []byte(`{"lease_id":"lease-1"}`)
	if got := client.proxyToken(http.MethodPost, "/admin/v1/jobs/job-1/tickets/ticket-a/complete", updateBody); got != "provider-token" {
		t.Fatalf("expected provider token for ticket update, got %q", got)
	}
}

func resetLocalNodeIDCacheForTest(t *testing.T) {
	t.Helper()
	nodeIDMu.Lock()
	cachedNodeID = ""
	nodeIDOnce = sync.Once{}
	nodeIDMu.Unlock()
	t.Cleanup(func() {
		nodeIDMu.Lock()
		cachedNodeID = ""
		nodeIDOnce = sync.Once{}
		nodeIDMu.Unlock()
	})
}

func TestCoordinatorRelayAndReleaseUseExactRequesterToken(t *testing.T) {
	var seen []string
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		seen = append(seen, r.URL.Path+" "+r.Header.Get("Authorization"))
		if r.Header.Get("Authorization") != "Bearer shen-requester" {
			t.Fatalf("expected exact requester token, got %q for %s", r.Header.Get("Authorization"), r.URL.Path)
		}
		switch r.URL.Path {
		case "/admin/v1/relay/execute":
			writeJSON(w, http.StatusOK, relayExecuteResponse{
				JobID:       "job-1",
				StatusCode:  http.StatusOK,
				ContentType: "application/json",
				BodyBase64:  "",
			})
		case "/admin/v1/sessions/release":
			var req releaseSessionRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode release request: %v", err)
			}
			writeJSON(w, http.StatusOK, releaseSessionResponse{SessionID: req.SessionID, Status: "released"})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	client := newCoordinatorClient(Config{
		CoordinatorURL:   coordinator.URL,
		HTTPClient:       coordinator.Client(),
		RelayHTTPClient:  coordinator.Client(),
		RuntimeStatePath: filepath.Join(t.TempDir(), "runtime.json"),
	})
	client.rememberCredentials(coordinatorCredentials{Requester: &coordinatorTokenResponse{
		Token:    "wrong-requester",
		Scope:    "requester",
		SwarmID:  "swarm-a",
		MemberID: "member-a",
	}})
	client.rememberCredentials(coordinatorCredentials{Requester: &coordinatorTokenResponse{
		Token:    "shen-requester",
		Scope:    "requester",
		SwarmID:  "swarm-public",
		MemberID: "member-shen",
	}})

	if _, err := client.executeRelay(context.Background(), "sess-shen", "provider-charles", "qwen", "swarm-public", "member-shen", chatCompletionsRequest{}); err != nil {
		t.Fatalf("execute relay: %v", err)
	}
	if _, err := client.release(releaseSessionRequest{SessionID: "sess-shen", SwarmID: "swarm-public", RequesterMemberID: "member-shen"}); err != nil {
		t.Fatalf("release: %v", err)
	}
	if len(seen) != 2 {
		t.Fatalf("expected two coordinator calls, got %+v", seen)
	}
}

func TestEnsurePublicSwarmCredentialRecoversMissingBoundRequesterToken(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	resetLocalNodeIDCacheForTest(t)

	firstMemberID, _ := localMemberIdentity()
	var upsertCalls int
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/admin/v1/swarms/members/upsert" {
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
		upsertCalls++
		var req upsertMemberRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode upsert request: %v", err)
		}
		if upsertCalls == 1 {
			if req.MemberID != firstMemberID {
				t.Fatalf("expected first upsert to use original member id %q, got %q", firstMemberID, req.MemberID)
			}
			writeJSON(w, http.StatusForbidden, map[string]any{
				"error": map[string]any{
					"code":    "REQUESTER_TOKEN_REQUIRED",
					"message": "requester token does not match this swarm member or session",
				},
			})
			return
		}
		if req.MemberID == firstMemberID {
			t.Fatalf("expected retry to rotate member id away from %q", firstMemberID)
		}
		writeJSON(w, http.StatusOK, upsertMemberResponse{
			Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public"},
			Member: swarmMember{ID: req.MemberID, Name: req.MemberName, Mode: req.Mode, SwarmID: defaultPublicSwarmID},
			Credentials: coordinatorCredentials{Requester: &coordinatorTokenResponse{
				Token:    "fresh-public-requester",
				Scope:    "requester",
				SwarmID:  defaultPublicSwarmID,
				MemberID: req.MemberID,
			}},
		})
	}))
	defer coordinator.Close()

	svc := newService(Config{
		CoordinatorURL:   coordinator.URL,
		HTTPClient:       coordinator.Client(),
		RuntimeStatePath: filepath.Join(t.TempDir(), "runtime.json"),
	})
	if err := svc.ensureActiveSwarmCredential(context.Background(), runtimeConfig{Mode: "both", ActiveSwarmID: defaultPublicSwarmID}); err != nil {
		t.Fatalf("ensure public swarm credential: %v", err)
	}
	if upsertCalls != 2 {
		t.Fatalf("expected recovery to retry once with a new member id, got %d calls", upsertCalls)
	}
	rotatedMemberID, _ := localMemberIdentity()
	if rotatedMemberID == firstMemberID {
		t.Fatalf("expected local member id to rotate from %q", firstMemberID)
	}
	if got := svc.coordinator.requesterToken(defaultPublicSwarmID, rotatedMemberID); got != "fresh-public-requester" {
		t.Fatalf("expected requester token for rotated member, got %q", got)
	}
}
