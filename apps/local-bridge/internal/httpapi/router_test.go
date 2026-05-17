package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"
)

func TestHealthHandler(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/health", nil)
	rec := httptest.NewRecorder()

	NewMux().ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, rec.Code)
	}
}

func TestLocalBridgeRejectsCrossSiteBrowserRequests(t *testing.T) {
	mux := NewMux()
	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/runtime", bytes.NewReader([]byte(`{"mode":"both"}`)))
	req.Host = "127.0.0.1:4318"
	req.Header.Set("Origin", "https://attacker.example")
	rec := httptest.NewRecorder()

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected cross-site origin to be blocked, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestLocalBridgeRejectsNonLocalHostHeader(t *testing.T) {
	mux := NewMux()
	req := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/health", nil)
	req.Host = "attacker.example"
	rec := httptest.NewRecorder()

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected non-local host to be blocked, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestLocalBridgeRejectsNonLocalExampleHost(t *testing.T) {
	mux := NewMux()
	req := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/health", nil)
	req.Host = "example.com"
	req.RemoteAddr = "127.0.0.1:12345"
	rec := httptest.NewRecorder()

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected non-local example host to be blocked, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestLocalBridgeRejectsNonLoopbackRemoteAddress(t *testing.T) {
	mux := NewMux()
	req := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/health", nil)
	req.Host = "127.0.0.1:4318"
	req.RemoteAddr = "203.0.113.10:55123"
	rec := httptest.NewRecorder()

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected non-loopback remote address to be blocked, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestLocalHardwareProfileIncludesRuntimeBasics(t *testing.T) {
	profile := localHardwareProfile()
	if profile == nil {
		t.Fatalf("expected local hardware profile")
	}
	if profile.CPUBrand == "" && profile.MemoryGB == 0 {
		t.Fatalf("expected CPU or RAM in hardware profile, got %+v", profile)
	}
}

func TestClientBuildFromEnvNormalizesStartupMetadata(t *testing.T) {
	t.Setenv("ONLYMACS_CLIENT_PRODUCT", " OnlyMacs ")
	t.Setenv("ONLYMACS_CLIENT_VERSION", "0.1.0")
	t.Setenv("ONLYMACS_CLIENT_BUILD_NUMBER", " 20260424141723 ")
	t.Setenv("ONLYMACS_CLIENT_BUILD_TIMESTAMP", " 2026-04-24T14:17:23Z ")
	t.Setenv("ONLYMACS_CLIENT_BUILD_CHANNEL", " public ")

	build := clientBuildFromEnv()
	if build == nil {
		t.Fatalf("expected client build from env")
	}
	if build.Product != "OnlyMacs" || build.BuildNumber != "20260424141723" || build.Channel != "public" {
		t.Fatalf("unexpected normalized client build: %+v", build)
	}
}

func TestClientBuildFromEnvFallsBackToContainingAppInfoPlist(t *testing.T) {
	infoPlistPath := writeTestOnlyMacsInfoPlist(t, "0.1.5", "20260429121253", "2026-04-29T12:12:53Z", "public")
	previousCandidates := clientBuildInfoPlistCandidates
	clientBuildInfoPlistCandidates = func() []string {
		return []string{infoPlistPath}
	}
	t.Cleanup(func() {
		clientBuildInfoPlistCandidates = previousCandidates
	})

	build := clientBuildFromEnv()
	if build == nil {
		t.Fatalf("expected client build from containing app Info.plist")
	}
	if build.Product != "OnlyMacs" || build.Version != "0.1.5" || build.BuildNumber != "20260429121253" || build.BuildTimestamp != "2026-04-29T12:12:53Z" || build.Channel != "public" {
		t.Fatalf("unexpected client build from app bundle: %+v", build)
	}
}

func TestClientBuildFromEnvPrefersExplicitEnvironmentOverAppBundle(t *testing.T) {
	infoPlistPath := writeTestOnlyMacsInfoPlist(t, "0.1.5", "20260429121253", "2026-04-29T12:12:53Z", "public")
	previousCandidates := clientBuildInfoPlistCandidates
	clientBuildInfoPlistCandidates = func() []string {
		return []string{infoPlistPath}
	}
	t.Cleanup(func() {
		clientBuildInfoPlistCandidates = previousCandidates
	})
	t.Setenv("ONLYMACS_CLIENT_VERSION", "0.1.6")
	t.Setenv("ONLYMACS_CLIENT_BUILD_NUMBER", "20260429143000")

	build := clientBuildFromEnv()
	if build == nil {
		t.Fatalf("expected client build")
	}
	if build.Version != "0.1.6" || build.BuildNumber != "20260429143000" {
		t.Fatalf("expected env build values to win, got %+v", build)
	}
	if build.BuildTimestamp != "2026-04-29T12:12:53Z" || build.Channel != "public" {
		t.Fatalf("expected missing env values to be filled from app bundle, got %+v", build)
	}
}

func TestCompactCPUBrand(t *testing.T) {
	if got := compactCPUBrand(" Apple M3 Max "); got != "M3 Max" {
		t.Fatalf("expected compact Apple CPU name, got %q", got)
	}
	if got := compactCPUBrand("Intel(R) Core(TM) i9"); got != "Intel(R) Core(TM) i9" {
		t.Fatalf("expected non-Apple CPU name to stay recognizable, got %q", got)
	}
}

func writeTestOnlyMacsInfoPlist(t *testing.T, version string, buildNumber string, buildTimestamp string, channel string) string {
	t.Helper()
	appContentsDir := filepath.Join(t.TempDir(), "OnlyMacs.app", "Contents")
	if err := os.MkdirAll(appContentsDir, 0755); err != nil {
		t.Fatalf("create app bundle contents: %v", err)
	}
	infoPlistPath := filepath.Join(appContentsDir, "Info.plist")
	infoPlist := `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>OnlyMacs</string>
	<key>CFBundleShortVersionString</key>
	<string>` + version + `</string>
	<key>CFBundleVersion</key>
	<string>` + buildNumber + `</string>
	<key>OnlyMacsBuildTimestamp</key>
	<string>` + buildTimestamp + `</string>
	<key>OnlyMacsBuildChannel</key>
	<string>` + channel + `</string>
</dict>
</plist>
`
	if err := os.WriteFile(infoPlistPath, []byte(infoPlist), 0644); err != nil {
		t.Fatalf("write Info.plist: %v", err)
	}
	return infoPlistPath
}

func TestProviderModelStatsPrefersQwen36OverOlderCoder(t *testing.T) {
	_, bestModel := providerModelStats(provider{
		Models: []model{
			{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B"},
			{ID: "qwen3.6:35b-a3b-q4_K_M", Name: "Qwen 3.6 35B Q4"},
			{ID: "qwen3.6:35b-a3b-q8_0", Name: "Qwen 3.6 35B Q8"},
		},
	})
	if bestModel != "qwen3.6:35b-a3b-q8_0" {
		t.Fatalf("expected Qwen 3.6 Q8 to be summarized as best model, got %q", bestModel)
	}
}

func TestNormalizeProviderCapacityStatusMarksOccupiedProviderBusy(t *testing.T) {
	provider := provider{
		Status:         "available",
		Slots:          slots{Free: 0, Total: 1},
		ActiveSessions: 1,
		Models: []model{{
			ID:         "qwen2.5-coder:32b",
			SlotsFree:  1,
			SlotsTotal: 1,
		}},
	}

	normalizeProviderCapacityStatus(&provider)

	if provider.Status != "busy" || provider.Slots.Free != 0 || provider.Models[0].SlotsFree != 0 {
		t.Fatalf("expected occupied provider to normalize as busy, got %+v", provider)
	}
}

func TestNormalizeLocalShareCapacityStatusMarksOccupiedShareBusy(t *testing.T) {
	status := localShareStatus{
		Status:         "available",
		ActiveSessions: 1,
		Slots:          slots{Free: 0, Total: 1},
		PublishedModels: []model{{
			ID:         "qwen2.5-coder:32b",
			SlotsFree:  1,
			SlotsTotal: 1,
		}},
	}

	normalizeLocalShareCapacityStatus(&status)

	if status.Status != "busy" || status.Slots.Free != 0 || status.PublishedModels[0].SlotsFree != 0 {
		t.Fatalf("expected occupied local share to normalize as busy, got %+v", status)
	}
}

func TestBuildSwarmMembersCarriesServingModelAndRecentTokenRate(t *testing.T) {
	members := buildSwarmMembers([]provider{
		{
			ID:                     "provider-studio",
			Name:                   "StudioHost",
			SwarmID:                defaultPublicSwarmID,
			OwnerMemberID:          "member-studio",
			OwnerMemberName:        "StudioHost",
			Status:                 "busy",
			Slots:                  slots{Free: 0, Total: 1},
			ActiveSessions:         1,
			ActiveModel:            "qwen3.6:35b-a3b-q8_0",
			RecentUploadedTokensPS: 17.2,
			Models: []model{{
				ID:         "qwen3.6:35b-a3b-q8_0",
				Name:       "Qwen 3.6 35B Q8",
				SlotsFree:  0,
				SlotsTotal: 1,
			}},
		},
	}, nil)

	if len(members) != 1 {
		t.Fatalf("expected one member, got %+v", members)
	}
	member := members[0]
	if member.Status != "serving" || member.ActiveModel != "qwen3.6:35b-a3b-q8_0" || member.RecentUploadedTokensPS != 17.2 {
		t.Fatalf("expected serving model and recent token rate, got %+v", member)
	}
	if len(member.Capabilities) != 1 || member.Capabilities[0].ActiveModel != "qwen3.6:35b-a3b-q8_0" || member.Capabilities[0].RecentUploadedTokensPS != 17.2 {
		t.Fatalf("expected capability serving model and recent token rate, got %+v", member.Capabilities)
	}
}

func TestRoundedMemoryGB(t *testing.T) {
	const gibibyte = uint64(1024 * 1024 * 1024)
	if got := roundedMemoryGB(64 * gibibyte); got != 64 {
		t.Fatalf("expected exact 64 GiB to report 64 GB, got %d", got)
	}
	if got := roundedMemoryGB(63*gibibyte + gibibyte/2); got != 64 {
		t.Fatalf("expected half-up rounding to 64 GB, got %d", got)
	}
}

func TestIdentityHandlerPersistsMemberNameAndRefreshesMembership(t *testing.T) {
	resetLocalIdentityCacheForTest()
	t.Cleanup(resetLocalIdentityCacheForTest)
	t.Setenv("ONLYMACS_IDENTITY_PATH", t.TempDir()+"/identity.json")
	t.Setenv("ONLYMACS_MEMBER_NAME", "")
	t.Setenv("ONLYMACS_PROVIDER_NAME", "")

	var upsertedName string
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms/members/upsert":
			var req upsertMemberRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode member upsert: %v", err)
			}
			upsertedName = req.MemberName
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: req.SwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: 1},
				Member: swarmMember{ID: req.MemberID, Name: req.MemberName, Mode: req.Mode, SwarmID: req.SwarmID},
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			writeJSON(w, http.StatusOK, ollamaModelsResponse{})
		default:
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
	}))
	defer inference.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		OllamaURL:           inference.URL,
		InferenceHTTPClient: inference.Client(),
	})

	body := []byte(`{"member_name":"Kevin"}`)
	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/identity", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if upsertedName != "Kevin" {
		t.Fatalf("expected coordinator membership to refresh with Kevin, got %q", upsertedName)
	}

	getReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/identity", nil)
	getRec := httptest.NewRecorder()
	mux.ServeHTTP(getRec, getReq)
	if getRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, getRec.Code)
	}
	var identity localIdentityResponse
	if err := json.Unmarshal(getRec.Body.Bytes(), &identity); err != nil {
		t.Fatalf("unmarshal identity: %v", err)
	}
	if identity.MemberName != "Kevin" || identity.ProviderName != "Kevin" {
		t.Fatalf("expected persisted identity to drive member and provider names, got %+v", identity)
	}
}

