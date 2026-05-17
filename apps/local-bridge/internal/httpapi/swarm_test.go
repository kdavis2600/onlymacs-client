package httpapi

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestSwarmStartIdempotentStickyPauseResumeAndCancel(t *testing.T) {
	var (
		reserveCalls  int
		releaseCalls  int
		reserveInputs []reserveSessionRequest
	)

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "qwen2.5-coder:32b",
				ResolvedModel:  "qwen2.5-coder:32b",
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:              "charles-m5",
						Name:            "Charles's Mac Studio",
						Status:          "available",
						ActiveSessions:  0,
						OwnerMemberName: "Charles",
						Hardware:        &hardwareProfile{CPUBrand: "M4 Max", MemoryGB: 128},
						MatchingModels:  []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1}},
						Slots:           slots{Free: 1, Total: 1},
					},
					{
						ID:             "dana-m4",
						Name:           "Dana's MacBook Pro",
						Status:         "available",
						ActiveSessions: 0,
						MatchingModels: []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1}},
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 2, SlotsTotal: 2}},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{
					Providers:  2,
					SlotsFree:  2,
					SlotsTotal: 2,
				},
			})
		case "/admin/v1/sessions/reserve":
			var req reserveSessionRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
			reserveInputs = append(reserveInputs, req)
			reserveCalls++

			providerID := "charles-m5"
			providerName := "Charles's Mac Studio"
			if req.PreferredProviderID != "" {
				providerID = req.PreferredProviderID
				if providerID == "dana-m4" {
					providerName = "Dana's MacBook Pro"
				}
			} else if reserveCalls%2 == 0 {
				providerID = "dana-m4"
				providerName = "Dana's MacBook Pro"
			}

			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-00000" + string(rune('0'+reserveCalls)),
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:32b",
				Provider: preflightProvider{
					ID:             providerID,
					Name:           providerName,
					Status:         "available",
					ActiveSessions: 1,
					MatchingModels: []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 0, SlotsTotal: 1}},
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/sessions/release":
			releaseCalls++
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "released",
				Status:    "released",
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:        coordinator.URL,
		HTTPClient:            coordinator.Client(),
		CannedChat:            true,
		DisableSwarmExecution: true,
	})

	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	startBody := marshalJSON(t, swarmPlanRequest{
		Title:           "parser-refactor",
		Model:           "qwen2.5-coder:32b",
		Strategy:        "go_wide",
		RequestedAgents: 2,
		MaxAgents:       2,
		Scheduling:      "sticky",
		WorkspaceID:     "repo-a",
		ThreadID:        "thread-1",
		IdempotencyKey:  "idem-1",
		Prompt:          "Implement a parser.",
	})
	startReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/start", bytes.NewReader(startBody))
	startRec := httptest.NewRecorder()
	mux.ServeHTTP(startRec, startReq)
	if startRec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d: %s", http.StatusCreated, startRec.Code, startRec.Body.String())
	}

	var startResp swarmStartResponse
	if err := json.Unmarshal(startRec.Body.Bytes(), &startResp); err != nil {
		t.Fatalf("unmarshal start response: %v", err)
	}
	if startResp.Duplicate {
		t.Fatalf("expected fresh session, got duplicate")
	}
	if startResp.Session.Status != "running" {
		t.Fatalf("expected running session, got %+v", startResp.Session)
	}
	if startResp.Session.Title != "parser-refactor" {
		t.Fatalf("expected session title to be preserved, got %+v", startResp.Session)
	}
	if len(startResp.Session.Reservations) != 2 {
		t.Fatalf("expected 2 reservations, got %+v", startResp.Session.Reservations)
	}
	if startResp.Session.SavedTokensEstimate <= 0 {
		t.Fatalf("expected saved token estimate to be populated, got %+v", startResp.Session)
	}
	if startResp.Session.SelectionExplanation == "" {
		t.Fatalf("expected selection explanation to be populated, got %+v", startResp.Session)
	}
	if startResp.Session.SelectionReason == "" {
		t.Fatalf("expected selection reason to be populated, got %+v", startResp.Session)
	}
	if startResp.Session.RouteSummary == "" {
		t.Fatalf("expected route summary to be populated, got %+v", startResp.Session)
	}
	if startResp.Session.Strategy != "go_wide" {
		t.Fatalf("expected go-wide strategy to be preserved, got %+v", startResp.Session)
	}
	if len(startResp.Session.CapabilityMatrix) != 2 || startResp.Session.CapabilityMatrix[0].MemoryGB != 128 || startResp.Session.CapabilityMatrix[0].SuggestedRole != "primary_generation" {
		t.Fatalf("expected capability matrix with primary generation role, got %+v", startResp.Session.CapabilityMatrix)
	}
	if len(startResp.Session.WorkerRoles) != 2 || startResp.Session.WorkerRoles[0].Role != "primary_generation" || startResp.Session.Quorum == nil {
		t.Fatalf("expected worker roles and quorum plan, got roles=%+v quorum=%+v", startResp.Session.WorkerRoles, startResp.Session.Quorum)
	}

	secondStartReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/start", bytes.NewReader(startBody))
	secondStartRec := httptest.NewRecorder()
	mux.ServeHTTP(secondStartRec, secondStartReq)
	if secondStartRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, secondStartRec.Code, secondStartRec.Body.String())
	}
	var duplicateResp swarmStartResponse
	if err := json.Unmarshal(secondStartRec.Body.Bytes(), &duplicateResp); err != nil {
		t.Fatalf("unmarshal duplicate response: %v", err)
	}
	if !duplicateResp.Duplicate {
		t.Fatalf("expected duplicate response, got %+v", duplicateResp)
	}
	if duplicateResp.Session.ID != startResp.Session.ID {
		t.Fatalf("expected duplicate to return same session id, got %q vs %q", duplicateResp.Session.ID, startResp.Session.ID)
	}
	if reserveCalls != 2 {
		t.Fatalf("expected duplicate start to avoid new reservations, got %d reserve calls", reserveCalls)
	}

	pauseReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/sessions/pause", bytes.NewReader(marshalJSON(t, swarmSessionActionRequest{SessionID: startResp.Session.ID})))
	pauseRec := httptest.NewRecorder()
	mux.ServeHTTP(pauseRec, pauseReq)
	if pauseRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, pauseRec.Code, pauseRec.Body.String())
	}
	if releaseCalls != 2 {
		t.Fatalf("expected 2 releases on pause, got %d", releaseCalls)
	}

	resumeReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/sessions/resume", bytes.NewReader(marshalJSON(t, swarmSessionActionRequest{SessionID: startResp.Session.ID})))
	resumeRec := httptest.NewRecorder()
	mux.ServeHTTP(resumeRec, resumeReq)
	if resumeRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, resumeRec.Code, resumeRec.Body.String())
	}

	if reserveCalls != 4 {
		t.Fatalf("expected 4 total reserve calls after resume, got %d", reserveCalls)
	}
	if !bytes.Contains(resumeRec.Body.Bytes(), []byte(`"saved_tokens_estimate"`)) {
		t.Fatalf("expected saved token estimate in resume response, got %s", resumeRec.Body.String())
	}
	if len(reserveInputs) < 4 || reserveInputs[2].PreferredProviderID == "" || reserveInputs[3].PreferredProviderID == "" {
		t.Fatalf("expected resume to prefer previous providers, got %+v", reserveInputs)
	}

	cancelReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/sessions/cancel", bytes.NewReader(marshalJSON(t, swarmSessionActionRequest{SessionID: startResp.Session.ID})))
	cancelRec := httptest.NewRecorder()
	mux.ServeHTTP(cancelRec, cancelReq)
	if cancelRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, cancelRec.Code, cancelRec.Body.String())
	}
	if releaseCalls != 4 {
		t.Fatalf("expected 4 total releases after cancel, got %d", releaseCalls)
	}
}

