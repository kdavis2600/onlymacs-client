package httpapi

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestCannedChatStream(t *testing.T) {
	var reserveCalls int
	var releaseCalls int
	localProviderID, _ := localProviderIdentity()

	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/sessions/reserve":
			reserveCalls++
			var req reserveSessionRequest
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				t.Fatalf("decode reserve request: %v", err)
			}
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
		case "/admin/v1/sessions/release":
			releaseCalls++
			writeJSON(w, http.StatusOK, releaseSessionResponse{
				SessionID: "sess-000001",
				Status:    "released",
			})
		default:
			t.Fatalf("unexpected path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/v1/chat/completions", strings.NewReader(`{"model":"qwen2.5-coder:32b","stream":true}`))
	rec := httptest.NewRecorder()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
		CannedChat:     true,
	})

	runtimeBody := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/runtime", strings.NewReader(`{"mode":"both","active_swarm_id":"swarm-alpha"}`))
	runtimeRec := httptest.NewRecorder()
	mux.ServeHTTP(runtimeRec, runtimeBody)
	if runtimeRec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, runtimeRec.Code)
	}

	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d", http.StatusOK, rec.Code)
	}

	body := rec.Body.String()
	if !strings.Contains(body, "data: [DONE]") {
		t.Fatalf("expected DONE marker, got %q", body)
	}
	if !strings.Contains(body, "This Mac") {
		t.Fatalf("expected provider name in stream, got %q", body)
	}
	if reserveCalls != 1 {
		t.Fatalf("expected 1 reserve call, got %d", reserveCalls)
	}
	if releaseCalls != 1 {
		t.Fatalf("expected 1 release call, got %d", releaseCalls)
	}
}