func TestRuntimeFilteredModelsAndModeBlocking(t *testing.T) {
	localProviderID, _ := localProviderIdentity()

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			writeJSON(w, http.StatusOK, map[string]any{
				"data": []map[string]any{
					{"id": "qwen2.5-coder:32b"},
					{"id": "gemma4:26b"},
				},
			})
		default:
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
	}))
	defer inference.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{
				Swarms: []swarm{
					{ID: "swarm-alpha", Name: "Alpha Swarm", MemberCount: 1, ProviderCount: 1},
					{ID: "swarm-beta", Name: "Beta Swarm", MemberCount: 0, ProviderCount: 1},
				},
			})
		case r.URL.Path == "/admin/v1/providers" && r.URL.Query().Get("swarm_id") == "swarm-alpha":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						SwarmID:        "swarm-alpha",
						Status:         "available",
						Modes:          []string{"share", "both"},
						Slots:          slots{Free: 2, Total: 2},
						ActiveSessions: 0,
						Models: []model{
							{
								ID:         "qwen2.5-coder:32b",
								Name:       "Qwen2.5 Coder 32B",
								SlotsFree:  2,
								SlotsTotal: 2,
							},
						},
					},
				},
			})
		case r.URL.Path == "/admin/v1/providers" && r.URL.Query().Get("swarm_id") == "swarm-beta":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:             "dana-m4",
						Name:           "Dana's MacBook Pro",
						SwarmID:        "swarm-beta",
						Status:         "available",
						Modes:          []string{"share", "both"},
						Slots:          slots{Free: 1, Total: 1},
						ActiveSessions: 0,
						Models: []model{
							{
								ID:         "gemma4:26b",
								Name:       "Gemma 4 26B",
								SlotsFree:  1,
								SlotsTotal: 1,
							},
						},
					},
				},
			})
		case r.URL.Path == "/admin/v1/providers" && r.URL.Query().Get("swarm_id") == "":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						SwarmID:        "swarm-alpha",
						Status:         "available",
						Modes:          []string{"share", "both"},
						Slots:          slots{Free: 2, Total: 2},
						ActiveSessions: 0,
						Models: []model{
							{
								ID:         "qwen2.5-coder:32b",
								Name:       "Qwen2.5 Coder 32B",
								SlotsFree:  2,
								SlotsTotal: 2,
							},
						},
					},
					{
						ID:             "dana-m4",
						Name:           "Dana's MacBook Pro",
						SwarmID:        "swarm-beta",
						Status:         "available",
						Modes:          []string{"share", "both"},
						Slots:          slots{Free: 1, Total: 1},
						ActiveSessions: 0,
						Models: []model{
							{
								ID:         "gemma4:26b",
								Name:       "Gemma 4 26B",
								SlotsFree:  1,
								SlotsTotal: 1,
							},
						},
					},
				},
			})
		case r.URL.Path == "/admin/v1/members/summary" && r.URL.Query().Get("swarm_id") == "swarm-alpha":
			writeJSON(w, http.StatusOK, memberSummaryResponse{
				MemberID:               r.URL.Query().Get("member_id"),
				MemberName:             "Kevin",
				SwarmID:                "swarm-alpha",
				ProviderCount:          1,
				ActiveReservations:     2,
				ReservationCap:         4,
				ServedSessions:         0,
				UploadedTokensEstimate: 0,
				BestPublishedModel:     "",
				CommunityBoost: coordinatorCommunityBoostSummary{
					Level:        3,
					Label:        "Steady",
					PrimaryTrait: "Fresh Face",
					Traits:       []string{"Fresh Face"},
					Detail:       "Fresh start. You're in the swarm; sharing or using compute gets your boost moving.",
				},
			})
		case r.URL.Path == "/admin/v1/preflight":
			var req preflightRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode preflight request: %v", err)
			}
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: req.Model,
				ResolvedModel:  req.Model,
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						Status:         "available",
						ActiveSessions: 0,
						Slots:          slots{Free: 2, Total: 2},
						MatchingModels: []model{
							{
								ID:         req.Model,
								Name:       "Qwen2.5 Coder 32B",
								SlotsFree:  2,
								SlotsTotal: 2,
							},
						},
					},
				},
				AvailableModels: []model{
					{
						ID:         req.Model,
						Name:       "Qwen2.5 Coder 32B",
						SlotsFree:  2,
						SlotsTotal: 2,
					},
				},
			})
		case r.URL.Path == "/admin/v1/sessions/reserve":
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-000001",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:32b",
				Provider: preflightProvider{
					ID:             localProviderID,
					Name:           "This Mac",
					Status:         "available",
					ActiveSessions: 1,
					Slots:          slots{Free: 1, Total: 2},
					MatchingModels: []model{
						{
							ID:         "qwen2.5-coder:32b",
							Name:       "Qwen2.5 Coder 32B",
							SlotsFree:  1,
							SlotsTotal: 2,
						},
					},
				},
			})
		case r.URL.Path == "/admin/v1/sessions/release":
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "sess-000001",
				Status:    "released",
			})
		case r.URL.Path == "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{})
		default:
			t.Fatalf("unexpected path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		CannedChat:          true,
		OllamaURL:           inference.URL,
		InferenceHTTPClient: inference.Client(),
	})

	updateRuntime(t, mux, runtimeConfig{
		Mode:          "use",
		ActiveSwarmID: "swarm-alpha",
	})

	statusReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil)
	statusRec := httptest.NewRecorder()
	mux.ServeHTTP(statusRec, statusReq)
	if statusRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, statusRec.Code)
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"active_swarm_id":"swarm-alpha"`)) {
		t.Fatalf("expected active swarm in status, got %s", statusRec.Body.String())
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"sharing":{"provider_id"`)) {
		t.Fatalf("expected sharing state in status, got %s", statusRec.Body.String())
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"tokens_saved_estimate":0`)) {
		t.Fatalf("expected saved token estimate in status, got %s", statusRec.Body.String())
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"downloaded_tokens_estimate":0`)) {
		t.Fatalf("expected downloaded token estimate in status, got %s", statusRec.Body.String())
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"active_reservations":2`)) || !bytes.Contains(statusRec.Body.Bytes(), []byte(`"reservation_cap":4`)) {
		t.Fatalf("expected requester swarm budget in status, got %s", statusRec.Body.String())
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"community_boost":{"level":3,"label":"Steady"`)) {
		t.Fatalf("expected community boost in status, got %s", statusRec.Body.String())
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"recent_sessions":[]`)) {
		t.Fatalf("expected recent session list in status, got %s", statusRec.Body.String())
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"queue_summary":{"queued_session_count":0`)) {
		t.Fatalf("expected queue summary in status, got %s", statusRec.Body.String())
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"Charles's Mac Studio"`)) {
		t.Fatalf("expected alpha provider in status, got %s", statusRec.Body.String())
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"members":[`)) || !bytes.Contains(statusRec.Body.Bytes(), []byte(`"member_name":"Charles's Mac Studio"`)) {
		t.Fatalf("expected swarm member summaries in status, got %s", statusRec.Body.String())
	}
	if bytes.Contains(statusRec.Body.Bytes(), []byte(`"Dana's MacBook Pro"`)) {
		t.Fatalf("did not expect beta provider in alpha status, got %s", statusRec.Body.String())
	}

	modelsReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/models", nil)
	modelsRec := httptest.NewRecorder()
	mux.ServeHTTP(modelsRec, modelsReq)
	if modelsRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, modelsRec.Code)
	}
	if !bytes.Contains(modelsRec.Body.Bytes(), []byte(`"qwen2.5-coder:32b"`)) {
		t.Fatalf("expected alpha model in models response, got %s", modelsRec.Body.String())
	}
	if bytes.Contains(modelsRec.Body.Bytes(), []byte(`"gemma4:26b"`)) {
		t.Fatalf("did not expect beta model in alpha models response, got %s", modelsRec.Body.String())
	}

	openAIModelsReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/v1/models", nil)
	openAIModelsRec := httptest.NewRecorder()
	mux.ServeHTTP(openAIModelsRec, openAIModelsReq)
	if openAIModelsRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, openAIModelsRec.Code)
	}
	var openAIModels openAIModelsResponse
	if err := json.Unmarshal(openAIModelsRec.Body.Bytes(), &openAIModels); err != nil {
		t.Fatalf("decode OpenAI-compatible models response: %v", err)
	}
	if openAIModels.Object != "list" {
		t.Fatalf("expected OpenAI-compatible list object, got %+v", openAIModels)
	}
	openAIModelIDs := map[string]openAIModel{}
	for _, item := range openAIModels.Data {
		openAIModelIDs[item.ID] = item
		if item.Object != "model" || item.OwnedBy != "onlymacs" {
			t.Fatalf("expected OpenAI-compatible model metadata, got %+v", item)
		}
	}
	if _, ok := openAIModelIDs["qwen2.5-coder:32b"]; !ok {
		t.Fatalf("expected alpha model in OpenAI-compatible models response, got %+v", openAIModels.Data)
	}
	if _, ok := openAIModelIDs["best-available"]; !ok {
		t.Fatalf("expected virtual best-available model in OpenAI-compatible models response, got %+v", openAIModels.Data)
	}
	if _, ok := openAIModelIDs["gemma4:26b"]; ok {
		t.Fatalf("did not expect beta model in OpenAI-compatible alpha response, got %+v", openAIModels.Data)
	}

	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	chatBody, err := json.Marshal(chatCompletionsRequest{
		Model:  "qwen2.5-coder:32b",
		Stream: true,
		Messages: []chatMessage{
			{Role: "user", Content: "hello"},
		},
	})
	if err != nil {
		t.Fatalf("marshal chat body: %v", err)
	}

	chatReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", bytes.NewReader(chatBody))
	chatRec := httptest.NewRecorder()
	mux.ServeHTTP(chatRec, chatReq)
	if chatRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, chatRec.Code)
	}
	if !bytes.Contains(chatRec.Body.Bytes(), []byte("This Mac")) {
		t.Fatalf("expected canned stream to mention provider, got %s", chatRec.Body.String())
	}

	statusAfterChatReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil)
	statusAfterChatRec := httptest.NewRecorder()
	mux.ServeHTTP(statusAfterChatRec, statusAfterChatReq)
	if statusAfterChatRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, statusAfterChatRec.Code)
	}

	var statusAfterChat struct {
		Usage usageSummary `json:"usage"`
	}
	if err := json.Unmarshal(statusAfterChatRec.Body.Bytes(), &statusAfterChat); err != nil {
		t.Fatalf("decode status after chat: %v", err)
	}
	if statusAfterChat.Usage.TokensSavedEstimate <= 0 {
		t.Fatalf("expected successful chat to increase tokens saved, got %+v", statusAfterChat.Usage)
	}
	if statusAfterChat.Usage.DownloadedTokensEstimate <= 0 {
		t.Fatalf("expected successful chat to increase downloaded tokens, got %+v", statusAfterChat.Usage)
	}
	if statusAfterChat.Usage.RecentRemoteTokensPS <= 0 {
		t.Fatalf("expected successful chat to expose recent requester throughput, got %+v", statusAfterChat.Usage)
	}
}

func TestStatusKeepsLocalSwarmWhenSwarmListTimesOut(t *testing.T) {
	localProviderID, _ := localProviderIdentity()
	localMemberID, _ := localMemberIdentity()

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			writeJSON(w, http.StatusOK, map[string]any{
				"data": []map[string]any{
					{"id": "qwen2.5-coder:32b"},
				},
			})
		default:
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
	}))
	defer inference.Close()

	remoteProvider := provider{
		ID:              "provider-charles",
		Name:            "Charles",
		SwarmID:         defaultPublicSwarmID,
		OwnerMemberID:   "member-charles",
		OwnerMemberName: "Charles",
		Status:          "available",
		Modes:           []string{"share", "both"},
		Slots:           slots{Free: 1, Total: 1},
		Models: []model{{
			ID:         "qwen2.5-coder:32b",
			Name:       "Qwen2.5 Coder 32B",
			SlotsFree:  1,
			SlotsTotal: 1,
		}},
	}

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/admin/v1/swarms":
			http.Error(w, "upstream swarms timeout", http.StatusGatewayTimeout)
		case r.URL.Path == "/admin/v1/providers" && r.Method == http.MethodGet:
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{Providers: []provider{remoteProvider}})
		case r.URL.Path == "/admin/v1/providers/register":
			var req registerProviderRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode provider registration: %v", err)
			}
			writeJSON(w, http.StatusCreated, registerProviderResponse{Status: "registered", Provider: req.Provider})
		case r.URL.Path == "/admin/v1/swarms/members/upsert":
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: 2, ProviderCount: 2},
				Member: swarmMember{ID: localMemberID, Name: "Kevin", Mode: "both", SwarmID: defaultPublicSwarmID},
			})
		case r.URL.Path == "/admin/v1/members/summary":
			http.Error(w, `{"error":{"code":"MEMBER_NOT_FOUND","message":"member could not be found"}}`, http.StatusNotFound)
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		OllamaURL:           inference.URL,
		InferenceHTTPClient: inference.Client(),
	})
	updateRuntime(t, mux, runtimeConfig{Mode: "both", ActiveSwarmID: defaultPublicSwarmID})

	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}

	var body struct {
		Bridge struct {
			Status          string `json:"status"`
			ActiveSwarmName string `json:"active_swarm_name"`
			Error           string `json:"error"`
		} `json:"bridge"`
		Swarms    []bridgeSwarmView              `json:"swarms"`
		Providers []provider                     `json:"providers"`
		Members   []swarmMemberSummary           `json:"members"`
		Swarm     bridgeSwarmCapacitySummaryView `json:"swarm"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode status body: %v", err)
	}
	if body.Bridge.Status != "ready" || body.Bridge.ActiveSwarmName != "OnlyMacs Public" || body.Bridge.Error != "" {
		t.Fatalf("expected ready status without a user-facing swarm-list warning, got %+v", body.Bridge)
	}
	if len(body.Swarms) != 1 || body.Swarms[0].ID != defaultPublicSwarmID || body.Swarms[0].MemberCount != 2 {
		t.Fatalf("expected synthesized active public swarm with live member count, got %+v", body.Swarms)
	}
	if len(body.Providers) != 2 || len(body.Members) != 2 {
		t.Fatalf("expected remote and local providers/members despite swarms timeout, got providers=%+v members=%+v", body.Providers, body.Members)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"provider_id":"`+localProviderID+`"`)) {
		t.Fatalf("expected local provider fallback in status, got %s", rec.Body.String())
	}
	if body.Swarm.SlotsTotal != 2 || body.Swarm.SlotsFree != 2 || body.Swarm.ModelCount != 1 {
		t.Fatalf("expected aggregate swarm stats to use live providers, got %+v", body.Swarm)
	}
}