func TestElasticSwarmSpreadsAcrossDistinctProvidersBeforeReusingOne(t *testing.T) {
	var reserveInputs []reserveSessionRequest

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms/members/upsert":
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: "swarm-public", Name: "OnlyMacs Public", Visibility: "public", MemberCount: 1},
				Member: swarmMember{ID: "member-kevin", Name: "Kevin", Mode: "both", SwarmID: "swarm-public"},
			})
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "qwen2.5-coder:14b",
				ResolvedModel:  "qwen2.5-coder:14b",
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:             "kevin-macbook",
						Name:           "Kevin's MacBook Pro",
						Status:         "available",
						ActiveSessions: 0,
						MatchingModels: []model{{ID: "qwen2.5-coder:14b", Name: "Qwen2.5 Coder 14B", SlotsFree: 1, SlotsTotal: 1}},
						Slots:          slots{Free: 1, Total: 1},
					},
					{
						ID:             "friend-mac-studio",
						Name:           "Friend's Mac Studio",
						Status:         "available",
						ActiveSessions: 0,
						MatchingModels: []model{{ID: "qwen2.5-coder:14b", Name: "Qwen2.5 Coder 14B", SlotsFree: 1, SlotsTotal: 1}},
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{{ID: "qwen2.5-coder:14b", Name: "Qwen2.5 Coder 14B", SlotsFree: 2, SlotsTotal: 2}},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{
					Providers:  2,
					SlotsFree:  2,
					SlotsTotal: 2,
				},
			})
		case "/admin/v1/sessions/reserve":
			var req reserveSessionRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
			reserveInputs = append(reserveInputs, req)

			providerID := "kevin-macbook"
			providerName := "Kevin's MacBook Pro"
			if len(req.AvoidProviderIDs) > 0 {
				providerID = "friend-mac-studio"
				providerName = "Friend's Mac Studio"
			}

			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-elastic-" + providerID,
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:14b",
				Provider: preflightProvider{
					ID:             providerID,
					Name:           providerName,
					Status:         "available",
					ActiveSessions: 1,
					MatchingModels: []model{{ID: "qwen2.5-coder:14b", Name: "Qwen2.5 Coder 14B", SlotsFree: 0, SlotsTotal: 1}},
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:        coordinator.URL,
		HTTPClient:            coordinator.Client(),
		CannedChat:            true,
		DisableSwarmExecution: true,
	})

	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: defaultPublicSwarmID,
	})

	body := marshalJSON(t, swarmPlanRequest{
		Model:           "qwen2.5-coder:14b",
		RequestedAgents: 2,
		MaxAgents:       2,
		Scheduling:      "elastic",
		Prompt:          "Review this startup pitch deck.",
	})
	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/start", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d: %s", http.StatusCreated, rec.Code, rec.Body.String())
	}

	var resp swarmStartResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("unmarshal swarm start response: %v", err)
	}
	if len(resp.Session.Reservations) != 2 {
		t.Fatalf("expected 2 reservations, got %+v", resp.Session.Reservations)
	}
	if resp.Session.Reservations[0].ProviderID == resp.Session.Reservations[1].ProviderID {
		t.Fatalf("expected elastic swarm to use distinct providers, got %+v", resp.Session.Reservations)
	}
	if len(reserveInputs) < 2 || len(reserveInputs[1].AvoidProviderIDs) == 0 || reserveInputs[1].AvoidProviderIDs[0] != "kevin-macbook" {
		t.Fatalf("expected second reservation to avoid first provider, got %+v", reserveInputs)
	}
}

func TestSwarmStartRemoteFirstExcludesLocalProvider(t *testing.T) {
	localProviderID, _ := localProviderIdentity()
	var preflightInputs []preflightRequest
	var reserveInputs []reserveSessionRequest

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms/members/upsert":
			var req upsertMemberRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode upsert request: %v", err)
			}
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public"},
				Member: swarmMember{ID: req.MemberID, Name: req.MemberName, Mode: req.Mode, SwarmID: defaultPublicSwarmID},
				Credentials: coordinatorCredentials{Requester: &coordinatorTokenResponse{
					Token:    "requester-token",
					Scope:    "requester",
					SwarmID:  defaultPublicSwarmID,
					MemberID: req.MemberID,
				}},
			})
		case "/admin/v1/preflight":
			var req preflightRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode preflight request: %v", err)
			}
			preflightInputs = append(preflightInputs, req)
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "",
				ResolvedModel:  "gemma3:27b",
				RouteScope:     "swarm",
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						Status:         "available",
						ActiveSessions: 0,
						MatchingModels: []model{{ID: "gemma3:27b", Name: "Gemma 3 27B", SlotsFree: 1, SlotsTotal: 1}},
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{{ID: "gemma3:27b", Name: "Gemma 3 27B", SlotsFree: 1, SlotsTotal: 1}},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{
					Providers:  1,
					SlotsFree:  1,
					SlotsTotal: 1,
				},
			})
		case "/admin/v1/sessions/reserve":
			var req reserveSessionRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
			reserveInputs = append(reserveInputs, req)
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-remote-first-swarm",
				Status:        "reserved",
				ResolvedModel: "gemma3:27b",
				Provider: preflightProvider{
					ID:             "charles-m5",
					Name:           "Charles's Mac Studio",
					Status:         "available",
					ActiveSessions: 1,
					MatchingModels: []model{{ID: "gemma3:27b", Name: "Gemma 3 27B", SlotsFree: 0, SlotsTotal: 1}},
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:        coordinator.URL,
		HTTPClient:            coordinator.Client(),
		CannedChat:            true,
		DisableSwarmExecution: true,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: defaultPublicSwarmID,
	})

	body := marshalJSON(t, swarmPlanRequest{
		RequestedAgents: 1,
		MaxAgents:       1,
		RouteScope:      "swarm",
		PreferRemote:    true,
		Prompt:          "Force this through another Mac first.",
	})
	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/start", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d: %s", http.StatusCreated, rec.Code, rec.Body.String())
	}

	if len(preflightInputs) != 1 || len(preflightInputs[0].ExcludeProviderIDs) != 1 || preflightInputs[0].ExcludeProviderIDs[0] != localProviderID {
		t.Fatalf("expected remote-first preflight to exclude local provider %q, got %+v", localProviderID, preflightInputs)
	}
	if len(reserveInputs) != 1 || len(reserveInputs[0].ExcludeProviderIDs) != 1 || reserveInputs[0].ExcludeProviderIDs[0] != localProviderID {
		t.Fatalf("expected remote-first reserve to exclude local provider %q, got %+v", localProviderID, reserveInputs)
	}
}

func TestSwarmStartSoftRemotePreferenceAvoidsLocalProvider(t *testing.T) {
	localProviderID, _ := localProviderIdentity()
	var preflightInputs []preflightRequest
	var reserveInputs []reserveSessionRequest

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms/members/upsert":
			var req upsertMemberRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode upsert request: %v", err)
			}
			writeJSON(w, http.StatusOK, upsertMemberResponse{
				Swarm:  swarm{ID: defaultPublicSwarmID, Name: "OnlyMacs Public", Visibility: "public"},
				Member: swarmMember{ID: req.MemberID, Name: req.MemberName, Mode: req.Mode, SwarmID: defaultPublicSwarmID},
				Credentials: coordinatorCredentials{Requester: &coordinatorTokenResponse{
					Token:    "requester-token",
					Scope:    "requester",
					SwarmID:  defaultPublicSwarmID,
					MemberID: req.MemberID,
				}},
			})
		case "/admin/v1/preflight":
			var req preflightRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode preflight request: %v", err)
			}
			preflightInputs = append(preflightInputs, req)
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "qwen2.5-coder:14b",
				ResolvedModel:  "qwen2.5-coder:14b",
				RouteScope:     "swarm",
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						Status:         "available",
						ActiveSessions: 0,
						MatchingModels: []model{{ID: "qwen2.5-coder:14b", Name: "Qwen2.5 Coder 14B", SlotsFree: 1, SlotsTotal: 1}},
						Slots:          slots{Free: 1, Total: 1},
					},
					{
						ID:             localProviderID,
						Name:           "This Mac",
						Status:         "available",
						ActiveSessions: 0,
						MatchingModels: []model{{ID: "qwen2.5-coder:14b", Name: "Qwen2.5 Coder 14B", SlotsFree: 1, SlotsTotal: 1}},
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{{ID: "qwen2.5-coder:14b", Name: "Qwen2.5 Coder 14B", SlotsFree: 2, SlotsTotal: 2}},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{
					Providers:  2,
					SlotsFree:  2,
					SlotsTotal: 2,
				},
			})
		case "/admin/v1/sessions/reserve":
			var req reserveSessionRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
			reserveInputs = append(reserveInputs, req)
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-soft-swarm-001",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:14b",
				Provider: preflightProvider{
					ID:             "charles-m5",
					Name:           "Charles's Mac Studio",
					Status:         "available",
					ActiveSessions: 1,
					MatchingModels: []model{{ID: "qwen2.5-coder:14b", Name: "Qwen2.5 Coder 14B", SlotsFree: 0, SlotsTotal: 1}},
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:        coordinator.URL,
		HTTPClient:            coordinator.Client(),
		CannedChat:            true,
		DisableSwarmExecution: true,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: defaultPublicSwarmID,
	})

	body := marshalJSON(t, swarmPlanRequest{
		RequestedAgents:  1,
		MaxAgents:        1,
		RouteScope:       "swarm",
		PreferRemoteSoft: true,
		Prompt:           "Prefer another Mac first, but fall back if needed.",
	})
	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/start", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d: %s", http.StatusCreated, rec.Code, rec.Body.String())
	}

	if len(preflightInputs) != 1 || len(preflightInputs[0].AvoidProviderIDs) != 1 || preflightInputs[0].AvoidProviderIDs[0] != localProviderID {
		t.Fatalf("expected soft remote preference preflight to avoid local provider %q, got %+v", localProviderID, preflightInputs)
	}
	if len(preflightInputs[0].ExcludeProviderIDs) != 0 {
		t.Fatalf("expected soft remote preference preflight not to exclude local provider entirely, got %+v", preflightInputs)
	}
	if len(reserveInputs) != 1 || len(reserveInputs[0].AvoidProviderIDs) != 1 || reserveInputs[0].AvoidProviderIDs[0] != localProviderID {
		t.Fatalf("expected soft remote preference reserve to avoid local provider %q, got %+v", localProviderID, reserveInputs)
	}
	if len(reserveInputs[0].ExcludeProviderIDs) != 0 {
		t.Fatalf("expected soft remote preference reserve not to exclude local provider entirely, got %+v", reserveInputs)
	}
}

func TestSwarmPlanRejectsOversizedPromptAndQueuedSessionShowsInQueue(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "qwen2.5-coder:32b",
				ResolvedModel:  "qwen2.5-coder:32b",
				Available:      false,
				AvailableModels: []model{
					{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 0, SlotsTotal: 1},
				},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{
					Providers:  1,
					SlotsFree:  0,
					SlotsTotal: 1,
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:        coordinator.URL,
		HTTPClient:            coordinator.Client(),
		CannedChat:            true,
		DisableSwarmExecution: true,
	})

	updateRuntime(t, mux, runtimeConfig{
		Mode:          "use",
		ActiveSwarmID: "swarm-alpha",
	})

	tooLarge := marshalJSON(t, swarmPlanRequest{
		Model:           "qwen2.5-coder:32b",
		RequestedAgents: 3,
		MaxAgents:       3,
		Prompt:          strings.Repeat("x", maxSwarmInputBytes+1),
	})
	tooLargeReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/plan", bytes.NewReader(tooLarge))
	tooLargeRec := httptest.NewRecorder()
	mux.ServeHTTP(tooLargeRec, tooLargeReq)
	if tooLargeRec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("expected status %d, got %d: %s", http.StatusUnprocessableEntity, tooLargeRec.Code, tooLargeRec.Body.String())
	}
	if !bytes.Contains(tooLargeRec.Body.Bytes(), []byte(`"CONTEXT_TOO_LARGE"`)) {
		t.Fatalf("expected context budget error, got %s", tooLargeRec.Body.String())
	}

	startQueued := marshalJSON(t, swarmPlanRequest{
		Model:           "qwen2.5-coder:32b",
		RequestedAgents: 1,
		MaxAgents:       1,
		WorkspaceID:     "repo-b",
		ThreadID:        "thread-2",
		Prompt:          "Queue me",
	})
	startQueuedReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/start", bytes.NewReader(startQueued))
	startQueuedRec := httptest.NewRecorder()
	mux.ServeHTTP(startQueuedRec, startQueuedReq)
	if startQueuedRec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d: %s", http.StatusCreated, startQueuedRec.Code, startQueuedRec.Body.String())
	}
	if !bytes.Contains(startQueuedRec.Body.Bytes(), []byte(`"status":"queued"`)) {
		t.Fatalf("expected queued session, got %s", startQueuedRec.Body.String())
	}

	queueReq := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/swarm/queue", nil)
	queueRec := httptest.NewRecorder()
	mux.ServeHTTP(queueRec, queueReq)
	if queueRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, queueRec.Code, queueRec.Body.String())
	}
	if !bytes.Contains(queueRec.Body.Bytes(), []byte(`"queued_session_count":1`)) {
		t.Fatalf("expected queued session count in queue response, got %s", queueRec.Body.String())
	}
	if !bytes.Contains(queueRec.Body.Bytes(), []byte(`"queue_summary":{"queued_session_count":1`)) {
		t.Fatalf("expected queue summary in queue response, got %s", queueRec.Body.String())
	}
}

func TestSwarmQueueHandlerReapsStaleQueuedSessions(t *testing.T) {
	svc := newService(Config{CannedChat: true})
	stale := swarmSessionSummary{
		ID:              "swarm-stale",
		Status:          "queued",
		RequestedModel:  "qwen2.5-coder:32b",
		ResolvedModel:   "qwen2.5-coder:32b",
		RequestedAgents: 1,
		QueueRemainder:  1,
		QueuePosition:   1,
		QueueReason:     "swarm_capacity",
		IdempotencyKey:  "idem-stale",
		CreatedAt:       time.Now().Add(-15 * time.Minute).UTC(),
		UpdatedAt:       time.Now().Add(-15 * time.Minute).UTC(),
	}
	svc.swarms.sessions[stale.ID] = stale
	svc.swarms.idempotency[stale.IdempotencyKey] = stale.ID

	req := httptest.NewRequest(http.MethodGet, "http://127.0.0.1:4318/admin/v1/swarm/queue", nil)
	rec := httptest.NewRecorder()
	svc.swarmQueueHandler(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}

	var queueResp swarmQueueResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &queueResp); err != nil {
		t.Fatalf("unmarshal queue response: %v", err)
	}
	if queueResp.QueuedSessionCount != 0 {
		t.Fatalf("expected stale queued session to be reaped from live queue, got %+v", queueResp)
	}
	if len(queueResp.Sessions) != 0 {
		t.Fatalf("expected no queued sessions after reaping, got %+v", queueResp.Sessions)
	}

	reaped, ok := svc.swarms.get(stale.ID)
	if !ok {
		t.Fatalf("expected stale session to remain visible in history")
	}
	if reaped.Status != "cancelled" || reaped.QueueReason != "stale_queue" {
		t.Fatalf("expected stale session to be cancelled with stale_queue, got %+v", reaped)
	}
	if _, ok := svc.swarms.idempotency[stale.IdempotencyKey]; ok {
		t.Fatalf("expected stale queued session idempotency key to be cleared after reaping")
	}
}

func TestSwarmStartIgnoresStaleQueuedDuplicate(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "qwen2.5-coder:32b",
				ResolvedModel:  "qwen2.5-coder:32b",
				Available:      false,
				AvailableModels: []model{
					{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 0, SlotsTotal: 1},
				},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{Providers: 1, SlotsFree: 0, SlotsTotal: 1},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	svc := newService(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		CannedChat:     true,
	})
	svc.runtime.Set(runtimeConfig{
		Mode:          "use",
		ActiveSwarmID: "swarm-alpha",
	})

	body := marshalJSON(t, swarmPlanRequest{
		Model:           "qwen2.5-coder:32b",
		RequestedAgents: 1,
		MaxAgents:       1,
		WorkspaceID:     "repo-stale",
		ThreadID:        "thread-stale",
		IdempotencyKey:  "idem-stale",
		Prompt:          "Queue me until stale.",
	})

	firstReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/start", bytes.NewReader(body))
	firstRec := httptest.NewRecorder()
	svc.swarmStartHandler(firstRec, firstReq)
	if firstRec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d: %s", http.StatusCreated, firstRec.Code, firstRec.Body.String())
	}

	var firstResp swarmStartResponse
	if err := json.Unmarshal(firstRec.Body.Bytes(), &firstResp); err != nil {
		t.Fatalf("unmarshal first response: %v", err)
	}
	if firstResp.Duplicate || firstResp.Session.Status != "queued" {
		t.Fatalf("expected initial queued session, got %+v", firstResp)
	}

	stale := firstResp.Session
	stale.UpdatedAt = time.Now().Add(-15 * time.Minute).UTC()
	svc.swarms.sessions[stale.ID] = stale

	secondReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/start", bytes.NewReader(body))
	secondRec := httptest.NewRecorder()
	svc.swarmStartHandler(secondRec, secondReq)
	if secondRec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d: %s", http.StatusCreated, secondRec.Code, secondRec.Body.String())
	}

	var secondResp swarmStartResponse
	if err := json.Unmarshal(secondRec.Body.Bytes(), &secondResp); err != nil {
		t.Fatalf("unmarshal second response: %v", err)
	}
	if secondResp.Duplicate {
		t.Fatalf("expected stale queued session not to block a fresh restart, got %+v", secondResp)
	}
	if secondResp.Session.ID == firstResp.Session.ID {
		t.Fatalf("expected a fresh session after stale queue reap, got reused id %q", secondResp.Session.ID)
	}
}