func TestStatusDoesNotWaitForSlowCoordinatorSwarms(t *testing.T) {
	localMemberID, _ := localMemberIdentity()

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			writeJSON(w, http.StatusOK, map[string]any{
				"data": []map[string]any{{"id": "qwen2.5-coder:32b"}},
			})
		default:
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
	}))
	defer inference.Close()

	remoteProvider := provider{
		ID:              "provider-charles",
		Name:            "Charles",
		SwarmID:         defaultPublicSwarmID,
		OwnerMemberID:   "member-charles",
		OwnerMemberName: "Charles",
		Status:          "available",
		Modes:           []string{"share", "both"},
		Slots:           slots{Free: 1, Total: 1},
		Models: []model{{
			ID:         "qwen2.5-coder:32b",
			Name:       "Qwen2.5 Coder 32B",
			SlotsFree:  1,
			SlotsTotal: 1,
		}},
	}

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/admin/v1/swarms":
			time.Sleep(2 * time.Second)
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{})
		case r.URL.Path == "/admin/v1/providers" && r.Method == http.MethodGet:
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{Providers: []provider{remoteProvider}})
		case r.URL.Path == "/admin/v1/providers/register":
			var req registerProviderRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode provider registration: %v", err)
			}
			writeJSON(w, http.StatusCreated, registerProviderResponse{Status: "registered", Provider: req.Provider})
		case r.URL.Path == "/admin/v1/swarms/members/upsert":
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: 2, ProviderCount: 2},
				Member: swarmMember{ID: localMemberID, Name: "Kevin", Mode: "both", SwarmID: defaultPublicSwarmID},
			})
		case r.URL.Path == "/admin/v1/members/summary":
			writeJSON(w, http.StatusOK, memberSummaryResponse{
				MemberID:           localMemberID,
				MemberName:         "Kevin",
				SwarmID:            defaultPublicSwarmID,
				SwarmMemberCount:   2,
				SwarmProviderCount: 2,
				ReservationCap:     4,
				CommunityBoost: coordinatorCommunityBoostSummary{
					Level:        3,
					Label:        "Steady",
					PrimaryTrait: "Fresh Face",
					Traits:       []string{"Fresh Face"},
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		OllamaURL:           inference.URL,
		InferenceHTTPClient: inference.Client(),
	})
	updateRuntime(t, mux, runtimeConfig{Mode: "both", ActiveSwarmID: defaultPublicSwarmID})

	rec := httptest.NewRecorder()
	start := time.Now()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil))
	elapsed := time.Since(start)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if elapsed > 1700*time.Millisecond {
		t.Fatalf("expected status to return before slow swarm endpoint completed, took %s", elapsed)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"providers"`)) || !bytes.Contains(rec.Body.Bytes(), []byte(`provider-charles`)) {
		t.Fatalf("expected status to keep available provider data despite slow swarms, got %s", rec.Body.String())
	}
	if bytes.Contains(rec.Body.Bytes(), []byte(`context deadline exceeded`)) {
		t.Fatalf("expected slow swarm timeout to stay out of user-facing status, got %s", rec.Body.String())
	}
}

func TestStatusUsesRecentCoordinatorCacheDuringTransientTimeout(t *testing.T) {
	localMemberID, _ := localMemberIdentity()

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			writeJSON(w, http.StatusOK, map[string]any{
				"data": []map[string]any{{"id": "qwen2.5-coder:32b"}},
			})
		default:
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
	}))
	defer inference.Close()

	var coordinatorSlow atomic.Bool
	remoteProvider := provider{
		ID:              "provider-charles",
		Name:            "Charles",
		SwarmID:         defaultPublicSwarmID,
		OwnerMemberID:   "member-charles",
		OwnerMemberName: "Charles",
		Status:          "available",
		Modes:           []string{"share", "both"},
		Slots:           slots{Free: 1, Total: 1},
		Models: []model{{
			ID:         "qwen2.5-coder:32b",
			Name:       "Qwen2.5 Coder 32B",
			SlotsFree:  1,
			SlotsTotal: 1,
		}},
	}

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if coordinatorSlow.Load() && (r.URL.Path == "/admin/v1/swarms" || (r.URL.Path == "/admin/v1/providers" && r.URL.Query().Get("swarm_id") == defaultPublicSwarmID)) {
			time.Sleep(2 * time.Second)
			return
		}
		switch {
		case r.URL.Path == "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{Swarms: []swarm{{
				ID:            defaultPublicSwarmID,
				Name:          "OnlyMacs Public",
				Visibility:    "public",
				MemberCount:   2,
				ProviderCount: 2,
				SlotsFree:     2,
				SlotsTotal:    2,
			}}})
		case r.URL.Path == "/admin/v1/providers" && r.Method == http.MethodGet:
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{Providers: []provider{remoteProvider}})
		case r.URL.Path == "/admin/v1/providers/register":
			var req registerProviderRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode provider registration: %v", err)
			}
			writeJSON(w, http.StatusCreated, registerProviderResponse{Status: "registered", Provider: req.Provider})
		case r.URL.Path == "/admin/v1/swarms/members/upsert":
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: 2, ProviderCount: 2},
				Member: swarmMember{ID: localMemberID, Name: "Kevin", Mode: "both", SwarmID: defaultPublicSwarmID},
			})
		case r.URL.Path == "/admin/v1/members/summary":
			writeJSON(w, http.StatusOK, memberSummaryResponse{
				MemberID:           localMemberID,
				MemberName:         "Kevin",
				SwarmID:            defaultPublicSwarmID,
				SwarmMemberCount:   2,
				SwarmProviderCount: 2,
			})
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		OllamaURL:           inference.URL,
		InferenceHTTPClient: inference.Client(),
	})
	updateRuntime(t, mux, runtimeConfig{Mode: "both", ActiveSwarmID: defaultPublicSwarmID})

	first := httptest.NewRecorder()
	mux.ServeHTTP(first, httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil))
	if first.Code != http.StatusOK {
		t.Fatalf("expected first status %d, got %d: %s", http.StatusOK, first.Code, first.Body.String())
	}

	coordinatorSlow.Store(true)
	second := httptest.NewRecorder()
	start := time.Now()
	mux.ServeHTTP(second, httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil))
	elapsed := time.Since(start)
	if second.Code != http.StatusOK {
		t.Fatalf("expected cached status %d, got %d: %s", http.StatusOK, second.Code, second.Body.String())
	}
	if elapsed > 1700*time.Millisecond {
		t.Fatalf("expected cached status to return before coordinator timeout finished, took %s", elapsed)
	}

	var body struct {
		Bridge struct {
			Status string `json:"status"`
			Error  string `json:"error"`
		} `json:"bridge"`
		Swarms    []bridgeSwarmView `json:"swarms"`
		Providers []provider        `json:"providers"`
	}
	if err := json.Unmarshal(second.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode cached status body: %v", err)
	}
	if body.Bridge.Status != "ready" || body.Bridge.Error != "" {
		t.Fatalf("expected cached coordinator state to keep bridge ready without visible error, got %+v", body.Bridge)
	}
	if len(body.Swarms) != 1 || body.Swarms[0].ID != defaultPublicSwarmID {
		t.Fatalf("expected cached swarms during transient timeout, got %+v", body.Swarms)
	}
	if len(body.Providers) < 1 {
		t.Fatalf("expected cached providers during transient timeout, got %+v", body.Providers)
	}
}

func TestSwarmsEndpointUsesRecentCoordinatorCacheDuringTransientTimeout(t *testing.T) {
	var coordinatorSlow atomic.Bool

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case coordinatorSlow.Load() && r.URL.Path == "/admin/v1/swarms":
			time.Sleep(2 * time.Second)
			return
		case r.URL.Path == "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{Swarms: []swarm{{
				ID:            defaultPublicSwarmID,
				Name:          "OnlyMacs Public",
				Visibility:    "public",
				MemberCount:   2,
				ProviderCount: 2,
				SlotsFree:     2,
				SlotsTotal:    2,
			}}})
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{CoordinatorURL: coordinator.URL, HTTPClient: coordinator.Client()})

	first := httptest.NewRecorder()
	mux.ServeHTTP(first, httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/swarms", nil))
	if first.Code != http.StatusOK {
		t.Fatalf("expected first swarms status %d, got %d: %s", http.StatusOK, first.Code, first.Body.String())
	}

	coordinatorSlow.Store(true)
	second := httptest.NewRecorder()
	start := time.Now()
	mux.ServeHTTP(second, httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/swarms", nil))
	elapsed := time.Since(start)
	if second.Code != http.StatusOK {
		t.Fatalf("expected cached swarms status %d, got %d: %s", http.StatusOK, second.Code, second.Body.String())
	}
	if elapsed > 1700*time.Millisecond {
		t.Fatalf("expected cached swarms to return before coordinator timeout finished, took %s", elapsed)
	}

	var body struct {
		Swarms []bridgeSwarmView `json:"swarms"`
		Stale  bool              `json:"stale"`
	}
	if err := json.Unmarshal(second.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode cached swarms body: %v", err)
	}
	if !body.Stale {
		t.Fatalf("expected cached swarms response to be marked stale")
	}
	if len(body.Swarms) != 1 || body.Swarms[0].ID != defaultPublicSwarmID || body.Swarms[0].MemberCount != 2 {
		t.Fatalf("expected cached public swarm during transient timeout, got %+v", body.Swarms)
	}
}

func TestSwarmsEndpointSynthesizesActiveSwarmDuringTransientTimeout(t *testing.T) {
	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			writeJSON(w, http.StatusOK, map[string]any{
				"data": []map[string]any{{"id": "qwen2.5-coder:32b"}},
			})
		default:
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
	}))
	defer inference.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms":
			time.Sleep(2 * time.Second)
			return
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		OllamaURL:           inference.URL,
		InferenceHTTPClient: inference.Client(),
	})
	updateRuntime(t, mux, runtimeConfig{Mode: "both", ActiveSwarmID: defaultPublicSwarmID})

	rec := httptest.NewRecorder()
	start := time.Now()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/swarms", nil))
	elapsed := time.Since(start)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected synthesized swarms status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if elapsed > 1700*time.Millisecond {
		t.Fatalf("expected synthesized swarms to return before coordinator timeout finished, took %s", elapsed)
	}

	var body struct {
		Swarms []bridgeSwarmView `json:"swarms"`
		Stale  bool              `json:"stale"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("decode synthesized swarms body: %v", err)
	}
	if !body.Stale {
		t.Fatalf("expected synthesized swarms response to be marked stale")
	}
	if len(body.Swarms) != 1 || body.Swarms[0].ID != defaultPublicSwarmID || body.Swarms[0].Name != "OnlyMacs Public" || body.Swarms[0].SlotsTotal != 1 {
		t.Fatalf("expected synthesized active public swarm from local runtime/share state, got %+v", body.Swarms)
	}
}

func TestPublicRuntimeStatusKeepsRequesterMembershipWithoutShareCapability(t *testing.T) {
	var (
		publicMemberCount int
		upsertCalls       int
		registerCalls     int
		removeCalls       int
	)

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			writeJSON(w, http.StatusOK, map[string]any{"data": []map[string]any{}})
		default:
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
	}))
	defer inference.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/admin/v1/swarms/members/upsert":
			upsertCalls++
			publicMemberCount = 1
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: publicMemberCount},
				Member: swarmMember{ID: "member-kevin-public", Name: "Kevin", Mode: "both", SwarmID: defaultPublicSwarmID},
				Credentials: coordinatorCredentials{Requester: &coordinatorTokenResponse{
					Token:    "requester-token",
					Scope:    "requester",
					SwarmID:  defaultPublicSwarmID,
					MemberID: "member-kevin-public",
				}},
			})
		case r.URL.Path == "/admin/v1/swarms/members/remove":
			removeCalls++
			writeJSON(w, http.StatusOK, removeMemberResponse{
				Status:   "removed",
				SwarmID:  defaultPublicSwarmID,
				MemberID: "member-kevin-public",
			})
		case r.URL.Path == "/admin/v1/providers/register":
			registerCalls++
			var req registerProviderRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode register provider request: %v", err)
			}
			writeJSON(w, http.StatusCreated, registerProviderResponse{Status: "registered", Provider: req.Provider})
		case r.URL.Path == "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{
				Swarms: []swarm{{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: publicMemberCount}},
			})
		case r.URL.Path == "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{Providers: []provider{}})
		case r.URL.Path == "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{})
		case r.URL.Path == "/admin/v1/members/summary":
			if publicMemberCount == 0 {
				http.Error(w, `{"error":{"code":"MEMBER_NOT_FOUND","message":"member could not be found"}}`, http.StatusNotFound)
				return
			}
			writeJSON(w, http.StatusOK, memberSummaryResponse{
				MemberID:         r.URL.Query().Get("member_id"),
				MemberName:       "Kevin",
				SwarmID:          defaultPublicSwarmID,
				SwarmMemberCount: publicMemberCount,
			})
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	t.Setenv("ONLYMACS_NODE_ID", "kevin-public")
	t.Setenv("ONLYMACS_MEMBER_NAME", "Kevin")

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		OllamaURL:           inference.URL,
		InferenceHTTPClient: inference.Client(),
		CannedChat:          true,
	})

	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: defaultPublicSwarmID,
	})

	statusReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil)
	statusRec := httptest.NewRecorder()
	mux.ServeHTTP(statusRec, statusReq)
	if statusRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, statusRec.Code, statusRec.Body.String())
	}
	if upsertCalls != 1 {
		t.Fatalf("expected public swarm to bootstrap requester membership, got %d upserts", upsertCalls)
	}
	if registerCalls != 0 {
		t.Fatalf("expected no provider registration without local models, got %d registrations", registerCalls)
	}
	if removeCalls != 0 {
		t.Fatalf("expected public requester membership to stay active without share capability, got %d removals", removeCalls)
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"member_count":1`)) {
		t.Fatalf("expected public requester member while this Mac is not sharing, got %s", statusRec.Body.String())
	}
	if bytes.Contains(statusRec.Body.Bytes(), []byte(`"provider_count"`)) {
		t.Fatalf("expected status payload to hide provider counts from the UI, got %s", statusRec.Body.String())
	}
}

func TestProvidersForRuntimeRefreshesStalePublicRequesterCredential(t *testing.T) {
	var (
		providerCalls int
		upsertAuth    string
	)

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms/members/upsert":
			upsertAuth = r.Header.Get("Authorization")
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: 1},
				Member: swarmMember{ID: "member-kevin-public", Name: "Kevin", Mode: "both", SwarmID: defaultPublicSwarmID},
				Credentials: coordinatorCredentials{Requester: &coordinatorTokenResponse{
					Token:    "fresh-requester",
					Scope:    "requester",
					SwarmID:  defaultPublicSwarmID,
					MemberID: "member-kevin-public",
				}},
			})
		case "/admin/v1/providers":
			providerCalls++
			switch r.Header.Get("Authorization") {
			case "Bearer stale-requester":
				writeJSON(w, http.StatusUnauthorized, map[string]any{
					"error": map[string]any{"code": "UNAUTHORIZED", "message": "valid coordinator token is required"},
				})
			case "Bearer fresh-requester":
				writeJSON(w, http.StatusOK, coordinatorProvidersResponse{})
			default:
				t.Fatalf("unexpected providers authorization header %q", r.Header.Get("Authorization"))
			}
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	t.Setenv("ONLYMACS_NODE_ID", "kevin-public")
	t.Setenv("ONLYMACS_MEMBER_NAME", "Kevin")
	svc := newService(Config{
		CoordinatorURL:   coordinator.URL,
		HTTPClient:       coordinator.Client(),
		RuntimeStatePath: filepath.Join(t.TempDir(), "runtime.json"),
	})
	svc.coordinator.rememberCredentials(coordinatorCredentials{Requester: &coordinatorTokenResponse{
		Token:    "stale-requester",
		Scope:    "requester",
		SwarmID:  defaultPublicSwarmID,
		MemberID: "member-kevin-public",
	}})

	resp, err := svc.providersForRuntimeWithContext(context.Background(), runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: defaultPublicSwarmID,
	})
	if err != nil {
		t.Fatalf("expected stale requester credential to refresh, got %v", err)
	}
	if len(resp.Providers) != 0 {
		t.Fatalf("expected empty provider response, got %+v", resp)
	}
	if providerCalls != 2 {
		t.Fatalf("expected providers retry after stale token, got %d calls", providerCalls)
	}
	if upsertAuth != "" {
		t.Fatalf("expected credential bootstrap to retry without stale authorization, got %q", upsertAuth)
	}
	if token := svc.coordinator.requesterToken(defaultPublicSwarmID, "member-kevin-public"); token != "fresh-requester" {
		t.Fatalf("expected refreshed requester token, got %q", token)
	}
}

func TestRegisterProviderRetriesStaleProviderCredentialWithOwnerRequester(t *testing.T) {
	var authHeaders []string

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/admin/v1/providers/register" {
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
		authHeaders = append(authHeaders, r.Header.Get("Authorization"))
		switch r.Header.Get("Authorization") {
		case "Bearer stale-provider":
			writeJSON(w, http.StatusUnauthorized, map[string]any{
				"error": map[string]any{"code": "UNAUTHORIZED", "message": "valid coordinator token is required"},
			})
		case "Bearer owner-requester":
			writeJSON(w, http.StatusCreated, registerProviderResponse{
				Status: "registered",
				Credentials: coordinatorCredentials{Provider: &coordinatorTokenResponse{
					Token:      "fresh-provider",
					Scope:      "provider",
					ProviderID: "provider-kevin-public",
				}},
			})
		default:
			t.Fatalf("unexpected provider authorization header %q", r.Header.Get("Authorization"))
		}
	}))
	defer coordinator.Close()

	svc := newService(Config{
		CoordinatorURL:   coordinator.URL,
		HTTPClient:       coordinator.Client(),
		RuntimeStatePath: filepath.Join(t.TempDir(), "runtime.json"),
	})
	svc.coordinator.rememberCredentials(coordinatorCredentials{
		Requester: &coordinatorTokenResponse{
			Token:    "owner-requester",
			Scope:    "requester",
			SwarmID:  defaultPublicSwarmID,
			MemberID: "member-kevin-public",
		},
		Provider: &coordinatorTokenResponse{
			Token:      "stale-provider",
			Scope:      "provider",
			ProviderID: "provider-kevin-public",
		},
	})

	_, err := svc.coordinator.registerProviderWithContext(context.Background(), registerProviderRequest{
		Provider: provider{
			ID:            "provider-kevin-public",
			Name:          "Kevin",
			SwarmID:       defaultPublicSwarmID,
			OwnerMemberID: "member-kevin-public",
		},
	})
	if err != nil {
		t.Fatalf("expected stale provider credential to recover, got %v", err)
	}
	if len(authHeaders) != 2 {
		t.Fatalf("expected provider register retry, got headers %v", authHeaders)
	}
	if token := svc.coordinator.providerToken("provider-kevin-public"); token != "fresh-provider" {
		t.Fatalf("expected refreshed provider token, got %q", token)
	}
}

func TestRegisterProviderUsesOwnerRequesterWhenProviderCredentialIsMissing(t *testing.T) {
	var authHeaders []string

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/admin/v1/providers/register" {
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
		authHeaders = append(authHeaders, r.Header.Get("Authorization"))
		if r.Header.Get("Authorization") != "Bearer owner-requester" {
			t.Fatalf("unexpected provider authorization header %q", r.Header.Get("Authorization"))
		}
		writeJSON(w, http.StatusCreated, registerProviderResponse{
			Status: "registered",
			Credentials: coordinatorCredentials{Provider: &coordinatorTokenResponse{
				Token:      "fresh-provider",
				Scope:      "provider",
				ProviderID: "provider-kevin-public",
			}},
		})
	}))
	defer coordinator.Close()

	svc := newService(Config{
		CoordinatorURL:   coordinator.URL,
		HTTPClient:       coordinator.Client(),
		RuntimeStatePath: filepath.Join(t.TempDir(), "runtime.json"),
	})
	svc.coordinator.rememberCredentials(coordinatorCredentials{
		Requester: &coordinatorTokenResponse{
			Token:    "owner-requester",
			Scope:    "requester",
			SwarmID:  defaultPublicSwarmID,
			MemberID: "member-kevin-public",
		},
	})

	_, err := svc.coordinator.registerProviderWithContext(context.Background(), registerProviderRequest{
		Provider: provider{
			ID:            "provider-kevin-public",
			Name:          "Kevin",
			SwarmID:       defaultPublicSwarmID,
			OwnerMemberID: "member-kevin-public",
		},
	})
	if err != nil {
		t.Fatalf("expected missing provider credential to recover through owner requester, got %v", err)
	}
	if len(authHeaders) != 1 {
		t.Fatalf("expected one owner requester attempt, got headers %v", authHeaders)
	}
	if token := svc.coordinator.providerToken("provider-kevin-public"); token != "fresh-provider" {
		t.Fatalf("expected refreshed provider token, got %q", token)
	}
}

func TestPublicRuntimeStatusAutoPublishesCapableMachine(t *testing.T) {
	var (
		publicMemberCount int
		publishedProvider provider
		upsertedMember    upsertMemberRequest
	)
	originalHardwareProfile := currentHardwareProfile
	t.Cleanup(func() { currentHardwareProfile = originalHardwareProfile })
	currentHardwareProfile = func() *hardwareProfile {
		return &hardwareProfile{CPUBrand: "M3 Max", MemoryGB: 64}
	}

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			writeJSON(w, http.StatusOK, map[string]any{
				"data": []map[string]any{
					{"id": "qwen2.5-coder:14b"},
				},
			})
		default:
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
	}))
	defer inference.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/admin/v1/swarms/members/upsert":
			if err := json.NewDecoder(r.Body).Decode(&upsertedMember); err != nil {
				t.Fatalf("decode upsert member request: %v", err)
			}
			publicMemberCount = 1
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: publicMemberCount, ProviderCount: boolToInt(publishedProvider.ID != "")},
				Member: swarmMember{ID: "member-kevin-public", Name: "Kevin", Mode: "both", SwarmID: defaultPublicSwarmID, ClientBuild: upsertedMember.ClientBuild},
			})
		case r.URL.Path == "/admin/v1/providers/register":
			var req registerProviderRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode register provider request: %v", err)
			}
			publishedProvider = req.Provider
			writeJSON(w, http.StatusCreated, registerProviderResponse{Status: "registered", Provider: req.Provider})
		case r.URL.Path == "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{
				Swarms: []swarm{{
					ID:            defaultPublicSwarmID,
					Name:          "OnlyMacs Public",
					Visibility:    "public",
					MemberCount:   publicMemberCount,
					ProviderCount: boolToInt(publishedProvider.ID != ""),
					SlotsFree:     publishedProvider.Slots.Free,
					SlotsTotal:    publishedProvider.Slots.Total,
				}},
			})
		case r.URL.Path == "/admin/v1/providers":
			providers := []provider{}
			if publishedProvider.ID != "" {
				providers = append(providers, publishedProvider)
			}
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{Providers: providers})
		case r.URL.Path == "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{})
		case r.URL.Path == "/admin/v1/members/summary":
			if publicMemberCount == 0 {
				http.Error(w, `{"error":{"code":"MEMBER_NOT_FOUND","message":"member could not be found"}}`, http.StatusNotFound)
				return
			}
			writeJSON(w, http.StatusOK, memberSummaryResponse{
				MemberID:               r.URL.Query().Get("member_id"),
				MemberName:             "Kevin",
				SwarmID:                defaultPublicSwarmID,
				SwarmMemberCount:       publicMemberCount,
				SwarmProviderCount:     boolToInt(publishedProvider.ID != ""),
				ProviderCount:          boolToInt(publishedProvider.ID != ""),
				ActiveReservations:     0,
				ReservationCap:         4,
				ServedSessions:         0,
				UploadedTokensEstimate: 0,
				CommunityBoost: coordinatorCommunityBoostSummary{
					Level:        3,
					Label:        "Steady",
					PrimaryTrait: "Fresh Face",
					Traits:       []string{"Fresh Face"},
					Detail:       "Fresh start. You're in the swarm.",
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	t.Setenv("ONLYMACS_NODE_ID", "kevin-public")
	t.Setenv("ONLYMACS_MEMBER_NAME", "Kevin")

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		OllamaURL:           inference.URL,
		InferenceHTTPClient: inference.Client(),
		CannedChat:          true,
		ClientBuild: &clientBuild{
			Product:     " OnlyMacs ",
			Version:     "0.1.0",
			BuildNumber: " 20260424141723 ",
			Channel:     " public ",
		},
	})

	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: defaultPublicSwarmID,
	})

	statusReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil)
	statusRec := httptest.NewRecorder()
	mux.ServeHTTP(statusRec, statusReq)
	if statusRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, statusRec.Code, statusRec.Body.String())
	}
	if publicMemberCount != 1 {
		t.Fatalf("expected capable public machine to upsert membership, got %d", publicMemberCount)
	}
	if publishedProvider.ID == "" {
		t.Fatalf("expected capable public machine to auto-publish a provider")
	}
	if publishedProvider.Hardware == nil || publishedProvider.Hardware.CPUBrand != "M3 Max" || publishedProvider.Hardware.MemoryGB != 64 {
		t.Fatalf("expected current CPU/RAM hardware to be published, got %+v", publishedProvider.Hardware)
	}
	if publishedProvider.ClientBuild == nil || publishedProvider.ClientBuild.Product != "OnlyMacs" || publishedProvider.ClientBuild.BuildNumber != "20260424141723" || publishedProvider.ClientBuild.Channel != "public" {
		t.Fatalf("expected normalized app build to be published, got %+v", publishedProvider.ClientBuild)
	}
	if upsertedMember.ClientBuild == nil || upsertedMember.ClientBuild.BuildNumber != "20260424141723" {
		t.Fatalf("expected public membership upsert to include app build, got %+v", upsertedMember.ClientBuild)
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"member_count":1`)) {
		t.Fatalf("expected public member count in status payload, got %s", statusRec.Body.String())
	}
	if bytes.Contains(statusRec.Body.Bytes(), []byte(`"provider_count"`)) {
		t.Fatalf("expected status payload to hide provider counts from the UI, got %s", statusRec.Body.String())
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"published":true`)) {
		t.Fatalf("expected share status to report published, got %s", statusRec.Body.String())
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"client_build"`)) {
		t.Fatalf("expected status payload to include client build, got %s", statusRec.Body.String())
	}

	currentHardwareProfile = func() *hardwareProfile {
		return &hardwareProfile{CPUBrand: "M4 Max", MemoryGB: 128}
	}
	secondStatusRec := httptest.NewRecorder()
	mux.ServeHTTP(secondStatusRec, httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil))
	if secondStatusRec.Code != http.StatusOK {
		t.Fatalf("expected second status %d, got %d: %s", http.StatusOK, secondStatusRec.Code, secondStatusRec.Body.String())
	}
	if publishedProvider.Hardware == nil || publishedProvider.Hardware.CPUBrand != "M4 Max" || publishedProvider.Hardware.MemoryGB != 128 {
		t.Fatalf("expected startup/status refresh to republish current hardware, got %+v", publishedProvider.Hardware)
	}

	publishedProvider.ActiveSessions = 1
	publishedProvider.Slots.Free = 0
	for idx := range publishedProvider.Models {
		publishedProvider.Models[idx].SlotsFree = 0
	}
	thirdStatusRec := httptest.NewRecorder()
	mux.ServeHTTP(thirdStatusRec, httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil))
	if thirdStatusRec.Code != http.StatusOK {
		t.Fatalf("expected third status %d, got %d: %s", http.StatusOK, thirdStatusRec.Code, thirdStatusRec.Body.String())
	}
	if publishedProvider.ActiveSessions != 0 || publishedProvider.Slots.Free != publishedProvider.Slots.Total || publishedProvider.Models[0].SlotsFree != publishedProvider.Models[0].SlotsTotal {
		t.Fatalf("expected share refresh to clear stale remote reservation accounting, got %+v", publishedProvider)
	}
}