func TestSwarmPlanBestAvailableUsesCoordinatorSelectionAndExplanation(t *testing.T) {
	var requestedModels []string

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			var req preflightRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode preflight request: %v", err)
			}
			requestedModels = append(requestedModels, req.Model)
			if req.Model == "" {
				writeJSON(w, http.StatusOK, preflightResponse{
					RequestedModel:       "",
					ResolvedModel:        "llama4:maverick",
					SelectionReason:      "best_available",
					SelectionExplanation: "OnlyMacs chose llama4:maverick because it is the strongest model with an open slot right now.",
					Available:            true,
					Providers: []preflightProvider{
						{ID: "provider-1", Name: "This Mac", Status: "available", ActiveSessions: 0, MatchingModels: []model{{ID: "llama4:maverick", Name: "Llama 4 Maverick", SlotsFree: 1, SlotsTotal: 1}}, Slots: slots{Free: 1, Total: 1}},
					},
					AvailableModels: []model{
						{ID: "llama4:maverick", Name: "Llama 4 Maverick", SlotsFree: 1, SlotsTotal: 1},
						{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1},
					},
					Totals: struct {
						Providers  int `json:"providers"`
						SlotsFree  int `json:"slots_free"`
						SlotsTotal int `json:"slots_total"`
					}{Providers: 1, SlotsFree: 1, SlotsTotal: 1},
				})
				return
			}
			t.Fatalf("did not expect swarm planner to re-preflight an exact model, got %q", req.Model)
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL:        coordinator.URL,
		HTTPClient:            coordinator.Client(),
		CannedChat:            true,
		DisableSwarmExecution: true,
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/plan", bytes.NewReader(marshalJSON(t, swarmPlanRequest{
		Model:           "best-available",
		RequestedAgents: 1,
		MaxAgents:       1,
		Prompt:          "Find the best coding model.",
	})))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"resolved_model":"llama4:maverick"`)) {
		t.Fatalf("expected coordinator-selected model to be preserved, got %s", rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"selection_explanation":"OnlyMacs chose llama4:maverick because it is the strongest model with an open slot right now."`)) {
		t.Fatalf("expected selection explanation in plan response, got %s", rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"title":"Find the best coding model."`)) {
		t.Fatalf("expected derived title in plan response, got %s", rec.Body.String())
	}
	if len(requestedModels) != 1 || requestedModels[0] != "" {
		t.Fatalf("expected bridge to trust the coordinator best-available choice, got %#v", requestedModels)
	}
}

func TestSwarmStartLocalOnlyPreservesRouteScopeAndLocalProvider(t *testing.T) {
	localProviderID, _ := localProviderIdentity()
	var (
		preflightInputs []preflightRequest
		reserveInputs   []reserveSessionRequest
	)

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			var req preflightRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode preflight request: %v", err)
			}
			preflightInputs = append(preflightInputs, req)
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel:       "",
				ResolvedModel:        "qwen2.5-coder:32b",
				RouteScope:           "local_only",
				SelectionReason:      "best_available",
				SelectionExplanation: "Route scope: This Mac only. OnlyMacs chose qwen2.5-coder:32b because it is the strongest model with an open slot in that route right now.",
				Available:            true,
				Providers: []preflightProvider{
					{
						ID:             localProviderID,
						Name:           "This Mac",
						Status:         "available",
						ActiveSessions: 0,
						MatchingModels: []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1}},
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{
					{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1},
				},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{Providers: 1, SlotsFree: 1, SlotsTotal: 1},
			})
		case "/admin/v1/sessions/reserve":
			var req reserveSessionRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
			reserveInputs = append(reserveInputs, req)
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-local-001",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:32b",
				Provider: preflightProvider{
					ID:             localProviderID,
					Name:           "This Mac",
					Status:         "available",
					ActiveSessions: 1,
					MatchingModels: []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 0, SlotsTotal: 1}},
					Slots:          slots{Free: 0, Total: 1},
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
		ActiveSwarmID: "swarm-alpha",
	})

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/start", bytes.NewReader(marshalJSON(t, swarmPlanRequest{
		RouteScope:      "local_only",
		RequestedAgents: 1,
		MaxAgents:       1,
		Prompt:          "Keep this code review on This Mac only.",
	})))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d: %s", http.StatusCreated, rec.Code, rec.Body.String())
	}
	if len(preflightInputs) != 1 || preflightInputs[0].RouteScope != "local_only" || preflightInputs[0].RouteProviderID != localProviderID {
		t.Fatalf("expected local-only preflight with local provider id, got %+v", preflightInputs)
	}
	if len(reserveInputs) != 1 || reserveInputs[0].RouteScope != "local_only" || reserveInputs[0].RouteProviderID != localProviderID {
		t.Fatalf("expected local-only reserve with local provider id, got %+v", reserveInputs)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"route_scope":"local_only"`)) {
		t.Fatalf("expected route scope in start response, got %s", rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`Route scope: This Mac only.`)) {
		t.Fatalf("expected local-only route summary or explanation in response, got %s", rec.Body.String())
	}
}

func TestSwarmStartExecutesLocalReservationAndCompletes(t *testing.T) {
	localProviderID, _ := localProviderIdentity()
	var releaseCalls int

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "qwen2.5-coder:32b",
				ResolvedModel:  "qwen2.5-coder:32b",
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:             localProviderID,
						Name:           "This Mac",
						Status:         "available",
						ActiveSessions: 0,
						MatchingModels: []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1}},
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1}},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{Providers: 1, SlotsFree: 1, SlotsTotal: 1},
			})
		case "/admin/v1/sessions/reserve":
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-local-exec-1",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:32b",
				Provider: preflightProvider{
					ID:             localProviderID,
					Name:           "This Mac",
					Status:         "available",
					ActiveSessions: 1,
					MatchingModels: []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 0, SlotsTotal: 1}},
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/sessions/release":
			releaseCalls++
			writeJSON(w, http.StatusOK, releaseSessionResponse{SessionID: "released", Status: "released"})
		case "/admin/v1/providers":
			writeJSON(w, http.StatusOK, coordinatorProvidersResponse{
				Providers: []provider{
					{
						ID:      localProviderID,
						Name:    "This Mac",
						SwarmID: "swarm-alpha",
						Status:  "available",
						Modes:   []string{"share", "both"},
						Slots:   slots{Free: 1, Total: 1},
						Models:  []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1}},
					},
				},
			})
		case "/admin/v1/providers/register":
			writeJSON(w, http.StatusCreated, registerProviderResponse{
				Status: "registered",
				Provider: provider{
					ID:      localProviderID,
					Name:    "This Mac",
					SwarmID: "swarm-alpha",
					Status:  "available",
					Modes:   []string{"share", "both"},
					Slots:   slots{Free: 1, Total: 1},
					Models:  []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1}},
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	backend := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/models" {
			writeJSON(w, http.StatusOK, map[string]any{"data": []map[string]any{{"id": "qwen2.5-coder:32b"}}})
			return
		}
		if r.URL.Path != "/v1/chat/completions" {
			t.Fatalf("unexpected inference path %s", r.URL.Path)
		}
		var req chatCompletionsRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			t.Fatalf("decode inference request: %v", err)
		}
		if req.Stream {
			t.Fatalf("expected swarm execution to use non-streaming chat completions")
		}
		if len(req.Messages) != 1 || req.Messages[0].Content != "Build the flash card app." {
			t.Fatalf("expected preserved swarm prompt, got %+v", req.Messages)
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"id":     "chatcmpl-local",
			"object": "chat.completion",
			"choices": []map[string]any{
				{
					"index": 0,
					"message": map[string]any{
						"role":    "assistant",
						"content": "print('cebu flash cards')",
					},
					"finish_reason": "stop",
				},
			},
		})
	}))
	defer backend.Close()

	service := newService(Config{
		CoordinatorURL:      coordinator.URL,
		HTTPClient:          coordinator.Client(),
		RelayHTTPClient:     coordinator.Client(),
		OllamaURL:           backend.URL,
		InferenceHTTPClient: backend.Client(),
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	startReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/start", bytes.NewReader(marshalJSON(t, swarmPlanRequest{
		Model:           "qwen2.5-coder:32b",
		RequestedAgents: 1,
		MaxAgents:       1,
		WorkspaceID:     "repo-local",
		ThreadID:        "thread-local",
		IdempotencyKey:  "local-exec",
		Prompt:          "Build the flash card app.",
	})))
	startRec := httptest.NewRecorder()
	service.swarmStartHandler(startRec, startReq)
	if startRec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d: %s", http.StatusCreated, startRec.Code, startRec.Body.String())
	}

	var startResp swarmStartResponse
	if err := json.Unmarshal(startRec.Body.Bytes(), &startResp); err != nil {
		t.Fatalf("decode start response: %v", err)
	}

	session := waitForSwarmSessionStatus(t, service, startResp.Session.ID, "completed", 2*time.Second)
	if session.Checkpoint == nil || !strings.Contains(session.Checkpoint.OutputPreview, "print('cebu flash cards')") {
		t.Fatalf("expected completed swarm output preview, got %+v", session.Checkpoint)
	}
	if releaseCalls != 1 {
		t.Fatalf("expected a release after local execution, got %d", releaseCalls)
	}
	if session.AdmittedAgents != 1 {
		t.Fatalf("expected completed session to preserve admitted worker count, got %+v", session)
	}
	if _, ok := service.swarms.idempotency["local-exec"]; ok {
		t.Fatalf("expected completed swarm idempotency key to be cleared")
	}
	usage := service.requestMetrics.snapshotValue()
	if usage.TokensSavedEstimate <= 0 {
		t.Fatalf("expected successful swarm to increase tokens saved, got %+v", usage)
	}
	if usage.DownloadedTokensEstimate <= 0 {
		t.Fatalf("expected successful swarm to increase downloaded tokens, got %+v", usage)
	}
}