func TestPublicRuntimeStatusPreservesLocallyActiveShareCapacity(t *testing.T) {
	var publicMemberCount int
	var publishedProvider provider

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			writeJSON(w, http.StatusOK, map[string]any{
				"data": []map[string]any{{"id": "qwen2.5-coder:14b"}},
			})
		default:
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
	}))
	defer inference.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/admin/v1/swarms/members/upsert":
			publicMemberCount = 1
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: publicMemberCount, ProviderCount: boolToInt(publishedProvider.ID != "")},
				Member: swarmMember{ID: "member-kevin-public", Name: "Kevin", Mode: "both", SwarmID: defaultPublicSwarmID},
			})
		case r.URL.Path == "/admin/v1/providers/register":
			var req registerProviderRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode register provider request: %v", err)
			}
			publishedProvider = req.Provider
			writeJSON(w, http.StatusCreated, registerProviderResponse{Status: "registered", Provider: req.Provider})
		case r.URL.Path == "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{
				Swarms: []swarm{{
					ID:            defaultPublicSwarmID,
					Name:          "OnlyMacs Public",
					Visibility:    "public",
					MemberCount:   publicMemberCount,
					ProviderCount: boolToInt(publishedProvider.ID != ""),
					SlotsFree:     publishedProvider.Slots.Free,
					SlotsTotal:    publishedProvider.Slots.Total,
				}},
			})
		case r.URL.Path == "/admin/v1/providers":
			providers := []provider{}
			if publishedProvider.ID != "" {
				providers = append(providers, publishedProvider)
			}
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{Providers: providers})
		case r.URL.Path == "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{})
		case r.URL.Path == "/admin/v1/members/summary":
			writeJSON(w, http.StatusOK, memberSummaryResponse{
				MemberID:           r.URL.Query().Get("member_id"),
				MemberName:         "Kevin",
				SwarmID:            defaultPublicSwarmID,
				SwarmMemberCount:   publicMemberCount,
				SwarmProviderCount: boolToInt(publishedProvider.ID != ""),
				ProviderCount:      boolToInt(publishedProvider.ID != ""),
				ReservationCap:     4,
				CommunityBoost: coordinatorCommunityBoostSummary{
					Level:        3,
					Label:        "Steady",
					PrimaryTrait: "Fresh Face",
					Traits:       []string{"Fresh Face"},
					Detail:       "Fresh start. You're in the swarm.",
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	t.Setenv("ONLYMACS_NODE_ID", "kevin-public-active")
	t.Setenv("ONLYMACS_MEMBER_NAME", "Kevin")

	service := newService(Config{
		CoordinatorURL:            coordinator.URL,
		HTTPClient:                coordinator.Client(),
		OllamaURL:                 inference.URL,
		InferenceHTTPClient:       inference.Client(),
		CannedChat:                true,
		EnableProviderRelayWorker: false,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: defaultPublicSwarmID,
	})

	service.shareMetrics.beginActiveSession()
	activeRec := httptest.NewRecorder()
	service.statusHandler(activeRec, httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil))
	if activeRec.Code != http.StatusOK {
		t.Fatalf("expected active status %d, got %d: %s", http.StatusOK, activeRec.Code, activeRec.Body.String())
	}
	if publishedProvider.ActiveSessions != 1 || publishedProvider.Slots.Free != 0 || publishedProvider.Models[0].SlotsFree != 0 {
		t.Fatalf("expected active local relay to publish busy capacity, got %+v", publishedProvider)
	}

	service.shareMetrics.endActiveSession()
	idleRec := httptest.NewRecorder()
	service.statusHandler(idleRec, httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil))
	if idleRec.Code != http.StatusOK {
		t.Fatalf("expected idle status %d, got %d: %s", http.StatusOK, idleRec.Code, idleRec.Body.String())
	}
	if publishedProvider.ActiveSessions != 0 || publishedProvider.Slots.Free != publishedProvider.Slots.Total || publishedProvider.Models[0].SlotsFree != publishedProvider.Models[0].SlotsTotal {
		t.Fatalf("expected idle refresh to republish free capacity, got %+v", publishedProvider)
	}
}

func TestPublicRuntimeStatusKeepsMemberAndDropsProviderWhenCapabilityDisappears(t *testing.T) {
	var (
		publicMemberCount int
		publishedProvider provider
		modelsReady       = true
		removeCalls       int
		unregisterCalls   int
	)

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			payload := []map[string]any{}
			if modelsReady {
				payload = append(payload, map[string]any{"id": "qwen2.5-coder:14b"})
			}
			writeJSON(w, http.StatusOK, map[string]any{"data": payload})
		default:
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
	}))
	defer inference.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/admin/v1/swarms/members/upsert":
			publicMemberCount = 1
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: publicMemberCount, ProviderCount: boolToInt(publishedProvider.ID != "")},
				Member: swarmMember{ID: "member-kevin-public", Name: "Kevin", Mode: "both", SwarmID: defaultPublicSwarmID},
				Credentials: coordinatorCredentials{Requester: &coordinatorTokenResponse{
					Token:    "requester-token",
					Scope:    "requester",
					SwarmID:  defaultPublicSwarmID,
					MemberID: "member-kevin-public",
				}},
			})
		case r.URL.Path == "/admin/v1/swarms/members/remove":
			removeCalls++
			publicMemberCount = 0
			writeJSON(w, http.StatusOK, removeMemberResponse{Status: "removed", SwarmID: defaultPublicSwarmID, MemberID: "member-kevin-public"})
		case r.URL.Path == "/admin/v1/providers/register":
			var req registerProviderRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode register provider request: %v", err)
			}
			publishedProvider = req.Provider
			writeJSON(w, http.StatusCreated, registerProviderResponse{Status: "registered", Provider: req.Provider})
		case r.URL.Path == "/admin/v1/providers/unregister":
			unregisterCalls++
			publishedProvider = provider{}
			writeJSON(w, http.StatusOK, unregisterProviderResponse{Status: "unregistered", ProviderID: "provider-kevin-public"})
		case r.URL.Path == "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{
				Swarms: []swarm{{
					ID:            defaultPublicSwarmID,
					Name:          "OnlyMacs Public",
					Visibility:    "public",
					MemberCount:   publicMemberCount,
					ProviderCount: boolToInt(publishedProvider.ID != ""),
				}},
			})
		case r.URL.Path == "/admin/v1/providers":
			providers := []provider{}
			if publishedProvider.ID != "" {
				providers = append(providers, publishedProvider)
			}
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{Providers: providers})
		case r.URL.Path == "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{})
		case r.URL.Path == "/admin/v1/members/summary":
			if publicMemberCount == 0 {
				http.Error(w, `{"error":{"code":"MEMBER_NOT_FOUND","message":"member could not be found"}}`, http.StatusNotFound)
				return
			}
			writeJSON(w, http.StatusOK, memberSummaryResponse{
				MemberID:               r.URL.Query().Get("member_id"),
				MemberName:             "Kevin",
				SwarmID:                defaultPublicSwarmID,
				SwarmMemberCount:       publicMemberCount,
				SwarmProviderCount:     boolToInt(publishedProvider.ID != ""),
				ProviderCount:          boolToInt(publishedProvider.ID != ""),
				ActiveReservations:     0,
				ReservationCap:         4,
				ServedSessions:         0,
				UploadedTokensEstimate: 0,
				CommunityBoost: coordinatorCommunityBoostSummary{
					Level:        3,
					Label:        "Steady",
					PrimaryTrait: "Fresh Face",
					Traits:       []string{"Fresh Face"},
					Detail:       "Fresh start. You're in the swarm.",
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	t.Setenv("ONLYMACS_NODE_ID", "kevin-public")
	t.Setenv("ONLYMACS_MEMBER_NAME", "Kevin")

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		OllamaURL:           inference.URL,
		InferenceHTTPClient: inference.Client(),
		CannedChat:          true,
	})

	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: defaultPublicSwarmID,
	})

	firstStatusReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil)
	firstStatusRec := httptest.NewRecorder()
	mux.ServeHTTP(firstStatusRec, firstStatusReq)
	if firstStatusRec.Code != http.StatusOK || publishedProvider.ID == "" || publicMemberCount != 1 {
		t.Fatalf("expected first status refresh to publish capable machine, got code=%d body=%s provider=%+v members=%d", firstStatusRec.Code, firstStatusRec.Body.String(), publishedProvider, publicMemberCount)
	}

	modelsReady = false

	secondStatusReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil)
	secondStatusRec := httptest.NewRecorder()
	mux.ServeHTTP(secondStatusRec, secondStatusReq)
	if secondStatusRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, secondStatusRec.Code, secondStatusRec.Body.String())
	}
	if unregisterCalls == 0 {
		t.Fatalf("expected capability loss to unregister the published provider")
	}
	if removeCalls != 0 {
		t.Fatalf("expected capability loss to keep requester membership active, got %d removals", removeCalls)
	}
	if !bytes.Contains(secondStatusRec.Body.Bytes(), []byte(`"member_count":1`)) {
		t.Fatalf("expected public member count to stay at 1, got %s", secondStatusRec.Body.String())
	}
	if bytes.Contains(secondStatusRec.Body.Bytes(), []byte(`"provider_count"`)) {
		t.Fatalf("expected status payload to hide provider counts from the UI, got %s", secondStatusRec.Body.String())
	}
	if !bytes.Contains(secondStatusRec.Body.Bytes(), []byte(`"published":false`)) {
		t.Fatalf("expected share status to report unpublished after capability loss, got %s", secondStatusRec.Body.String())
	}
}

func TestPrivateRuntimeStatusKeepsMemberButDropsPublishedProviderWhenCapabilityDisappears(t *testing.T) {
	var (
		publishedProvider = provider{
			ID:              "provider-kevin-private",
			Name:            "Kevin's MacBook Pro",
			SwarmID:         "swarm-private",
			OwnerMemberID:   "member-kevin-private",
			OwnerMemberName: "Kevin",
			Status:          "available",
			Modes:           []string{"share", "both"},
			Slots:           slots{Free: 1, Total: 1},
			Models: []model{
				{ID: "qwen2.5-coder:14b", Name: "Qwen2.5 Coder 14B", SlotsFree: 1, SlotsTotal: 1},
			},
		}
		unregisterCalls int
	)

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			writeJSON(w, http.StatusOK, map[string]any{"data": []map[string]any{}})
		default:
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
	}))
	defer inference.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/admin/v1/providers/unregister":
			unregisterCalls++
			publishedProvider = provider{}
			writeJSON(w, http.StatusOK, unregisterProviderResponse{Status: "unregistered", ProviderID: "provider-kevin-private"})
		case r.URL.Path == "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{
				Swarms: []swarm{{
					ID:            "swarm-private",
					Name:          "Friends",
					Visibility:    "private",
					MemberCount:   2,
					ProviderCount: boolToInt(publishedProvider.ID != ""),
				}},
			})
		case r.URL.Path == "/admin/v1/providers":
			providers := []provider{}
			if publishedProvider.ID != "" {
				providers = append(providers, publishedProvider)
			}
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{Providers: providers})
		case r.URL.Path == "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{})
		case r.URL.Path == "/admin/v1/members/summary":
			writeJSON(w, http.StatusOK, memberSummaryResponse{
				MemberID:               r.URL.Query().Get("member_id"),
				MemberName:             "Kevin",
				SwarmID:                "swarm-private",
				SwarmMemberCount:       2,
				SwarmProviderCount:     boolToInt(publishedProvider.ID != ""),
				ProviderCount:          0,
				ActiveReservations:     0,
				ReservationCap:         4,
				ServedSessions:         0,
				UploadedTokensEstimate: 0,
				CommunityBoost: coordinatorCommunityBoostSummary{
					Level:        3,
					Label:        "Steady",
					PrimaryTrait: "Fresh Face",
					Traits:       []string{"Fresh Face"},
					Detail:       "Friends swarm membership stays explicit even when a Mac is not helping right now.",
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	t.Setenv("ONLYMACS_NODE_ID", "kevin-private")
	t.Setenv("ONLYMACS_MEMBER_NAME", "Kevin")

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		OllamaURL:           inference.URL,
		InferenceHTTPClient: inference.Client(),
		CannedChat:          true,
	})

	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-private",
	})

	statusReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil)
	statusRec := httptest.NewRecorder()
	mux.ServeHTTP(statusRec, statusReq)
	if statusRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, statusRec.Code, statusRec.Body.String())
	}
	if unregisterCalls == 0 {
		t.Fatalf("expected private published provider to be unpublished when capability disappears")
	}
	if !bytes.Contains(statusRec.Body.Bytes(), []byte(`"member_count":2`)) {
		t.Fatalf("expected private member count to stay explicit, got %s", statusRec.Body.String())
	}
	if bytes.Contains(statusRec.Body.Bytes(), []byte(`"provider_count"`)) {
		t.Fatalf("expected status payload to hide provider counts from the UI, got %s", statusRec.Body.String())
	}
}

func TestSwarmCreateJoinInviteAndLocalSharePublish(t *testing.T) {
	t.Setenv("ONLYMACS_NODE_ID", "bridge-test-node")

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			writeJSON(w, http.StatusOK, map[string]any{
				"data": []map[string]any{
					{"id": "qwen2.5-coder:32b"},
					{"id": "gemma4:26b"},
				},
			})
		default:
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
	}))
	defer inference.Close()

	var (
		currentSwarm  = swarm{ID: "swarm-000001", Name: "Public Swarm", MemberCount: 1, ProviderCount: 0}
		currentInvite = swarmInvite{InviteToken: "invite-000001", SwarmID: "swarm-000001", SwarmName: "Public Swarm"}
		published     provider
	)

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/admin/v1/swarms" && r.Method == http.MethodPost:
			var req createSwarmRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode create swarm request: %v", err)
			}
			if req.Name != "" {
				currentSwarm.Name = req.Name
				currentInvite.SwarmName = req.Name
			}
			if req.Visibility != "private" || req.Discoverability != "unlisted" || req.JoinPolicy == nil || req.JoinPolicy.Mode != "invite_link" {
				t.Fatalf("expected private swarm create request to use unlisted invite-link defaults, got %+v", req)
			}
			writeJSON(w, http.StatusCreated, createSwarmResponse{Swarm: currentSwarm})
		case r.URL.Path == "/admin/v1/swarms" && r.Method == http.MethodGet:
			resp := coordinatorSwarmsResponse{Swarms: []swarm{currentSwarm}}
			if published.ID != "" {
				resp.Swarms[0].ProviderCount = 1
			}
			writeJSON(w, http.StatusOK, resp)
		case r.URL.Path == "/admin/v1/swarms/swarm-000001/invites":
			writeJSON(w, http.StatusCreated, createSwarmInviteResponse{Invite: currentInvite})
		case r.URL.Path == "/admin/v1/swarms/join":
			var req joinSwarmRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode join swarm request: %v", err)
			}
			writeJSON(w, http.StatusOK, joinSwarmResponse{
				Swarm: currentSwarm,
				Member: swarmMember{
					ID:      req.MemberID,
					Name:    req.MemberName,
					Mode:    req.Mode,
					SwarmID: currentSwarm.ID,
				},
			})
		case r.URL.Path == "/admin/v1/providers/register":
			var req registerProviderRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode register provider request: %v", err)
			}
			published = req.Provider
			currentSwarm.ProviderCount = 1
			writeJSON(w, http.StatusCreated, registerProviderResponse{
				Status:   "registered",
				Provider: published,
			})
		case r.URL.Path == "/admin/v1/providers/unregister":
			published = provider{}
			currentSwarm.ProviderCount = 0
			writeJSON(w, http.StatusOK, unregisterProviderResponse{
				Status:     "unregistered",
				ProviderID: "provider-localhost",
			})
		case r.URL.Path == "/admin/v1/providers" && r.URL.Query().Get("swarm_id") == "":
			if published.ID == "" {
				writeJSON(w, http.StatusOK, coordinatorProvidersResponse{})
				return
			}
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{Providers: []provider{published}})
		case r.URL.Path == "/admin/v1/providers" && r.URL.Query().Get("swarm_id") == currentSwarm.ID:
			if published.ID == "" {
				writeJSON(w, http.StatusOK, coordinatorProvidersResponse{})
				return
			}
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{Providers: []provider{published}})
		case r.URL.Path == "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{})
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		OllamaURL:           inference.URL,
		InferenceHTTPClient: inference.Client(),
		CannedChat:          true,
	})

	createSwarmBody, err := json.Marshal(createLocalSwarmRequest{
		Name:       "Public Swarm",
		MemberName: "Kevin",
		Mode:       "both",
	})
	if err != nil {
		t.Fatalf("marshal create swarm body: %v", err)
	}

	createSwarmReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarms/create", bytes.NewReader(createSwarmBody))
	createSwarmRec := httptest.NewRecorder()
	mux.ServeHTTP(createSwarmRec, createSwarmReq)
	if createSwarmRec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d", http.StatusCreated, createSwarmRec.Code)
	}

	var createResp createLocalSwarmResponse
	if err := json.Unmarshal(createSwarmRec.Body.Bytes(), &createResp); err != nil {
		t.Fatalf("unmarshal create swarm response: %v", err)
	}
	if createResp.Runtime.ActiveSwarmID == "" {
		t.Fatalf("expected active swarm id to be set, got %+v", createResp.Runtime)
	}

	inviteReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarms/invite", bytes.NewReader([]byte("{}")))
	inviteRec := httptest.NewRecorder()
	mux.ServeHTTP(inviteRec, inviteReq)
	if inviteRec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d", http.StatusCreated, inviteRec.Code)
	}

	shareReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/share/publish", bytes.NewReader([]byte(`{"slots_total":1}`)))
	shareRec := httptest.NewRecorder()
	mux.ServeHTTP(shareRec, shareReq)
	if shareRec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d", http.StatusCreated, shareRec.Code)
	}
	if !bytes.Contains(shareRec.Body.Bytes(), []byte(`"provider-bridge-test-node"`)) {
		t.Fatalf("expected deterministic provider id in publish response, got %s", shareRec.Body.String())
	}
	if !bytes.Contains(shareRec.Body.Bytes(), []byte(`"published":true`)) {
		t.Fatalf("expected sharing response to report published state, got %s", shareRec.Body.String())
	}

	shareStatusReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/share/local", nil)
	shareStatusRec := httptest.NewRecorder()
	mux.ServeHTTP(shareStatusRec, shareStatusReq)
	if shareStatusRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, shareStatusRec.Code)
	}
	if !bytes.Contains(shareStatusRec.Body.Bytes(), []byte(`"published":true`)) {
		t.Fatalf("expected published share status, got %s", shareStatusRec.Body.String())
	}
	if !bytes.Contains(shareStatusRec.Body.Bytes(), []byte(`"qwen2.5-coder:32b"`)) {
		t.Fatalf("expected discovered local model in share status, got %s", shareStatusRec.Body.String())
	}

	unpublishReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/share/unpublish", bytes.NewReader([]byte("{}")))
	unpublishRec := httptest.NewRecorder()
	mux.ServeHTTP(unpublishRec, unpublishReq)
	if unpublishRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, unpublishRec.Code)
	}
	if !bytes.Contains(unpublishRec.Body.Bytes(), []byte(`"status":"unregistered"`)) {
		t.Fatalf("expected unregistered response, got %s", unpublishRec.Body.String())
	}
}

func TestLocalShareStatusIncludesRecentProviderActivity(t *testing.T) {
	t.Setenv("ONLYMACS_NODE_ID", "bridge-test-node")

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/v1/models":
			writeJSON(w, http.StatusOK, map[string]any{
				"data": []map[string]any{
					{"id": "qwen3.6:35b-a3b-q8_0"},
				},
			})
		default:
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
	}))
	defer inference.Close()

	localMemberID, localMemberName := localMemberIdentity()
	localProviderID, _ := localProviderIdentity()
	published := provider{
		ID:              localProviderID,
		Name:            "This Mac",
		SwarmID:         "swarm-public",
		OwnerMemberID:   localMemberID,
		OwnerMemberName: localMemberName,
		Status:          "available",
		Modes:           []string{"share", "both"},
		Slots:           slots{Free: 1, Total: 1},
		Models: []model{
			{ID: "qwen3.6:35b-a3b-q8_0", Name: "qwen3.6:35b-a3b-q8_0", SlotsFree: 1, SlotsTotal: 1},
		},
	}

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{
				Swarms: []swarm{{ID: "swarm-public", Name: "OnlyMacs Public", MemberCount: 2, SlotsFree: 1, SlotsTotal: 1}},
			})
		case "/admin/v1/swarms/members/upsert":
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: "swarm-public", Name: "OnlyMacs Public", Visibility: "public", MemberCount: 2, SlotsFree: 1, SlotsTotal: 1},
				Member: swarmMember{ID: localMemberID, Name: localMemberName, Mode: "both", SwarmID: "swarm-public"},
			})
		case "/admin/v1/swarms/members/remove":
			writeJSON(w, http.StatusOK, removeMemberResponse{
				Status:   "removed",
				SwarmID:  "swarm-public",
				MemberID: localMemberID,
			})
		case "/admin/v1/providers/register":
			var req registerProviderRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode register provider request: %v", err)
			}
			published = req.Provider
			writeJSON(w, http.StatusCreated, registerProviderResponse{
				Status:   "registered",
				Provider: published,
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{Providers: []provider{published}})
		case "/admin/v1/providers/unregister":
			writeJSON(w, http.StatusOK, unregisterProviderResponse{
				Status:     "unregistered",
				ProviderID: localProviderID,
			})
		case "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{
				Activities: []providerActivity{
					{
						ID:                     "relay-000777",
						JobID:                  "relay-000777",
						SessionID:              "sess-000777",
						SwarmID:                "swarm-public",
						SwarmName:              "OnlyMacs Public",
						ProviderID:             localProviderID,
						ProviderName:           "This Mac",
						OwnerMemberID:          localMemberID,
						OwnerMemberName:        localMemberName,
						RequesterMemberID:      "member-charles",
						RequesterMemberName:    "Charles",
						ResolvedModel:          "qwen3.6:35b-a3b-q8_0",
						Status:                 "completed",
						StatusCode:             http.StatusOK,
						UploadedBytes:          2048,
						UploadedTokensEstimate: 512,
						StartedAt:              "2026-04-22T05:30:00Z",
						UpdatedAt:              "2026-04-22T05:31:00Z",
						CompletedAt:            "2026-04-22T05:31:00Z",
					},
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		OllamaURL:           inference.URL,
		InferenceHTTPClient: inference.Client(),
		CannedChat:          true,
	})

	runtimeBody := []byte(`{"mode":"both","active_swarm_id":"swarm-public"}`)
	runtimeReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/runtime", bytes.NewReader(runtimeBody))
	runtimeRec := httptest.NewRecorder()
	mux.ServeHTTP(runtimeRec, runtimeReq)
	if runtimeRec.Code != http.StatusOK {
		t.Fatalf("expected runtime status %d, got %d", http.StatusOK, runtimeRec.Code)
	}

	shareStatusReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/share/local", nil)
	shareStatusRec := httptest.NewRecorder()
	mux.ServeHTTP(shareStatusRec, shareStatusReq)
	if shareStatusRec.Code != http.StatusOK {
		t.Fatalf("expected share status %d, got %d", http.StatusOK, shareStatusRec.Code)
	}
	if !bytes.Contains(shareStatusRec.Body.Bytes(), []byte(`"recent_provider_activity"`)) {
		t.Fatalf("expected recent provider activity in share status, got %s", shareStatusRec.Body.String())
	}
	if !bytes.Contains(shareStatusRec.Body.Bytes(), []byte(`"Charles"`)) {
		t.Fatalf("expected requester name in provider activity feed, got %s", shareStatusRec.Body.String())
	}
	if !bytes.Contains(shareStatusRec.Body.Bytes(), []byte(`"uploaded_tokens_estimate":512`)) {
		t.Fatalf("expected uploaded token estimate in provider activity feed, got %s", shareStatusRec.Body.String())
	}
}