func TestSwarmStartExecutesRemoteReservationAndCompletes(t *testing.T) {
	var (
		releaseCalls int
		relayBodies  []chatCompletionsRequest
	)

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "qwen2.5-coder:32b",
				ResolvedModel:  "qwen2.5-coder:32b",
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						Status:         "available",
						ActiveSessions: 0,
						MatchingModels: []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1}},
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1}},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{Providers: 1, SlotsFree: 1, SlotsTotal: 1},
			})
		case "/admin/v1/sessions/reserve":
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-remote-exec-1",
				Status:        "reserved",
				ResolvedModel: "qwen2.5-coder:32b",
				Provider: preflightProvider{
					ID:             "charles-m5",
					Name:           "Charles's Mac Studio",
					Status:         "available",
					ActiveSessions: 1,
					MatchingModels: []model{{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 0, SlotsTotal: 1}},
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/relay/execute":
			var relayReq relayExecuteRequest
			if err := json.NewDecoder(r.Body).Decode(&relayReq); err != nil {
				t.Fatalf("decode relay execute request: %v", err)
			}
			var forwarded chatCompletionsRequest
			if err := json.Unmarshal(relayReq.Request, &forwarded); err != nil {
				t.Fatalf("decode forwarded relay request: %v", err)
			}
			relayBodies = append(relayBodies, forwarded)
			writeJSON(w, http.StatusOK, relayExecuteResponse{
				JobID:       "job-remote-1",
				StatusCode:  http.StatusOK,
				ContentType: "application/json",
				BodyBase64:  base64.StdEncoding.EncodeToString([]byte(`{"id":"chatcmpl-remote","object":"chat.completion","choices":[{"index":0,"message":{"role":"assistant","content":"remote flash card result"},"finish_reason":"stop"}]}`)),
			})
		case "/admin/v1/sessions/release":
			releaseCalls++
			writeJSON(w, http.StatusOK, releaseSessionResponse{SessionID: "released", Status: "released"})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL:  coordinator.URL,
		HTTPClient:      coordinator.Client(),
		RelayHTTPClient: coordinator.Client(),
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	startReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/start", bytes.NewReader(marshalJSON(t, swarmPlanRequest{
		Model:           "qwen2.5-coder:32b",
		RequestedAgents: 1,
		MaxAgents:       1,
		WorkspaceID:     "repo-remote",
		ThreadID:        "thread-remote",
		IdempotencyKey:  "remote-exec",
		Prompt:          "Build the remote flash card app.",
	})))
	startRec := httptest.NewRecorder()
	service.swarmStartHandler(startRec, startReq)
	if startRec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d: %s", http.StatusCreated, startRec.Code, startRec.Body.String())
	}

	var startResp swarmStartResponse
	if err := json.Unmarshal(startRec.Body.Bytes(), &startResp); err != nil {
		t.Fatalf("decode start response: %v", err)
	}

	session := waitForSwarmSessionStatus(t, service, startResp.Session.ID, "completed", 2*time.Second)
	if session.Checkpoint == nil || !strings.Contains(session.Checkpoint.OutputPreview, "remote flash card result") {
		t.Fatalf("expected remote relay output preview, got %+v", session.Checkpoint)
	}
	if len(relayBodies) != 1 || len(relayBodies[0].Messages) != 1 || relayBodies[0].Messages[0].Content != "Build the remote flash card app." {
		t.Fatalf("expected remote relay to receive preserved prompt, got %+v", relayBodies)
	}
	if releaseCalls != 1 {
		t.Fatalf("expected a release after remote execution, got %d", releaseCalls)
	}
	usage := service.requestMetrics.snapshotValue()
	if usage.TokensSavedEstimate <= 0 {
		t.Fatalf("expected successful remote swarm to increase tokens saved, got %+v", usage)
	}
	if usage.DownloadedTokensEstimate <= 0 {
		t.Fatalf("expected successful remote swarm to increase downloaded tokens, got %+v", usage)
	}
}

func TestSwarmPlanPremiumContentionGetsDedicatedQueueReason(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel:       "",
				ResolvedModel:        "gemma-4-31b",
				SelectionReason:      "scarce_premium_fallback",
				SelectionExplanation: "OnlyMacs kept the last scarce premium slot available for stronger contributors and moved this swarm onto the best strong fallback.",
				Available:            true,
				Providers:            []preflightProvider{},
				AvailableModels: []model{
					{ID: "llama4:maverick", Name: "Llama 4 Maverick", SlotsFree: 0, SlotsTotal: 1},
					{ID: "gemma-4-31b", Name: "Gemma 4 31B", SlotsFree: 0, SlotsTotal: 1},
				},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{
					Providers:  1,
					SlotsFree:  0,
					SlotsTotal: 1,
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
		ActiveSwarmID: "swarm-alpha",
	})

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/plan", bytes.NewReader(marshalJSON(t, swarmPlanRequest{
		RequestedAgents: 2,
		MaxAgents:       2,
		Prompt:          "Try the best available premium coding path.",
	})))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"selection_reason":"scarce_premium_fallback"`)) {
		t.Fatalf("expected scarce premium selection reason, got %s", rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"queue_reason":"premium_contention"`)) {
		t.Fatalf("expected premium contention queue reason, got %s", rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"eta_seconds":90`)) {
		t.Fatalf("expected premium contention ETA in plan response, got %s", rec.Body.String())
	}
}

func TestQueueSummaryClassifiesPressureAndETA(t *testing.T) {
	store := newSwarmStore()
	now := time.Now().UTC()
	store.sessions["swarm-000001"] = swarmSessionSummary{
		ID:          "swarm-000001",
		Status:      "queued",
		QueueReason: "premium_contention",
		ETASeconds:  90,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	store.sessions["swarm-000002"] = swarmSessionSummary{
		ID:          "swarm-000002",
		Status:      "queued",
		QueueReason: "swarm_capacity",
		ETASeconds:  45,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	store.sessions["swarm-000003"] = swarmSessionSummary{
		ID:          "swarm-000003",
		Status:      "queued",
		QueueReason: "requested_width",
		ETASeconds:  135,
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	summary := store.queueSummary()
	if summary.QueuedSessionCount != 3 {
		t.Fatalf("expected 3 queued sessions, got %#v", summary)
	}
	if summary.PremiumContentionCount != 1 || summary.CapacityWaitCount != 1 || summary.WidthLimitedCount != 1 {
		t.Fatalf("expected queue summary buckets to be classified, got %#v", summary)
	}
	if summary.NextETASeconds != 45 || summary.MaxETASeconds != 135 {
		t.Fatalf("expected eta range 45-135, got %#v", summary)
	}
	if summary.PrimaryReason != "premium_contention" {
		t.Fatalf("expected premium contention to be primary reason, got %#v", summary)
	}
	if summary.PrimaryDetail == "" || summary.SuggestedAction == "" {
		t.Fatalf("expected queue summary explanation, got %#v", summary)
	}
}

func TestQueueSummaryMarksStaleQueuedSessions(t *testing.T) {
	store := newSwarmStore()
	now := time.Now().UTC()
	store.sessions["swarm-000010"] = swarmSessionSummary{
		ID:          "swarm-000010",
		Status:      "queued",
		QueueReason: "swarm_capacity",
		ETASeconds:  45,
		CreatedAt:   now.Add(-20 * time.Minute),
		UpdatedAt:   now.Add(-20 * time.Minute),
	}

	summary := store.queueSummary()
	if summary.StaleQueuedCount != 1 {
		t.Fatalf("expected stale queued count to be tracked, got %#v", summary)
	}
	if !strings.Contains(summary.PrimaryDetail, "waiting long enough") {
		t.Fatalf("expected stale queue detail in summary, got %#v", summary)
	}
	if !strings.Contains(summary.SuggestedAction, "Pause/resume or cancel/restart stale swarms") {
		t.Fatalf("expected stale queue action in summary, got %#v", summary)
	}
}

func TestQueueSummaryClassifiesRequesterBudget(t *testing.T) {
	store := newSwarmStore()
	now := time.Now().UTC()
	store.sessions["swarm-000020"] = swarmSessionSummary{
		ID:          "swarm-000020",
		Status:      "queued",
		QueueReason: "requester_budget",
		ETASeconds:  60,
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	summary := store.queueSummary()
	if summary.RequesterBudgetCount != 1 {
		t.Fatalf("expected requester budget count, got %#v", summary)
	}
	if summary.PrimaryReason != "requester_budget" {
		t.Fatalf("expected requester budget to be primary reason, got %#v", summary)
	}
	if !strings.Contains(summary.PrimaryDetail, "already has enough queued swarms") {
		t.Fatalf("expected requester budget detail, got %#v", summary)
	}
}

func TestQueueSummaryClassifiesPremiumBudget(t *testing.T) {
	store := newSwarmStore()
	now := time.Now().UTC()
	store.sessions["swarm-000021"] = swarmSessionSummary{
		ID:             "swarm-000021",
		Status:         "queued",
		RequestedModel: "llama4:maverick",
		ResolvedModel:  "llama4:maverick",
		QueueReason:    "premium_budget",
		ETASeconds:     75,
		CreatedAt:      now,
		UpdatedAt:      now,
	}

	summary := store.queueSummary()
	if summary.PremiumBudgetCount != 1 {
		t.Fatalf("expected premium budget count, got %#v", summary)
	}
	if summary.PrimaryReason != "premium_budget" {
		t.Fatalf("expected premium budget to be primary reason, got %#v", summary)
	}
	if !strings.Contains(summary.PrimaryDetail, "scarce premium work in flight") {
		t.Fatalf("expected premium budget detail, got %#v", summary)
	}
}

func TestQueueSummaryClassifiesPremiumCooldown(t *testing.T) {
	store := newSwarmStore()
	now := time.Now().UTC()
	store.sessions["swarm-000022"] = swarmSessionSummary{
		ID:             "swarm-000022",
		Status:         "queued",
		RequestedModel: "llama4:maverick",
		ResolvedModel:  "llama4:maverick",
		QueueReason:    "premium_cooldown",
		ETASeconds:     45,
		CreatedAt:      now,
		UpdatedAt:      now,
	}

	summary := store.queueSummary()
	if summary.PremiumCooldownCount != 1 {
		t.Fatalf("expected premium cooldown count, got %#v", summary)
	}
	if summary.PrimaryReason != "premium_cooldown" {
		t.Fatalf("expected premium cooldown to be primary reason, got %#v", summary)
	}
	if !strings.Contains(summary.PrimaryDetail, "short cooldown") {
		t.Fatalf("expected premium cooldown detail, got %#v", summary)
	}
}

func TestSensitiveSwarmRoutePlanEmitsWarning(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel:       "",
				ResolvedModel:        "qwen2.5-coder:32b",
				RouteScope:           "swarm",
				Available:            true,
				SelectionExplanation: "OnlyMacs chose qwen2.5-coder:32b because it is the strongest model with an open slot right now.",
				Providers: []preflightProvider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						Status:         "available",
						ActiveSessions: 0,
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{
					{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1},
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
		ActiveSwarmID: "swarm-alpha",
	})

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/plan", bytes.NewReader(marshalJSON(t, swarmPlanRequest{
		RequestedAgents: 1,
		MaxAgents:       1,
		RouteScope:      "swarm",
		Prompt:          "Review this private auth flow with api key rotation and secret handling.",
	})))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"warnings":["This request looks sensitive`)) {
		t.Fatalf("expected sensitive-route warning, got %s", rec.Body.String())
	}
}

func TestSensitiveTrustedOnlyRouteSkipsSwarmWarning(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "",
				ResolvedModel:  "qwen2.5-coder:32b",
				RouteScope:     "trusted_only",
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:             "kevin-macbook",
						Name:           "Kevin's MacBook Pro",
						Status:         "available",
						ActiveSessions: 0,
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{
					{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1},
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
		ActiveSwarmID: "swarm-alpha",
	})

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/plan", bytes.NewReader(marshalJSON(t, swarmPlanRequest{
		RequestedAgents: 1,
		MaxAgents:       1,
		RouteScope:      "trusted_only",
		Prompt:          "Review this private auth flow with api key rotation and secret handling.",
	})))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if bytes.Contains(rec.Body.Bytes(), []byte(`"warnings":["This request looks sensitive`)) {
		t.Fatalf("did not expect swarm-warning on trusted-only route, got %s", rec.Body.String())
	}
}

func TestGoWideCapabilityMatrixRanks12864And32GBMembers(t *testing.T) {
	providers := []preflightProvider{
		{
			ID:                     "studio-128",
			Name:                   "Charles Studio",
			OwnerMemberName:        "Charles",
			Status:                 "available",
			ActiveSessions:         0,
			RecentUploadedTokensPS: 41.5,
			Hardware:               &hardwareProfile{CPUBrand: "M4 Max", MemoryGB: 128},
			MatchingModels:         []model{{ID: "qwen3.6:35b-a3b-q8_0", SlotsFree: 1, SlotsTotal: 1}},
			Slots:                  slots{Free: 1, Total: 1},
		},
		{
			ID:                     "macbook-64",
			Name:                   "Kevin MacBook",
			OwnerMemberName:        "Kevin",
			Status:                 "available",
			ActiveSessions:         1,
			RecentUploadedTokensPS: 18.25,
			Hardware:               &hardwareProfile{CPUBrand: "M2 Max", MemoryGB: 64},
			MatchingModels:         []model{{ID: "qwen2.5-coder:32b", SlotsFree: 1, SlotsTotal: 1}},
			Slots:                  slots{Free: 1, Total: 2},
		},
		{
			ID:              "mini-32",
			Name:            "Mini 32",
			OwnerMemberName: "Mini",
			Status:          "available",
			Hardware:        &hardwareProfile{CPUBrand: "M4", MemoryGB: 32},
			MatchingModels:  []model{{ID: "llama3.1:8b", SlotsFree: 1, SlotsTotal: 1}},
			Slots:           slots{Free: 1, Total: 1},
		},
		{
			ID:              "air-16",
			Name:            "Air 16",
			OwnerMemberName: "Air",
			Status:          "available",
			Hardware:        &hardwareProfile{CPUBrand: "M2", MemoryGB: 16},
			MatchingModels:  []model{{ID: "llama3.2:3b", SlotsFree: 1, SlotsTotal: 1}},
			Slots:           slots{Free: 1, Total: 1},
		},
	}

	matrix := buildSwarmCapabilityMatrix(providers, swarmPlanRequest{Strategy: "go_wide", RouteScope: "swarm"})
	if len(matrix) != 4 {
		t.Fatalf("expected 4 capability rows, got %+v", matrix)
	}
	if matrix[0].CapabilityTier != "tier_128gb_power" || matrix[0].SuggestedRole != "primary_generation" || matrix[0].RecentTokensPerSecond != 41.5 {
		t.Fatalf("expected 128GB primary generation row with token rate, got %+v", matrix[0])
	}
	if matrix[1].CapabilityTier != "tier_64gb_power" || matrix[1].SuggestedRole != "validation_review" || matrix[1].CurrentLoad == 0 {
		t.Fatalf("expected 64GB validation row with current load, got %+v", matrix[1])
	}
	if matrix[2].CapabilityTier != "tier_32gb_light" || matrix[2].SuggestedRole != "conflict_checker" {
		t.Fatalf("expected 32GB member to get bounded checker work, got %+v", matrix[2])
	}
	if matrix[3].SuggestedRole != "idle_underpowered" || matrix[3].AssignmentPolicy != "idle_for_this_job" || matrix[3].IdleReason == "" {
		t.Fatalf("expected underpowered member to be left idle with reason, got %+v", matrix[3])
	}
	if matrix[0].FileAccessApprovalState != "prompt_only" || matrix[0].RouteTrust != "public_member" {
		t.Fatalf("expected prompt-only public trust metadata, got %+v", matrix[0])
	}
	warnings := goWideCapabilityWarnings("go_wide", matrix)
	if len(warnings) != 1 || !strings.Contains(warnings[0], "left idle") {
		t.Fatalf("expected underpowered go-wide warning, got %#v", warnings)
	}
}