func TestChatCompletionsLocalOnlyPreservesRouteScopeAndLocalProvider(t *testing.T) {
	localProviderID, _ := localProviderIdentity()
	var reserveReq reserveSessionRequest

	inference := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/models" {
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"data": []map[string]any{{"id": "qwen2.5-coder:32b"}},
		})
	}))
	defer inference.Close()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{
				Swarms: []swarm{{ID: "swarm-alpha", Name: "Alpha Swarm", MemberCount: 1, ProviderCount: 1}},
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:             localProviderID,
						Name:           "This Mac",
						SwarmID:        "swarm-alpha",
						Status:         "available",
						Modes:          []string{"share", "both"},
						Slots:          slots{Free: 1, Total: 1},
						ActiveSessions: 0,
						Models:         []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1}},
					},
				},
			})
		case "/admin/v1/providers/register":
			var registerReq registerProviderRequest
			if err := json.NewDecoder(r.Body).Decode(&registerReq); err != nil {
				t.Fatalf("decode register request: %v", err)
			}
			writeJSON(w, http.StatusCreated, registerProviderResponse{
				Status:   "registered",
				Provider: registerReq.Provider,
			})
		case "/admin/v1/members/summary":
			writeJSON(w, http.StatusOK, memberSummaryResponse{
				MemberID:               r.URL.Query().Get("member_id"),
				MemberName:             "Kevin",
				SwarmID:                "swarm-alpha",
				ProviderCount:          1,
				ActiveReservations:     0,
				ReservationCap:         4,
				UploadedTokensEstimate: 0,
				CommunityBoost: coordinatorCommunityBoostSummary{
					Level:        3,
					Label:        "Steady",
					PrimaryTrait: "Fresh Face",
					Traits:       []string{"Fresh Face"},
					Detail:       "Fresh start.",
				},
			})
		case "/admin/v1/sessions/reserve":
			if err := json.NewDecoder(r.Body).Decode(&reserveReq); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-local-only-001",
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
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "sess-local-only-001",
				Status:    "released",
			})
		case "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		OllamaURL:           inference.URL,
		InferenceHTTPClient: inference.Client(),
		CannedChat:          true,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	chatBody, err := json.Marshal(chatCompletionsRequest{
		Model:      "",
		Stream:     true,
		RouteScope: "local_only",
		Messages: []chatMessage{
			{Role: "user", Content: "hello"},
		},
	})
	if err != nil {
		t.Fatalf("marshal chat body: %v", err)
	}

	chatReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", bytes.NewReader(chatBody))
	chatRec := httptest.NewRecorder()
	mux.ServeHTTP(chatRec, chatReq)

	if chatRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, chatRec.Code)
	}
	if reserveReq.RouteScope != "local_only" {
		t.Fatalf("expected local_only route scope, got %+v", reserveReq)
	}
	if reserveReq.RouteProviderID != localProviderID {
		t.Fatalf("expected local provider id %q, got %+v", localProviderID, reserveReq)
	}
	if !bytes.Contains(chatRec.Body.Bytes(), []byte("This Mac")) {
		t.Fatalf("expected canned response to mention This Mac, got %s", chatRec.Body.String())
	}

	statusReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/status", nil)
	statusRec := httptest.NewRecorder()
	mux.ServeHTTP(statusRec, statusReq)
	if statusRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, statusRec.Code)
	}

	var statusResp struct {
		Usage usageSummary `json:"usage"`
	}
	if err := json.Unmarshal(statusRec.Body.Bytes(), &statusResp); err != nil {
		t.Fatalf("decode status response: %v", err)
	}
	if statusResp.Usage.TokensSavedEstimate <= 0 {
		t.Fatalf("expected This Mac local_only request to count toward tokens saved, got %+v", statusResp.Usage)
	}
}

func TestChatCompletionsDoesNotReleaseRemoteRelayReservationLocally(t *testing.T) {
	releaseCalls := 0
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/sessions/reserve":
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-remote-stream-001",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:32b",
				Provider: preflightProvider{
					ID:             "remote-charles",
					Name:           "Charles",
					Status:         "available",
					ActiveSessions: 1,
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/relay/execute":
			w.Header().Set("Content-Type", "text/event-stream")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte("data: {\"choices\":[{\"delta\":{\"content\":\"REMOTE_OK\"}}]}\n\ndata: [DONE]\n\n"))
		case "/admin/v1/sessions/release":
			releaseCalls++
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "sess-remote-stream-001",
				Status:    "released",
			})
		case "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		CannedChat:     true,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	chatBody, err := json.Marshal(chatCompletionsRequest{
		Model:        "qwen2.5-coder:32b",
		Stream:       true,
		RouteScope:   "swarm",
		PreferRemote: true,
		Messages: []chatMessage{
			{Role: "user", Content: "hello"},
		},
	})
	if err != nil {
		t.Fatalf("marshal chat body: %v", err)
	}

	chatReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", bytes.NewReader(chatBody))
	chatRec := httptest.NewRecorder()
	mux.ServeHTTP(chatRec, chatReq)

	if chatRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, chatRec.Code, chatRec.Body.String())
	}
	if releaseCalls != 0 {
		t.Fatalf("expected remote relay reservation release to be owned by coordinator completion, got %d local release calls", releaseCalls)
	}
}

func TestChatCompletionsRecoversPublicRequesterCredentialBeforeReserve(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	resetLocalNodeIDCacheForTest(t)

	firstMemberID, _ := localMemberIdentity()
	var (
		upsertCalls int
		reserveReq  reserveSessionRequest
		reserveAuth string
		releaseReq  releaseSessionRequest
		releaseAuth string
	)

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms/members/upsert":
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
				t.Fatalf("expected recovery upsert to rotate member id away from %q", firstMemberID)
			}
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: 1},
				Member: swarmMember{ID: req.MemberID, Name: req.MemberName, Mode: req.Mode, SwarmID: defaultPublicSwarmID},
				Credentials: coordinatorCredentials{Requester: &coordinatorTokenResponse{
					Token:    "fresh-public-requester",
					Scope:    "requester",
					SwarmID:  defaultPublicSwarmID,
					MemberID: req.MemberID,
				}},
			})
		case "/admin/v1/sessions/reserve":
			reserveAuth = r.Header.Get("Authorization")
			if err := json.NewDecoder(r.Body).Decode(&reserveReq); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
			localProviderID, _ := localProviderIdentity()
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-public-fresh-001",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:32b",
				Provider: preflightProvider{
					ID:     localProviderID,
					Name:   "This Mac",
					Status: "available",
					Slots:  slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/sessions/release":
			releaseAuth = r.Header.Get("Authorization")
			if err := json.NewDecoder(r.Body).Decode(&releaseReq); err != nil {
				t.Fatalf("decode release request: %v", err)
			}
			writeJSON(w, http.StatusOK, releaseSessionResponse{SessionID: releaseReq.SessionID, Status: "released"})
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:   coordinator.URL,
		HTTPClient:       coordinator.Client(),
		RelayHTTPClient:  coordinator.Client(),
		CannedChat:       true,
		RuntimeStatePath: filepath.Join(t.TempDir(), "runtime.json"),
	})

	body := []byte(`{"model":"qwen2.5-coder:32b","stream":false,"messages":[{"role":"user","content":"hello"}]}`)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", bytes.NewReader(body)))

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	rotatedMemberID, _ := localMemberIdentity()
	if rotatedMemberID == firstMemberID {
		t.Fatalf("expected local member id to rotate from %q", firstMemberID)
	}
	if upsertCalls != 2 {
		t.Fatalf("expected one failed upsert and one recovery upsert, got %d", upsertCalls)
	}
	if reserveAuth != "Bearer fresh-public-requester" {
		t.Fatalf("expected reserve to use recovered requester token, got %q", reserveAuth)
	}
	if reserveReq.RequesterMemberID != rotatedMemberID {
		t.Fatalf("expected reserve to use rotated requester member %q, got %+v", rotatedMemberID, reserveReq)
	}
	if releaseAuth != "Bearer fresh-public-requester" || releaseReq.RequesterMemberID != rotatedMemberID {
		t.Fatalf("expected release to use recovered requester context, auth=%q req=%+v", releaseAuth, releaseReq)
	}
}

func TestChatCompletionsReportsRequesterSwarmCapConflict(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/sessions/reserve":
			writeJSON(w, http.StatusConflict, map[string]any{
				"error": map[string]any{
					"code":    "NO_CAPACITY",
					"message": "no provider capacity is available for the requested model",
				},
			})
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel:              "qwen2.5-coder:32b",
				ResolvedModel:               "qwen2.5-coder:32b",
				RouteScope:                  "swarm",
				Available:                   false,
				RequesterActiveReservations: 4,
				RequesterReservationCap:     4,
				RequesterReservationBlocked: true,
				SelectionReason:             "requester_swarm_cap",
			})
		case "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		CannedChat:     true,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", bytes.NewReader([]byte(`{"model":"qwen2.5-coder:32b","stream":false,"messages":[{"role":"user","content":"Review this patch."}]}`)))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected status %d, got %d: %s", http.StatusConflict, rec.Code, rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"code":"REQUESTER_POOL_CAP"`)) {
		t.Fatalf("expected requester swarm cap error code, got %s", rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"requester_reservation_cap":4`)) {
		t.Fatalf("expected requester reservation cap details, got %s", rec.Body.String())
	}
}

func TestChatCompletionsRemoteFirstReportsRemoteUnavailable(t *testing.T) {
	localProviderID, _ := localProviderIdentity()
	var preflightReq preflightRequest
	var reserveReq reserveSessionRequest

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/sessions/reserve":
			if err := json.NewDecoder(r.Body).Decode(&reserveReq); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
			writeJSON(w, http.StatusConflict, map[string]any{
				"error": map[string]any{
					"code":    "NO_CAPACITY",
					"message": "no provider capacity is available for the requested model",
				},
			})
		case "/admin/v1/preflight":
			if err := json.NewDecoder(r.Body).Decode(&preflightReq); err != nil {
				t.Fatalf("decode preflight request: %v", err)
			}
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel:  "",
				ResolvedModel:   "",
				RouteScope:      "swarm",
				Available:       false,
				Providers:       []preflightProvider{},
				AvailableModels: []model{},
			})
		case "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		CannedChat:     true,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", bytes.NewReader([]byte(`{"model":"","stream":false,"route_scope":"swarm","prefer_remote":true,"messages":[{"role":"user","content":"Reply with REMOTE_ONLY_OK exactly."}]}`)))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusConflict {
		t.Fatalf("expected status %d, got %d: %s", http.StatusConflict, rec.Code, rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"code":"REMOTE_UNAVAILABLE"`)) {
		t.Fatalf("expected remote unavailable error code, got %s", rec.Body.String())
	}
	if len(reserveReq.ExcludeProviderIDs) != 1 || reserveReq.ExcludeProviderIDs[0] != localProviderID {
		t.Fatalf("expected remote-first reserve to exclude %q, got %+v", localProviderID, reserveReq)
	}
	if len(preflightReq.ExcludeProviderIDs) != 1 || preflightReq.ExcludeProviderIDs[0] != localProviderID {
		t.Fatalf("expected remote-first preflight to exclude %q, got %+v", localProviderID, preflightReq)
	}
}

func TestPreflightBestAvailableAliasUsesCoordinatorDefault(t *testing.T) {
	var (
		preflightReq  preflightRequest
		preflightAuth string
		upsertCalls   int
	)

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms/members/upsert":
			upsertCalls++
			var req upsertMemberRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode upsert request: %v", err)
			}
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: 1},
				Member: swarmMember{ID: req.MemberID, Name: req.MemberName, Mode: req.Mode, SwarmID: defaultPublicSwarmID},
				Credentials: coordinatorCredentials{Requester: &coordinatorTokenResponse{
					Token:    "fresh-preflight-requester",
					Scope:    "requester",
					SwarmID:  defaultPublicSwarmID,
					MemberID: req.MemberID,
				}},
			})
		case "/admin/v1/preflight":
			preflightAuth = r.Header.Get("Authorization")
			if err := json.NewDecoder(r.Body).Decode(&preflightReq); err != nil {
				t.Fatalf("decode preflight request: %v", err)
			}
			if preflightReq.Model != "" {
				t.Fatalf("expected best-available alias to be sent as coordinator default, got %q", preflightReq.Model)
			}
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel:       "",
				ResolvedModel:        "qwen3.6:35b-a3b-q4_K_M",
				RouteScope:           "swarm",
				SelectionReason:      "best_available",
				SelectionExplanation: "OnlyMacs chose qwen3.6:35b-a3b-q4_K_M because it is the strongest model with an open slot right now.",
				Available:            true,
				Providers: []preflightProvider{
					{
						ID:             "public-provider",
						Name:           "Public Mac",
						Status:         "available",
						ActiveSessions: 0,
						Slots:          slots{Free: 1, Total: 1},
						MatchingModels: []model{{ID: "qwen3.6:35b-a3b-q4_K_M", Name: "Qwen 3.6", SlotsFree: 1, SlotsTotal: 1}},
					},
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		CannedChat:     true,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: defaultPublicSwarmID,
	})

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/preflight", bytes.NewReader([]byte(`{"model":"best-available","max_providers":1,"route_scope":"swarm"}`)))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if upsertCalls != 1 {
		t.Fatalf("expected fresh public preflight to bootstrap requester credential once, got %d", upsertCalls)
	}
	if preflightAuth != "Bearer fresh-preflight-requester" {
		t.Fatalf("expected preflight to use bootstrapped requester token, got %q", preflightAuth)
	}
	if preflightReq.RequesterMemberID == "" {
		t.Fatalf("expected preflight to include requester member id, got %+v", preflightReq)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"available":true`)) || !bytes.Contains(rec.Body.Bytes(), []byte(`"resolved_model":"qwen3.6:35b-a3b-q4_K_M"`)) {
		t.Fatalf("expected best-available preflight to resolve through coordinator, got %s", rec.Body.String())
	}
}

func TestJoinInvalidInviteMapsTo404(t *testing.T) {
	t.Setenv("ONLYMACS_NODE_ID", "bridge-test-node")

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/admin/v1/swarms/join":
			http.Error(w, `{"error":{"code":"INVITE_NOT_FOUND","message":"invite token could not be resolved"}}`, http.StatusNotFound)
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		CannedChat:     true,
	})

	body, err := json.Marshal(joinLocalSwarmRequest{
		InviteToken: "invite-missing",
		MemberName:  "Kevin",
		Mode:        "both",
	})
	if err != nil {
		t.Fatalf("marshal join body: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarms/join", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected status %d, got %d", http.StatusNotFound, rec.Code)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"INVITE_NOT_FOUND"`)) {
		t.Fatalf("expected invite not found error, got %s", rec.Body.String())
	}
}