func TestSwarmResumeWarnsWhenPremiumModelChanges(t *testing.T) {
	var preflightCalls int
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			preflightCalls++
			resolved := "llama4:maverick"
			if preflightCalls > 1 {
				resolved = "gemma-4-31b"
			}
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "llama4:maverick",
				ResolvedModel:  resolved,
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						Status:         "available",
						ActiveSessions: 0,
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{
					{ID: resolved, Name: resolved, SlotsFree: 1, SlotsTotal: 1},
				},
			})
		case "/admin/v1/sessions/reserve":
			writeJSON(w, http.StatusCreated, reserveSessionResponse{
				SessionID:     "sess-resume-1",
				Status:        "reserved",
				ResolvedModel: "gemma-4-31b",
				Provider: preflightProvider{
					ID:             "charles-m5",
					Name:           "Charles's Mac Studio",
					Status:         "available",
					ActiveSessions: 1,
					Slots:          slots{Free: 0, Total: 1},
				},
			})
		case "/admin/v1/sessions/release":
			writeJSON(w, http.StatusOK, releaseSessionResponse{SessionID: "released", Status: "released"})
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

	startReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/start", bytes.NewReader(marshalJSON(t, swarmPlanRequest{
		Model:           "llama4:maverick",
		RequestedAgents: 1,
		MaxAgents:       1,
		WorkspaceID:     "repo-a",
		ThreadID:        "thread-1",
		IdempotencyKey:  "premium-resume",
		Prompt:          "Do a code review on this risky migration.",
	})))
	startRec := httptest.NewRecorder()
	mux.ServeHTTP(startRec, startReq)
	if startRec.Code != http.StatusCreated {
		t.Fatalf("expected status %d, got %d: %s", http.StatusCreated, startRec.Code, startRec.Body.String())
	}

	var startResp swarmStartResponse
	if err := json.Unmarshal(startRec.Body.Bytes(), &startResp); err != nil {
		t.Fatalf("decode start response: %v", err)
	}

	pauseReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/sessions/pause", bytes.NewReader(marshalJSON(t, swarmSessionActionRequest{SessionID: startResp.Session.ID})))
	pauseRec := httptest.NewRecorder()
	mux.ServeHTTP(pauseRec, pauseReq)
	if pauseRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, pauseRec.Code, pauseRec.Body.String())
	}

	resumeReq := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/sessions/resume", bytes.NewReader(marshalJSON(t, swarmSessionActionRequest{SessionID: startResp.Session.ID})))
	resumeRec := httptest.NewRecorder()
	mux.ServeHTTP(resumeRec, resumeReq)
	if resumeRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, resumeRec.Code, resumeRec.Body.String())
	}
	if !bytes.Contains(resumeRec.Body.Bytes(), []byte(`Resume could not keep llama4:maverick.`)) {
		t.Fatalf("expected resume continuity warning, got %s", resumeRec.Body.String())
	}
}

func TestSwarmPlanEnforcesRequesterQueueBudget(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "",
				ResolvedModel:  "qwen2.5-coder:32b",
				RouteScope:     "swarm",
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						Status:         "available",
						ActiveSessions: 0,
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{
					{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 1, SlotsTotal: 1},
				},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{
					Providers:  1,
					SlotsFree:  1,
					SlotsTotal: 1,
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		CannedChat:     true,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})
	now := time.Now().UTC()
	service.swarms.sessions["swarm-queued-1"] = swarmSessionSummary{
		ID:          "swarm-queued-1",
		Status:      "queued",
		WorkspaceID: "repo-a",
		ThreadID:    "thread-1",
		QueueReason: "swarm_capacity",
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	service.swarms.sessions["swarm-queued-2"] = swarmSessionSummary{
		ID:          "swarm-queued-2",
		Status:      "queued",
		WorkspaceID: "repo-a",
		ThreadID:    "thread-1",
		QueueReason: "swarm_capacity",
		CreatedAt:   now,
		UpdatedAt:   now,
	}

	plan, status, errPayload := service.computeSwarmPlan(httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/plan", nil), swarmPlanRequest{
		RequestedAgents: 1,
		MaxAgents:       1,
		WorkspaceID:     "repo-a",
		ThreadID:        "thread-1",
		Prompt:          "Do a code review on this patch.",
	})
	if errPayload != nil {
		t.Fatalf("expected no error payload, got status %d payload %#v", status, errPayload)
	}
	if plan.QueueReason != "requester_budget" {
		t.Fatalf("expected requester_budget queue reason, got %#v", plan)
	}
	if plan.AdmittedAgents != 0 || plan.QueueRemainder != 1 {
		t.Fatalf("expected requester budget to fully queue this request, got %#v", plan)
	}
	if len(plan.Warnings) == 0 || !strings.Contains(plan.Warnings[0], "already has 2 queued swarms for this thread") {
		t.Fatalf("expected requester budget warning, got %#v", plan.Warnings)
	}
}

func TestSwarmPlanClampsAgainstRequesterSwarmCap(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel:              "qwen2.5-coder:32b",
				ResolvedModel:               "qwen2.5-coder:32b",
				RouteScope:                  "swarm",
				Available:                   true,
				RequesterActiveReservations: 3,
				RequesterReservationCap:     4,
				Providers: []preflightProvider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						Status:         "available",
						ActiveSessions: 0,
						Slots:          slots{Free: 2, Total: 2},
					},
				},
				AvailableModels: []model{
					{ID: "qwen2.5-coder:32b", Name: "Qwen2.5 Coder 32B", SlotsFree: 2, SlotsTotal: 2},
				},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{
					Providers:  1,
					SlotsFree:  2,
					SlotsTotal: 2,
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		CannedChat:     true,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})

	plan, status, errPayload := service.computeSwarmPlan(httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/plan", nil), swarmPlanRequest{
		Model:           "qwen2.5-coder:32b",
		RequestedAgents: 2,
		MaxAgents:       2,
		Prompt:          "Review this concurrency patch.",
	})
	if errPayload != nil {
		t.Fatalf("expected no error payload, got status %d payload %#v", status, errPayload)
	}
	if plan.QueueReason != "member_cap" {
		t.Fatalf("expected member_cap queue reason, got %#v", plan)
	}
	if plan.AdmittedAgents != 1 || plan.QueueRemainder != 1 {
		t.Fatalf("expected requester swarm cap to admit 1 and queue 1, got %#v", plan)
	}
	if len(plan.Warnings) == 0 || !strings.Contains(plan.Warnings[0], "admitted 1 of 2 requested agents") {
		t.Fatalf("expected admitted-width warning, got %#v", plan.Warnings)
	}
}