func TestJoinPublicSwarmWithoutInviteToken(t *testing.T) {
	t.Setenv("ONLYMACS_NODE_ID", "bridge-test-node")

	var received joinSwarmRequest
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/admin/v1/swarms/join":
			if err := json.NewDecoder(r.Body).Decode(&received); err != nil {
				t.Fatalf("decode public join request: %v", err)
			}
			writeJSON(w, http.StatusOK, joinSwarmResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: 1},
				Member: swarmMember{ID: "member-bridge-test-node", Name: "Kevin", Mode: "both", SwarmID: defaultPublicSwarmID},
			})
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		CannedChat:     true,
	})

	body, err := json.Marshal(joinLocalSwarmRequest{
		SwarmID:    defaultPublicSwarmID,
		MemberName: "Kevin",
		Mode:       "both",
	})
	if err != nil {
		t.Fatalf("marshal public join body: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarms/join", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if received.SwarmID != defaultPublicSwarmID || received.InviteToken != "" {
		t.Fatalf("expected open public join by swarm id without invite, got %+v", received)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"active_swarm_id":"swarm-public"`)) {
		t.Fatalf("expected runtime to select public swarm, got %s", rec.Body.String())
	}
}

func TestJoinPublicSwarmRecoversRequesterTokenMismatchByRotatingMember(t *testing.T) {
	t.Setenv("HOME", t.TempDir())
	resetLocalNodeIDCacheForTest(t)

	firstMemberID, _ := localMemberIdentity()
	var received []joinSwarmRequest
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/admin/v1/swarms/join":
			var req joinSwarmRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode public join request: %v", err)
			}
			received = append(received, req)
			if len(received) == 1 {
				if req.MemberID != firstMemberID {
					t.Fatalf("expected first join to use original member id %q, got %q", firstMemberID, req.MemberID)
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
			writeJSON(w, http.StatusOK, joinSwarmResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public", MemberCount: 1},
				Member: swarmMember{ID: req.MemberID, Name: req.MemberName, Mode: req.Mode, SwarmID: defaultPublicSwarmID},
				Credentials: coordinatorCredentials{Requester: &coordinatorTokenResponse{
					Token:    "fresh-public-requester",
					Scope:    "requester",
					SwarmID:  defaultPublicSwarmID,
					MemberID: req.MemberID,
				}},
			})
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:   coordinator.URL,
		HTTPClient:       coordinator.Client(),
		CannedChat:       true,
		RuntimeStatePath: filepath.Join(t.TempDir(), "runtime.json"),
	})

	body, err := json.Marshal(joinLocalSwarmRequest{
		SwarmID:    defaultPublicSwarmID,
		MemberName: "Shen",
		Mode:       "both",
	})
	if err != nil {
		t.Fatalf("marshal public join body: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarms/join", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if len(received) != 2 {
		t.Fatalf("expected join recovery to retry once, got %+v", received)
	}
	rotatedMemberID, _ := localMemberIdentity()
	if rotatedMemberID == firstMemberID {
		t.Fatalf("expected local member id to rotate from %q", firstMemberID)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(rotatedMemberID)) {
		t.Fatalf("expected response to include rotated member %q, got %s", rotatedMemberID, rec.Body.String())
	}
}

func TestJoinExpiredInviteMapsTo410(t *testing.T) {
	t.Setenv("ONLYMACS_NODE_ID", "bridge-test-node")

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.URL.Path == "/admin/v1/swarms/join":
			http.Error(w, `{"error":{"code":"INVITE_EXPIRED","message":"invite token has expired; create a fresh invite"}}`, http.StatusGone)
		default:
			t.Fatalf("unexpected coordinator path %s?%s", r.URL.Path, r.URL.RawQuery)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		CannedChat:     true,
	})

	body, err := json.Marshal(joinLocalSwarmRequest{
		InviteToken: "invite-expired",
		MemberName:  "Kevin",
		Mode:        "both",
	})
	if err != nil {
		t.Fatalf("marshal join body: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarms/join", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusGone {
		t.Fatalf("expected status %d, got %d", http.StatusGone, rec.Code)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"INVITE_EXPIRED"`)) {
		t.Fatalf("expected invite expired error, got %s", rec.Body.String())
	}
}

func TestJobReportHandlerForwardsLocalMetadata(t *testing.T) {
	var received jobReportRequest
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/v1/job-reports" {
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
		if r.Method != http.MethodPost {
			t.Fatalf("expected POST, got %s", r.Method)
		}
		if err := json.NewDecoder(r.Body).Decode(&received); err != nil {
			t.Fatalf("decode forwarded report: %v", err)
		}
		writeJSON(w, http.StatusCreated, jobReportResponse{
			Status: "recorded",
			Report: jobReport{
				ID:          "report-000001",
				RunID:       received.RunID,
				SwarmID:     received.SwarmID,
				MemberID:    received.MemberID,
				MemberName:  received.MemberName,
				ClientBuild: received.ClientBuild,
			},
		})
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		ClientBuild: &clientBuild{
			Product:     "OnlyMacs",
			Version:     "0.1.test",
			BuildNumber: "test-build",
		},
	})
	updateRuntime(t, mux, runtimeConfig{Mode: "both", ActiveSwarmID: defaultPublicSwarmID})

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/job-reports", bytes.NewReader([]byte(`{"run_id":"run-1","report_markdown":"ok","automatic":true,"tickets":[{"step_id":"step-01","index":1,"status":"completed"}]}`)))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d: %s", http.StatusCreated, rec.Code, rec.Body.String())
	}
	if received.SwarmID != defaultPublicSwarmID {
		t.Fatalf("expected active swarm to be forwarded, got %+v", received)
	}
	if received.MemberID == "" || received.MemberName == "" {
		t.Fatalf("expected local member identity to be forwarded, got %+v", received)
	}
	if received.ClientBuild == nil || received.ClientBuild.BuildNumber != "test-build" {
		t.Fatalf("expected client build metadata to be forwarded, got %+v", received.ClientBuild)
	}
	if len(received.Tickets) != 1 || received.Tickets[0].Index != 1 || received.Tickets[0].Status != "completed" {
		t.Fatalf("expected tickets to be forwarded, got %+v", received.Tickets)
	}
}

func TestJobBoardProxyEnrichesLocalMetadata(t *testing.T) {
	t.Setenv("ONLYMACS_NODE_ID", "kevin-node")
	t.Setenv("ONLYMACS_MEMBER_NAME", "Kevin")
	t.Setenv("ONLYMACS_PROVIDER_NAME", "Kevin Studio")

	var receivedCreate map[string]any
	var receivedClaim map[string]any
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodPost && r.URL.Path == "/admin/v1/jobs":
			if err := json.NewDecoder(r.Body).Decode(&receivedCreate); err != nil {
				t.Fatalf("decode create payload: %v", err)
			}
			writeJSON(w, http.StatusCreated, map[string]any{"job": map[string]any{"id": "job-1"}})
		case r.Method == http.MethodPost && r.URL.Path == "/admin/v1/jobs/job-1/tickets/claim":
			if err := json.NewDecoder(r.Body).Decode(&receivedClaim); err != nil {
				t.Fatalf("decode claim payload: %v", err)
			}
			writeJSON(w, http.StatusOK, map[string]any{"job_id": "job-1", "tickets": []any{}})
		default:
			t.Fatalf("unexpected coordinator call %s %s", r.Method, r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{CoordinatorURL: coordinator.URL, HTTPClient: coordinator.Client()})
	updateRuntime(t, mux, runtimeConfig{Mode: "both", ActiveSwarmID: "swarm-private"})

	createReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/jobs", bytes.NewReader([]byte(`{"prompt_preview":"build site"}`)))
	createRec := httptest.NewRecorder()
	mux.ServeHTTP(createRec, createReq)
	if createRec.Code != http.StatusCreated {
		t.Fatalf("expected create status %d, got %d: %s", http.StatusCreated, createRec.Code, createRec.Body.String())
	}
	if receivedCreate["swarm_id"] != "swarm-private" || receivedCreate["requester_member_id"] != "member-kevin-node" || receivedCreate["requester_member_name"] != "Kevin" {
		t.Fatalf("expected create metadata enrichment, got %+v", receivedCreate)
	}

	claimReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/jobs/job-1/tickets/claim", bytes.NewReader([]byte(`{"capabilities":["frontend"]}`)))
	claimRec := httptest.NewRecorder()
	mux.ServeHTTP(claimRec, claimReq)
	if claimRec.Code != http.StatusOK {
		t.Fatalf("expected claim status %d, got %d: %s", http.StatusOK, claimRec.Code, claimRec.Body.String())
	}
	if receivedClaim["member_id"] != "member-kevin-node" || receivedClaim["member_name"] != "Kevin" || receivedClaim["provider_id"] != "provider-kevin-node" || receivedClaim["provider_name"] != "Kevin Studio" {
		t.Fatalf("expected claim metadata enrichment, got %+v", receivedClaim)
	}
}

func updateRuntime(t *testing.T, mux *http.ServeMux, runtime runtimeConfig) {
	t.Helper()

	body, err := json.Marshal(runtime)
	if err != nil {
		t.Fatalf("marshal runtime: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/runtime", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, rec.Code)
	}
}

func boolToInt(value bool) int {
	if value {
		return 1
	}
	return 0
}

func TestRuntimeAlwaysCoercesToBothForPublicSwarm(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms/members/upsert":
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: "swarm-public", Name: "OnlyMacs Public", Visibility: "public", MemberCount: 1},
				Member: swarmMember{ID: "member-public", Name: "Kevin", Mode: "both", SwarmID: "swarm-public"},
			})
		case "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{
				Swarms: []swarm{
					{ID: "swarm-public", Name: "OnlyMacs Public", Visibility: "public"},
					{ID: "swarm-private", Name: "Private", Visibility: "private"},
				},
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{})
		case "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
	})

	body, err := json.Marshal(runtimeConfig{
		Mode:          "use",
		ActiveSwarmID: "swarm-public",
	})
	if err != nil {
		t.Fatalf("marshal runtime: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/runtime", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, rec.Code)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"mode":"both"`)) {
		t.Fatalf("expected public swarm runtime to coerce to both, got %s", rec.Body.String())
	}
}

func TestRuntimeAlwaysCoercesToBothForPrivateSwarm(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{
				Swarms: []swarm{
					{ID: "swarm-public", Name: "OnlyMacs Public", Visibility: "public"},
					{ID: "swarm-private", Name: "Private", Visibility: "private"},
				},
			})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{})
		case "/admin/v1/providers/activity":
			writeJSON(w, http.StatusOK, coordinatorProviderActivitiesResponse{})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
	})

	body, err := json.Marshal(runtimeConfig{
		Mode:          "use",
		ActiveSwarmID: "swarm-private",
	})
	if err != nil {
		t.Fatalf("marshal runtime: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/runtime", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, rec.Code)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"mode":"both"`)) {
		t.Fatalf("expected private swarm runtime to coerce to both, got %s", rec.Body.String())
	}
}

func TestRuntimePersistsLastActiveSwarmAcrossRestart(t *testing.T) {
	statePath := filepath.Join(t.TempDir(), "runtime.json")
	mux := NewMuxWithConfig(Config{RuntimeStatePath: statePath})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-private-alpha",
	})

	restarted := NewMuxWithConfig(Config{RuntimeStatePath: statePath})
	req := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/runtime", nil)
	rec := httptest.NewRecorder()
	restarted.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	var runtime runtimeConfig
	if err := json.Unmarshal(rec.Body.Bytes(), &runtime); err != nil {
		t.Fatalf("unmarshal runtime: %v", err)
	}
	if runtime.ActiveSwarmID != "swarm-private-alpha" || runtime.Mode != "both" {
		t.Fatalf("expected runtime to restore last active swarm, got %+v", runtime)
	}
}

func TestConfigFromEnvPreservesHostedCoordinatorAndDefaultRelayWorker(t *testing.T) {
	t.Setenv("ONLYMACS_COORDINATOR_URL", "https://onlymacs.ai")
	t.Setenv("ONLYMACS_OLLAMA_URL", "http://127.0.0.1:11435")
	t.Setenv("ONLYMACS_ENABLE_CANNED_CHAT", "1")

	cfg := ConfigFromEnv(filepath.Join(t.TempDir(), "runtime.json"))
	if cfg.CoordinatorURL != "https://onlymacs.ai" {
		t.Fatalf("expected hosted coordinator env to be preserved, got %q", cfg.CoordinatorURL)
	}
	if cfg.OllamaURL != "http://127.0.0.1:11435" {
		t.Fatalf("expected Ollama URL env to be preserved, got %q", cfg.OllamaURL)
	}
	if !cfg.CannedChat {
		t.Fatalf("expected canned chat env to be preserved")
	}
	if !cfg.EnableProviderRelayWorker {
		t.Fatalf("expected provider relay worker to keep default enabled when using env config")
	}
	if cfg.RuntimeStatePath == "" {
		t.Fatalf("expected runtime state path to be preserved")
	}
}