func TestSwarmPlanEnforcesPremiumQueueBudget(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "llama4:maverick",
				ResolvedModel:  "llama4:maverick",
				RouteScope:     "swarm",
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						Status:         "available",
						ActiveSessions: 0,
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{
					{ID: "llama4:maverick", Name: "Llama 4 Maverick", SlotsFree: 1, SlotsTotal: 1},
				},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{
					Providers:  1,
					SlotsFree:  1,
					SlotsTotal: 1,
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		CannedChat:     true,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})
	now := time.Now().UTC()
	service.swarms.sessions["swarm-premium-1"] = swarmSessionSummary{
		ID:             "swarm-premium-1",
		Status:         "running",
		RequestedModel: "llama4:maverick",
		ResolvedModel:  "llama4:maverick",
		WorkspaceID:    "repo-a",
		ThreadID:       "thread-1",
		CreatedAt:      now,
		UpdatedAt:      now,
	}

	plan, status, errPayload := service.computeSwarmPlan(httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/plan", nil), swarmPlanRequest{
		Model:           "llama4:maverick",
		RequestedAgents: 1,
		MaxAgents:       1,
		WorkspaceID:     "repo-a",
		ThreadID:        "thread-1",
		Prompt:          "Summarize these files for me.",
	})
	if errPayload != nil {
		t.Fatalf("expected no error payload, got status %d payload %#v", status, errPayload)
	}
	if plan.QueueReason != "premium_budget" {
		t.Fatalf("expected premium_budget queue reason, got %#v", plan)
	}
	if plan.AdmittedAgents != 0 || plan.QueueRemainder != 1 {
		t.Fatalf("expected premium budget to fully queue this request, got %#v", plan)
	}
	if len(plan.Warnings) == 0 || !strings.Contains(plan.Warnings[0], "already has 1 scarce premium swarm") {
		t.Fatalf("expected premium budget warning, got %#v", plan.Warnings)
	}
}

func TestSwarmPlanEnforcesPremiumCooldownAfterPause(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "llama4:maverick",
				ResolvedModel:  "llama4:maverick",
				RouteScope:     "swarm",
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						Status:         "available",
						ActiveSessions: 0,
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{
					{ID: "llama4:maverick", Name: "Llama 4 Maverick", SlotsFree: 1, SlotsTotal: 1},
				},
				Totals: struct {
					Providers  int `json:"providers"`
					SlotsFree  int `json:"slots_free"`
					SlotsTotal int `json:"slots_total"`
				}{
					Providers:  1,
					SlotsFree:  1,
					SlotsTotal: 1,
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	service := newService(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		CannedChat:     true,
	})
	service.runtime.Set(runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-alpha",
	})
	now := time.Now().UTC()
	service.swarms.sessions["swarm-premium-paused"] = swarmSessionSummary{
		ID:             "swarm-premium-paused",
		Status:         "paused",
		RequestedModel: "llama4:maverick",
		ResolvedModel:  "llama4:maverick",
		WorkspaceID:    "repo-a",
		ThreadID:       "thread-1",
		QueueReason:    "manual_pause",
		CreatedAt:      now.Add(-2 * time.Minute),
		UpdatedAt:      now,
	}

	plan, status, errPayload := service.computeSwarmPlan(httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/plan", nil), swarmPlanRequest{
		Model:           "llama4:maverick",
		RequestedAgents: 1,
		MaxAgents:       1,
		WorkspaceID:     "repo-a",
		ThreadID:        "thread-1",
		Prompt:          "Summarize these files for me.",
	})
	if errPayload != nil {
		t.Fatalf("expected no error payload, got status %d payload %#v", status, errPayload)
	}
	if plan.QueueReason != "premium_cooldown" {
		t.Fatalf("expected premium_cooldown queue reason, got %#v", plan)
	}
	if plan.AdmittedAgents != 0 || plan.QueueRemainder != 1 {
		t.Fatalf("expected premium cooldown to fully queue this request, got %#v", plan)
	}
	if plan.ETASeconds <= 0 || plan.ETASeconds > int(premiumCooldownAfterRelease.Seconds()) {
		t.Fatalf("expected cooldown ETA inside lease window, got %#v", plan)
	}
	if len(plan.Warnings) == 0 || !strings.Contains(plan.Warnings[0], "just released a scarce premium swarm") {
		t.Fatalf("expected premium cooldown warning, got %#v", plan.Warnings)
	}
}

func TestPremiumMisusePlanEmitsWarningForLightweightPremiumAsk(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "llama4:maverick",
				ResolvedModel:  "llama4:maverick",
				RouteScope:     "swarm",
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						Status:         "available",
						ActiveSessions: 0,
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{
					{ID: "llama4:maverick", Name: "Llama 4 Maverick", SlotsFree: 1, SlotsTotal: 1},
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
		ActiveSwarmID: "swarm-alpha",
	})

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/plan", bytes.NewReader(marshalJSON(t, swarmPlanRequest{
		Model:           "llama4:maverick",
		RequestedAgents: 1,
		MaxAgents:       1,
		RouteScope:      "swarm",
		Prompt:          "Summarize these files for me.",
	})))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`This request looks lightweight for a scarce premium or beast-capacity slot.`)) {
		t.Fatalf("expected premium-misuse warning, got %s", rec.Body.String())
	}
}

func TestPremiumMisusePlanSkipsWarningForRealCodeReview(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/preflight":
			writeJSON(w, http.StatusOK, preflightResponse{
				RequestedModel: "llama4:maverick",
				ResolvedModel:  "llama4:maverick",
				RouteScope:     "swarm",
				Available:      true,
				Providers: []preflightProvider{
					{
						ID:             "charles-m5",
						Name:           "Charles's Mac Studio",
						Status:         "available",
						ActiveSessions: 0,
						Slots:          slots{Free: 1, Total: 1},
					},
				},
				AvailableModels: []model{
					{ID: "llama4:maverick", Name: "Llama 4 Maverick", SlotsFree: 1, SlotsTotal: 1},
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
		ActiveSwarmID: "swarm-alpha",
	})

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/swarm/plan", bytes.NewReader(marshalJSON(t, swarmPlanRequest{
		Model:           "llama4:maverick",
		RequestedAgents: 1,
		MaxAgents:       1,
		RouteScope:      "swarm",
		Prompt:          "Do a code review on this risky migration.",
	})))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if bytes.Contains(rec.Body.Bytes(), []byte(`This request looks lightweight for a scarce premium or beast-capacity slot.`)) {
		t.Fatalf("did not expect premium-misuse warning for real review work, got %s", rec.Body.String())
	}
}

func TestBuildSwarmChatRequestCarriesOnlyMacsArtifact(t *testing.T) {
	artifact := &onlyMacsArtifactPayload{
		ExportMode: "trusted_review_full",
		Manifest: onlyMacsArtifactManifest{
			ID:               "artifact-swarm",
			TotalExportBytes: 2048,
		},
	}

	req, err := buildSwarmChatRequest(swarmSessionSummary{
		ID:               "swarm-artifact-001",
		Status:           "running",
		ResolvedModel:    "qwen2.5-coder:32b",
		OnlyMacsArtifact: artifact,
		Messages: []chatMessage{{
			Role:    "user",
			Content: "Review these docs.",
		}},
	})
	if err != nil {
		t.Fatalf("buildSwarmChatRequest: %v", err)
	}
	if req.OnlyMacsArtifact == nil {
		t.Fatal("expected artifact to be preserved for swarm execution")
	}
	if req.OnlyMacsArtifact.Manifest.ID != "artifact-swarm" {
		t.Fatalf("expected artifact manifest to survive, got %+v", req.OnlyMacsArtifact.Manifest)
	}
}

func marshalJSON(t *testing.T, value any) []byte {
	t.Helper()
	body, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("marshal json: %v", err)
	}
	return body
}

func waitForSwarmSessionStatus(t *testing.T, service *service, sessionID string, want string, timeout time.Duration) swarmSessionSummary {
	t.Helper()

	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		session, ok := service.swarms.get(sessionID)
		if ok && session.Status == want {
			return session
		}
		time.Sleep(10 * time.Millisecond)
	}

	session, ok := service.swarms.get(sessionID)
	if !ok {
		t.Fatalf("expected session %q to exist while waiting for status %q", sessionID, want)
	}
	t.Fatalf("timed out waiting for session %q to reach status %q, last state %+v", sessionID, want, session)
	return swarmSessionSummary{}
}
