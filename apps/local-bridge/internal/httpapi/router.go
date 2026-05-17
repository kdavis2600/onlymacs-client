package httpapi

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

func NewMux() *http.ServeMux {
	return NewMuxWithConfig(ConfigFromEnv(""))
}

func ConfigFromEnv(runtimeStatePath string) Config {
	cfg := defaultConfig()
	cfg.RuntimeStatePath = runtimeStatePath
	if coordinatorURL := strings.TrimSpace(os.Getenv("ONLYMACS_COORDINATOR_URL")); coordinatorURL != "" {
		cfg.CoordinatorURL = coordinatorURL
	}
	if ollamaURL := strings.TrimSpace(os.Getenv("ONLYMACS_OLLAMA_URL")); ollamaURL != "" {
		cfg.OllamaURL = ollamaURL
	}
	cfg.CannedChat = os.Getenv("ONLYMACS_ENABLE_CANNED_CHAT") == "1"
	if disableRelayWorker := strings.TrimSpace(os.Getenv("ONLYMACS_DISABLE_PROVIDER_RELAY_WORKER")); disableRelayWorker == "1" {
		cfg.EnableProviderRelayWorker = false
	}
	if disableSwarmExecution := strings.TrimSpace(os.Getenv("ONLYMACS_DISABLE_SWARM_EXECUTION")); disableSwarmExecution == "1" {
		cfg.DisableSwarmExecution = true
	}
	cfg.ClientBuild = clientBuildFromEnv()
	return cfg
}

func NewMuxWithConfig(cfg Config) *http.ServeMux {
	service := newService(cfg)
	inner := http.NewServeMux()
	inner.HandleFunc("/health", service.healthHandler)
	inner.HandleFunc("/admin/v1/runtime", service.runtimeHandler)
	inner.HandleFunc("/admin/v1/identity", service.identityHandler)
	inner.HandleFunc("/admin/v1/coordinator/credentials/rotate", service.rotateCoordinatorCredentialHandler)
	inner.HandleFunc("/admin/v1/swarms", service.swarmsHandler)
	inner.HandleFunc("/admin/v1/swarms/create", service.createSwarmHandler)
	inner.HandleFunc("/admin/v1/swarms/invite", service.inviteHandler)
	inner.HandleFunc("/admin/v1/swarms/join", service.joinSwarmHandler)
	inner.HandleFunc("/admin/v1/share/local", service.localShareStatusHandler)
	inner.HandleFunc("/admin/v1/share/publish", service.publishLocalShareHandler)
	inner.HandleFunc("/admin/v1/share/unpublish", service.unpublishLocalShareHandler)
	inner.HandleFunc("/admin/v1/relay/activity", service.relayActivityHandler)
	inner.HandleFunc("/admin/v1/job-reports", service.jobReportsHandler)
	inner.HandleFunc("/admin/v1/jobs", service.jobBoardProxyHandler)
	inner.HandleFunc("/admin/v1/jobs/", service.jobBoardProxyHandler)
	inner.HandleFunc("/admin/v1/status", service.statusHandler)
	inner.HandleFunc("/admin/v1/models", service.modelsHandler)
	inner.HandleFunc("/admin/v1/preflight", service.preflightHandler)
	inner.HandleFunc("/admin/v1/request-policy/classify", service.requestPolicyClassifyHandler)
	inner.HandleFunc("/admin/v1/swarm/plan", service.swarmPlanHandler)
	inner.HandleFunc("/admin/v1/swarm/start", service.swarmStartHandler)
	inner.HandleFunc("/admin/v1/swarm/sessions", service.swarmSessionsHandler)
	inner.HandleFunc("/admin/v1/swarm/queue", service.swarmQueueHandler)
	inner.HandleFunc("/admin/v1/swarm/sessions/pause", service.swarmPauseHandler)
	inner.HandleFunc("/admin/v1/swarm/sessions/resume", service.swarmResumeHandler)
	inner.HandleFunc("/admin/v1/swarm/sessions/cancel", service.swarmCancelHandler)
	inner.HandleFunc("/v1/models", service.openAIModelsHandler)
	inner.HandleFunc("/v1/chat/completions", service.chatCompletionsHandler)

	mux := http.NewServeMux()
	mux.Handle("/", localBridgeSecurityMiddleware(inner))
	return mux
}

type service struct {
	cfg            Config
	coordinator    *coordinatorClient
	inference      *inferenceClient
	runtime        *runtimeStore
	swarms         *swarmStore
	swarmRuns      *swarmExecutionStore
	requestMetrics *requestMetricsStore
	shareMetrics   *shareMetricsStore
	statusCache    *statusCoordinatorCache
}

const (
	statusCoordinatorCacheMaxAge   = 2 * time.Minute
	statusCoordinatorFreshMaxAge   = 30 * time.Second
	statusCoordinatorPollTimeout   = 1200 * time.Millisecond
	localShareActivityFreshMaxAge  = 60 * time.Second
	localShareReconcileFreshMaxAge = 20 * time.Second
)

type statusCoordinatorCache struct {
	mu                 sync.Mutex
	swarms             coordinatorSwarmsResponse
	swarmsAt           time.Time
	providers          map[string]cachedCoordinatorProviders
	providersAt        map[string]time.Time
	memberSummaries    map[string]cachedMemberSummary
	memberSummariesAt  map[string]time.Time
	activities         map[string]cachedProviderActivities
	activitiesAt       map[string]time.Time
	lastShareReconcile time.Time
}

type cachedCoordinatorProviders struct {
	response coordinatorProvidersResponse
}

type cachedMemberSummary struct {
	response memberSummaryResponse
}

type cachedProviderActivities struct {
	response coordinatorProviderActivitiesResponse
}

func newStatusCoordinatorCache() *statusCoordinatorCache {
	return &statusCoordinatorCache{
		providers:         make(map[string]cachedCoordinatorProviders),
		providersAt:       make(map[string]time.Time),
		memberSummaries:   make(map[string]cachedMemberSummary),
		memberSummariesAt: make(map[string]time.Time),
		activities:        make(map[string]cachedProviderActivities),
		activitiesAt:      make(map[string]time.Time),
	}
}

func (c *statusCoordinatorCache) storeSwarms(resp coordinatorSwarmsResponse, now time.Time) {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.swarms = resp
	c.swarmsAt = now
}

func (c *statusCoordinatorCache) recentSwarms(now time.Time) (coordinatorSwarmsResponse, bool) {
	return c.recentSwarmsWithMaxAge(now, statusCoordinatorCacheMaxAge)
}

func (c *statusCoordinatorCache) freshSwarms(now time.Time) (coordinatorSwarmsResponse, bool) {
	return c.recentSwarmsWithMaxAge(now, statusCoordinatorFreshMaxAge)
}

func (c *statusCoordinatorCache) recentSwarmsWithMaxAge(now time.Time, maxAge time.Duration) (coordinatorSwarmsResponse, bool) {
	if c == nil {
		return coordinatorSwarmsResponse{}, false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if maxAge <= 0 {
		maxAge = statusCoordinatorCacheMaxAge
	}
	if c.swarmsAt.IsZero() || now.Sub(c.swarmsAt) > maxAge {
		return coordinatorSwarmsResponse{}, false
	}
	return c.swarms, true
}

func (c *statusCoordinatorCache) storeProviders(swarmID string, resp coordinatorProvidersResponse, now time.Time) {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	key := strings.TrimSpace(swarmID)
	c.providers[key] = cachedCoordinatorProviders{response: resp}
	c.providersAt[key] = now
}

func (c *statusCoordinatorCache) recentProviders(swarmID string, now time.Time) (coordinatorProvidersResponse, bool) {
	return c.recentProvidersWithMaxAge(swarmID, now, statusCoordinatorCacheMaxAge)
}

func (c *statusCoordinatorCache) freshProviders(swarmID string, now time.Time) (coordinatorProvidersResponse, bool) {
	return c.recentProvidersWithMaxAge(swarmID, now, statusCoordinatorFreshMaxAge)
}

func (c *statusCoordinatorCache) recentProvidersWithMaxAge(swarmID string, now time.Time, maxAge time.Duration) (coordinatorProvidersResponse, bool) {
	if c == nil {
		return coordinatorProvidersResponse{}, false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if maxAge <= 0 {
		maxAge = statusCoordinatorCacheMaxAge
	}
	key := strings.TrimSpace(swarmID)
	updatedAt := c.providersAt[key]
	if updatedAt.IsZero() || now.Sub(updatedAt) > maxAge {
		return coordinatorProvidersResponse{}, false
	}
	return c.providers[key].response, true
}

func memberSummaryCacheKey(swarmID string, memberID string) string {
	return strings.TrimSpace(swarmID) + "\x00" + strings.TrimSpace(memberID)
}

func providerActivityCacheKey(providerID string, ownerMemberID string, swarmID string) string {
	return strings.TrimSpace(providerID) + "\x00" + strings.TrimSpace(ownerMemberID) + "\x00" + strings.TrimSpace(swarmID)
}

func (c *statusCoordinatorCache) storeMemberSummary(swarmID string, memberID string, resp memberSummaryResponse, now time.Time) {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	key := memberSummaryCacheKey(swarmID, memberID)
	c.memberSummaries[key] = cachedMemberSummary{response: resp}
	c.memberSummariesAt[key] = now
}

func (c *statusCoordinatorCache) freshMemberSummary(swarmID string, memberID string, now time.Time) (memberSummaryResponse, bool) {
	if c == nil {
		return memberSummaryResponse{}, false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	key := memberSummaryCacheKey(swarmID, memberID)
	updatedAt := c.memberSummariesAt[key]
	if updatedAt.IsZero() || now.Sub(updatedAt) > statusCoordinatorFreshMaxAge {
		return memberSummaryResponse{}, false
	}
	return c.memberSummaries[key].response, true
}

func (c *statusCoordinatorCache) storeProviderActivities(providerID string, ownerMemberID string, swarmID string, resp coordinatorProviderActivitiesResponse, now time.Time) {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	key := providerActivityCacheKey(providerID, ownerMemberID, swarmID)
	c.activities[key] = cachedProviderActivities{response: resp}
	c.activitiesAt[key] = now
}

func (c *statusCoordinatorCache) freshProviderActivities(providerID string, ownerMemberID string, swarmID string, now time.Time) (coordinatorProviderActivitiesResponse, bool) {
	if c == nil {
		return coordinatorProviderActivitiesResponse{}, false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	key := providerActivityCacheKey(providerID, ownerMemberID, swarmID)
	updatedAt := c.activitiesAt[key]
	if updatedAt.IsZero() || now.Sub(updatedAt) > localShareActivityFreshMaxAge {
		return coordinatorProviderActivitiesResponse{}, false
	}
	return c.activities[key].response, true
}

func (c *statusCoordinatorCache) markShareReconciled(now time.Time) {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.lastShareReconcile = now
}

func (c *statusCoordinatorCache) shareReconcileFresh(now time.Time) bool {
	if c == nil {
		return false
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	return !c.lastShareReconcile.IsZero() && now.Sub(c.lastShareReconcile) <= localShareReconcileFreshMaxAge
}

func (c *statusCoordinatorCache) clearCoordinatorState() {
	if c == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	c.swarms = coordinatorSwarmsResponse{}
	c.swarmsAt = time.Time{}
	c.providers = make(map[string]cachedCoordinatorProviders)
	c.providersAt = make(map[string]time.Time)
	c.memberSummaries = make(map[string]cachedMemberSummary)
	c.memberSummariesAt = make(map[string]time.Time)
}

type bridgeSwarmView struct {
	ID              string              `json:"id"`
	Name            string              `json:"name"`
	Slug            string              `json:"slug,omitempty"`
	PublicPath      string              `json:"public_path,omitempty"`
	Visibility      string              `json:"visibility,omitempty"`
	Discoverability string              `json:"discoverability,omitempty"`
	JoinPolicy      *swarmJoinPolicy    `json:"join_policy,omitempty"`
	ContextPolicy   *swarmContextPolicy `json:"context_policy,omitempty"`
	MemberCount     int                 `json:"member_count"`
	SlotsFree       int                 `json:"slots_free"`
	SlotsTotal      int                 `json:"slots_total"`
}

type bridgeSwarmCapacitySummaryView struct {
	SlotsFree          int `json:"slots_free"`
	SlotsTotal         int `json:"slots_total"`
	ModelCount         int `json:"model_count"`
	ActiveSessionCount int `json:"active_session_count"`
}

func newService(cfg Config) *service {
	cfg.ClientBuild = normalizeClientBuild(cfg.ClientBuild)
	if cfg.CoordinatorURL == "" {
		defaults := defaultConfig()
		cfg.CoordinatorURL = defaults.CoordinatorURL
		if cfg.HTTPClient == nil {
			cfg.HTTPClient = defaults.HTTPClient
		}
	}

	service := &service{
		cfg:            cfg,
		coordinator:    newCoordinatorClient(cfg),
		inference:      newInferenceClient(cfg),
		runtime:        newRuntimeStore(cfg.RuntimeStatePath),
		swarms:         newSwarmStore(),
		swarmRuns:      newSwarmExecutionStore(),
		requestMetrics: newRequestMetricsStore(),
		shareMetrics:   newShareMetricsStore(),
		statusCache:    newStatusCoordinatorCache(),
	}
	if cfg.EnableProviderRelayWorker {
		service.startProviderRelayWorker()
	}
	return service
}

func (s *service) healthHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"service": "onlymacs-local-bridge",
		"status":  "ok",
		"version": "v1",
	})
}

func (s *service) relayActivityHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "relay activity requires GET",
			},
		})
		return
	}
	sessionID := strings.TrimSpace(r.URL.Query().Get("session_id"))
	if sessionID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"error": map[string]any{
				"code":    "INVALID_SESSION",
				"message": "session_id is required",
			},
		})
		return
	}
	resp, err := s.coordinator.providerActivitiesForSession("", "", s.runtime.Get().ActiveSwarmID, sessionID, 1)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]any{
				"code":    "COORDINATOR_UNAVAILABLE",
				"message": err.Error(),
			},
		})
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

const maxBridgeJobReportRequestBytes = 256 * 1024

func (s *service) jobReportsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "job reports require POST",
			},
		})
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxBridgeJobReportRequestBytes)
	var req jobReportRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"error": map[string]any{
				"code":    "INVALID_JSON",
				"message": err.Error(),
			},
		})
		return
	}

	runtime := s.runtime.Get()
	if strings.TrimSpace(req.SwarmID) == "" {
		req.SwarmID = runtime.ActiveSwarmID
	}
	memberID, memberName := localMemberIdentity()
	if strings.TrimSpace(req.MemberID) == "" {
		req.MemberID = memberID
	}
	if strings.TrimSpace(req.MemberName) == "" {
		req.MemberName = memberName
	}
	if strings.TrimSpace(req.Source) == "" {
		req.Source = "onlymacs-local-bridge"
	}
	if req.ClientBuild == nil {
		req.ClientBuild = s.cfg.ClientBuild
	}

	resp, err := s.coordinator.submitJobReport(r.Context(), req)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]any{
				"code":    "COORDINATOR_UNAVAILABLE",
				"message": err.Error(),
			},
		})
		return
	}
	writeJSON(w, http.StatusCreated, resp)
}

const maxBridgeJobBoardRequestBytes = 512 * 1024

func (s *service) jobBoardProxyHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet, http.MethodPost:
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "job board proxy supports GET and POST",
			},
		})
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxBridgeJobBoardRequestBytes)
	var body []byte
	if r.Body != nil {
		data, err := io.ReadAll(r.Body)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{
				"error": map[string]any{
					"code":    "INVALID_BODY",
					"message": err.Error(),
				},
			})
			return
		}
		body = data
	}
	if r.Method == http.MethodPost {
		body = s.enrichJobBoardProxyBody(r.URL.Path, body)
	}
	status, respBody, _, err := s.coordinator.proxyJSON(r.Context(), r.Method, r.URL.RequestURI(), body)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]any{
				"code":    "COORDINATOR_UNAVAILABLE",
				"message": err.Error(),
			},
		})
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_, _ = w.Write(respBody) // #nosec G705 -- this proxy only forwards scoped coordinator job-board JSON responses.
}

func (s *service) enrichJobBoardProxyBody(path string, body []byte) []byte {
	if len(body) == 0 || !json.Valid(body) {
		return body
	}
	var payload map[string]any
	if err := json.Unmarshal(body, &payload); err != nil {
		return body
	}
	runtime := s.runtime.Get()
	memberID, memberName := localMemberIdentity()
	if strings.TrimSpace(path) == "/admin/v1/jobs" {
		if stringValue(payload["swarm_id"]) == "" {
			payload["swarm_id"] = runtime.ActiveSwarmID
		}
		if stringValue(payload["requester_member_id"]) == "" {
			payload["requester_member_id"] = memberID
		}
		if stringValue(payload["requester_member_name"]) == "" {
			payload["requester_member_name"] = memberName
		}
	}
	if strings.HasSuffix(path, "/tickets/claim") {
		providerID, providerName := localProviderIdentity()
		if stringValue(payload["member_id"]) == "" {
			payload["member_id"] = memberID
		}
		if stringValue(payload["member_name"]) == "" {
			payload["member_name"] = memberName
		}
		if stringValue(payload["provider_id"]) == "" {
			payload["provider_id"] = providerID
		}
		if stringValue(payload["provider_name"]) == "" {
			payload["provider_name"] = providerName
		}
	}
	updated, err := json.Marshal(payload)
	if err != nil {
		return body
	}
	return updated
}

func stringValue(value any) string {
	if s, ok := value.(string); ok {
		return strings.TrimSpace(s)
	}
	return ""
}

func (s *service) runtimeHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, s.runtime.Get())
	case http.MethodPost:
		var req runtimeConfig
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeJSON(w, http.StatusBadRequest, map[string]any{
				"error": map[string]any{
					"code":    "INVALID_JSON",
					"message": err.Error(),
				},
			})
			return
		}
		req.Mode = strings.TrimSpace(req.Mode)
		if req.Mode != "use" && req.Mode != "share" && req.Mode != "both" {
			writeJSON(w, http.StatusBadRequest, map[string]any{
				"error": map[string]any{
					"code":    "INVALID_MODE",
					"message": "mode must be one of use, share, or both",
				},
			})
			return
		}
		req.ActiveSwarmID = strings.TrimSpace(req.ActiveSwarmID)
		req.Mode = "both"
		runtime := s.runtime.Set(req)
		writeJSON(w, http.StatusOK, runtime)
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "runtime endpoint supports GET and POST",
			},
		})
	}
}

func (s *service) rotateCoordinatorCredentialHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "coordinator credential rotation requires POST",
			},
		})
		return
	}

	var req struct {
		Scope string `json:"scope"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && err != io.EOF {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"error": map[string]any{
				"code":    "INVALID_JSON",
				"message": err.Error(),
			},
		})
		return
	}
	scope := strings.TrimSpace(req.Scope)
	if scope == "" {
		scope = "requester"
	}

	var (
		credential coordinatorTokenResponse
		err        error
	)
	switch scope {
	case "requester":
		runtime := s.runtime.Get()
		memberID, _ := localMemberIdentity()
		credential, err = s.coordinator.rotateRequesterCredential(r.Context(), runtime.ActiveSwarmID, memberID)
	case "provider":
		providerID, _ := localProviderIdentity()
		credential, err = s.coordinator.rotateProviderCredential(r.Context(), providerID)
	default:
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"error": map[string]any{
				"code":    "INVALID_SCOPE",
				"message": "scope must be requester or provider",
			},
		})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]any{
				"code":    "COORDINATOR_UNAVAILABLE",
				"message": err.Error(),
			},
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":      "rotated",
		"scope":       credential.Scope,
		"swarm_id":    credential.SwarmID,
		"member_id":   credential.MemberID,
		"provider_id": credential.ProviderID,
		"expires_at":  credential.ExpiresAt,
	})
}

func (s *service) swarmsHandler(w http.ResponseWriter, r *http.Request) {
	swarmsCtx, cancel := context.WithTimeout(r.Context(), statusCoordinatorPollTimeout)
	defer cancel()
	runtime := s.runtime.Get()
	swarmsResp, err := s.swarmsForRuntimeWithContext(swarmsCtx, runtime)
	if err != nil {
		now := time.Now().UTC()
		if cached, ok := s.statusCache.recentSwarms(now); ok {
			writeJSON(w, http.StatusOK, map[string]any{
				"swarms": bridgeSwarmsForUI(cached.Swarms),
				"stale":  true,
			})
			return
		}
		if isTransientCoordinatorStateError(err) {
			if swarms := s.fallbackSwarmsForRuntime(r.Context(), runtime); len(swarms) > 0 {
				writeJSON(w, http.StatusOK, map[string]any{
					"swarms": swarms,
					"stale":  true,
				})
				return
			}
		}
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]any{
				"code":    "COORDINATOR_UNAVAILABLE",
				"message": err.Error(),
			},
		})
		return
	}
	s.statusCache.storeSwarms(swarmsResp, time.Now().UTC())

	writeJSON(w, http.StatusOK, map[string]any{
		"swarms": bridgeSwarmsForUI(swarmsResp.Swarms),
	})
}

func (s *service) fallbackSwarmsForRuntime(ctx context.Context, runtime runtimeConfig) []bridgeSwarmView {
	if strings.TrimSpace(runtime.ActiveSwarmID) == "" {
		return nil
	}
	shareCtx, cancel := context.WithTimeout(ctx, 700*time.Millisecond)
	defer cancel()
	shareStatus := s.localShareSnapshotFast(shareCtx)
	providers := normalizeProviderCapacityStatuses(mergeLocalShareProvider(nil, shareStatus, runtime))
	slotsFree, slotsTotal := aggregateProviderSlots(providers)
	activeSwarmName := defaultValue(strings.TrimSpace(shareStatus.ActiveSwarmName), defaultSwarmName(runtime.ActiveSwarmID))
	return bridgeSwarmsForStatus(nil, runtime, activeSwarmName, slotsFree, slotsTotal, len(buildSwarmMembers(providers, nil)))
}

func (s *service) statusHandler(w http.ResponseWriter, r *http.Request) {
	s.swarms.reapStaleQueuedSessions(time.Now().UTC())
	runtime := s.runtime.Get()
	reconcileCtx, reconcileCancel := context.WithTimeout(r.Context(), 700*time.Millisecond)
	if err := s.reconcileSharePublication(reconcileCtx); err == nil {
		s.statusCache.markShareReconciled(time.Now().UTC())
	}
	reconcileCancel()
	swarmsResp, swarmsErr, providersResp, providersErr, memberSummary := s.statusCoordinatorState(r.Context(), runtime)
	shareCtx, shareCancel := context.WithTimeout(r.Context(), 700*time.Millisecond)
	defer shareCancel()
	shareStatus := s.localShareSnapshotFast(shareCtx)
	queueSummary := s.swarms.queueSummary()
	usage := buildUsageSummary(s.requestMetrics.snapshotValue(), shareStatus, memberSummary)

	if swarmsErr != nil || providersErr != nil {
		errMessage := "coordinator state unavailable"
		if swarmsErr != nil {
			errMessage = swarmsErr.Error()
		} else if providersErr != nil {
			errMessage = providersErr.Error()
		}
		providers := providersResp.Providers
		if providersErr != nil {
			providers = []provider{}
		}
		providers = normalizeProviderCapacityStatuses(mergeLocalShareProvider(providers, shareStatus, runtime))
		models := aggregateModels(providers)
		slotsFree, slotsTotal := aggregateProviderSlots(providers)
		activeSwarmName := statusActiveSwarmName(swarmsResp.Swarms, runtime, shareStatus)
		shareStatus.ActiveSwarmName = activeSwarmName
		swarms := bridgeSwarmsForStatus(swarmsResp.Swarms, runtime, activeSwarmName, slotsFree, slotsTotal, len(buildSwarmMembers(providers, memberSummary)))
		bridgeStatus := "degraded"
		if len(providers) > 0 && (providersErr == nil || isTransientCoordinatorStateError(providersErr)) {
			bridgeStatus = "ready"
		}
		bridge := map[string]any{
			"status":            bridgeStatus,
			"coordinator_url":   s.cfg.CoordinatorURL,
			"active_swarm_name": activeSwarmName,
		}
		if bridgeStatus != "ready" {
			bridge["error"] = errMessage
		}

		writeJSON(w, http.StatusOK, map[string]any{
			"bridge":   bridge,
			"runtime":  runtime,
			"identity": currentLocalIdentityResponse(),
			"modes":    []string{"use", "share", "both"},
			"swarms":   swarms,
			"sharing":  shareStatus,
			"swarm": map[string]any{
				"active_session_count":  s.swarms.activeSessionCount(),
				"queued_session_count":  s.swarms.queuedSessionCount(),
				"queue_summary":         queueSummary,
				"recent_sessions":       s.swarms.recent(5),
				"slots_free":            slotsFree,
				"slots_total":           slotsTotal,
				"model_count":           len(models),
				"provider_active_count": aggregateActiveSessions(providers),
			},
			"usage":     usage,
			"providers": providers,
			"members":   buildSwarmMembers(providers, memberSummary),
			"models":    models,
		})
		return
	}

	providers := normalizeProviderCapacityStatuses(mergeLocalShareProvider(providersResp.Providers, shareStatus, runtime))
	models := aggregateModels(providers)
	slotsFree, slotsTotal := aggregateProviderSlots(providers)
	s.enrichLocalShareSnapshotFromCoordinator(&shareStatus, providers, swarmsResp.Swarms)
	usage = buildUsageSummary(s.requestMetrics.snapshotValue(), shareStatus, memberSummary)
	members := buildSwarmMembers(providers, memberSummary)
	writeJSON(w, http.StatusOK, map[string]any{
		"bridge": map[string]any{
			"status":            "ready",
			"coordinator_url":   s.cfg.CoordinatorURL,
			"active_swarm_name": swarmName(swarmsResp.Swarms, runtime.ActiveSwarmID),
		},
		"runtime":  runtime,
		"identity": currentLocalIdentityResponse(),
		"modes":    []string{"use", "share", "both"},
		"swarms":   bridgeSwarmsForUI(swarmsResp.Swarms),
		"sharing":  shareStatus,
		"swarm": map[string]any{
			"active_session_count":  s.swarms.activeSessionCount(),
			"queued_session_count":  s.swarms.queuedSessionCount(),
			"queue_summary":         queueSummary,
			"recent_sessions":       s.swarms.recent(5),
			"slots_free":            slotsFree,
			"slots_total":           slotsTotal,
			"model_count":           len(models),
			"provider_active_count": aggregateActiveSessions(providers),
		},
		"usage":     usage,
		"providers": providers,
		"members":   members,
		"models":    models,
	})
}

func (s *service) modelsHandler(w http.ResponseWriter, _ *http.Request) {
	runtime := s.runtime.Get()
	providersResp, err := s.providersForRuntime(runtime)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]any{
				"code":    "COORDINATOR_UNAVAILABLE",
				"message": err.Error(),
			},
		})
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"models":          aggregateModels(providersResp.Providers),
		"active_swarm_id": runtime.ActiveSwarmID,
		"active_mode":     runtime.Mode,
		"source":          "coordinator",
	})
}

type openAIModelsResponse struct {
	Object string        `json:"object"`
	Data   []openAIModel `json:"data"`
}

type openAIModel struct {
	ID      string `json:"id"`
	Object  string `json:"object"`
	Created int64  `json:"created"`
	OwnedBy string `json:"owned_by"`
}

func (s *service) openAIModelsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "models endpoint requires GET",
			},
		})
		return
	}

	runtime := s.runtime.Get()
	providersResp, err := s.providersForRuntime(runtime)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]any{
				"code":    "COORDINATOR_UNAVAILABLE",
				"message": err.Error(),
			},
		})
		return
	}

	writeJSON(w, http.StatusOK, openAIModelsFromAggregate(aggregateModels(providersResp.Providers)))
}

func openAIModelsFromAggregate(models []model) openAIModelsResponse {
	resp := openAIModelsResponse{
		Object: "list",
		Data:   make([]openAIModel, 0, len(models)+1),
	}
	seen := make(map[string]struct{}, len(models)+1)
	for _, model := range models {
		id := strings.TrimSpace(model.ID)
		if id == "" {
			continue
		}
		seen[id] = struct{}{}
		resp.Data = append(resp.Data, openAIModel{
			ID:      id,
			Object:  "model",
			Created: 0,
			OwnedBy: "onlymacs",
		})
	}
	if len(resp.Data) > 0 {
		if _, exists := seen["best-available"]; !exists {
			resp.Data = append(resp.Data, openAIModel{
				ID:      "best-available",
				Object:  "model",
				Created: 0,
				OwnedBy: "onlymacs",
			})
		}
	}
	return resp
}

func bridgeSwarmsForUI(swarms []swarm) []bridgeSwarmView {
	views := make([]bridgeSwarmView, 0, len(swarms))
	for _, candidate := range swarms {
		views = append(views, bridgeSwarmView{
			ID:              candidate.ID,
			Name:            candidate.Name,
			Slug:            candidate.Slug,
			PublicPath:      candidate.PublicPath,
			Visibility:      candidate.Visibility,
			Discoverability: candidate.Discoverability,
			JoinPolicy:      candidate.JoinPolicy,
			ContextPolicy:   normalizedBridgeSwarmContextPolicy(candidate.ContextPolicy, candidate.Visibility),
			MemberCount:     candidate.MemberCount,
			SlotsFree:       candidate.SlotsFree,
			SlotsTotal:      candidate.SlotsTotal,
		})
	}
	return views
}

func bridgeSwarmsForStatus(swarms []swarm, runtime runtimeConfig, activeSwarmName string, slotsFree int, slotsTotal int, memberCount int) []bridgeSwarmView {
	views := bridgeSwarmsForUI(swarms)
	activeSwarmID := strings.TrimSpace(runtime.ActiveSwarmID)
	if activeSwarmID == "" {
		return views
	}
	for idx := range views {
		if views[idx].ID != activeSwarmID {
			continue
		}
		if views[idx].Name == "" {
			views[idx].Name = activeSwarmName
		}
		if views[idx].MemberCount == 0 && memberCount > 0 {
			views[idx].MemberCount = memberCount
		}
		if views[idx].SlotsTotal == 0 && slotsTotal > 0 {
			views[idx].SlotsFree = slotsFree
			views[idx].SlotsTotal = slotsTotal
		}
		return views
	}
	if activeSwarmName == "" {
		activeSwarmName = defaultSwarmName(activeSwarmID)
	}
	if activeSwarmName == "" {
		activeSwarmName = activeSwarmID
	}
	visibility := "private"
	discoverability := "unlisted"
	joinPolicy := &swarmJoinPolicy{Version: 1, Mode: "invite_link"}
	if activeSwarmID == defaultPublicSwarmID {
		visibility = "public"
		discoverability = "listed"
		joinPolicy = &swarmJoinPolicy{Version: 1, Mode: "open"}
	}
	return append(views, bridgeSwarmView{
		ID:              activeSwarmID,
		Name:            activeSwarmName,
		Visibility:      visibility,
		Discoverability: discoverability,
		JoinPolicy:      joinPolicy,
		ContextPolicy:   normalizedBridgeSwarmContextPolicy(nil, visibility),
		MemberCount:     memberCount,
		SlotsFree:       slotsFree,
		SlotsTotal:      slotsTotal,
	})
}

func mergeLocalShareProvider(providers []provider, shareStatus localShareStatus, runtime runtimeConfig) []provider {
	localProvider, ok := localShareProviderForStatus(shareStatus, runtime)
	if !ok {
		return providers
	}
	for idx := range providers {
		if providers[idx].ID != localProvider.ID {
			continue
		}
		return providers
	}
	merged := make([]provider, 0, len(providers)+1)
	merged = append(merged, providers...)
	merged = append(merged, localProvider)
	return merged
}

func normalizeProviderCapacityStatuses(providers []provider) []provider {
	if len(providers) == 0 {
		return providers
	}
	normalized := make([]provider, len(providers))
	copy(normalized, providers)
	for idx := range normalized {
		normalizeProviderCapacityStatus(&normalized[idx])
	}
	return normalized
}

func normalizeProviderCapacityStatus(candidate *provider) {
	if candidate == nil || candidate.ActiveSessions <= 0 {
		return
	}
	totalSlots := candidate.Slots.Total
	if totalSlots <= 0 {
		totalSlots = 1
	}
	capacity, computedStatus := shareCapacityForActiveSessions(totalSlots, candidate.ActiveSessions)
	candidate.Slots = capacity
	if computedStatus == "busy" {
		candidate.Status = computedStatus
	}
	for idx := range candidate.Models {
		if candidate.Models[idx].SlotsTotal <= 0 {
			candidate.Models[idx].SlotsTotal = capacity.Total
		}
		if capacity.Free == 0 {
			candidate.Models[idx].SlotsFree = 0
		}
	}
}

func localShareProviderForStatus(shareStatus localShareStatus, runtime runtimeConfig) (provider, bool) {
	if !modeAllowsShare(runtime.Mode) {
		return provider{}, false
	}
	providerID := strings.TrimSpace(shareStatus.ProviderID)
	if providerID == "" {
		return provider{}, false
	}
	models := shareStatus.PublishedModels
	if len(models) == 0 {
		models = shareStatus.DiscoveredModels
	}
	if len(models) == 0 {
		return provider{}, false
	}
	swarmID := defaultValue(strings.TrimSpace(shareStatus.ActiveSwarmID), strings.TrimSpace(runtime.ActiveSwarmID))
	if swarmID == "" {
		return provider{}, false
	}
	capacity := shareStatus.Slots
	if capacity.Total <= 0 {
		capacity = slots{Free: 1, Total: 1}
	}
	status := strings.TrimSpace(shareStatus.Status)
	if status == "" || status == "ready" || status == "offline" {
		status = "available"
	}
	if shareStatus.ActiveSessions > 0 {
		capacity, status = shareCapacityForActiveSessions(capacity.Total, shareStatus.ActiveSessions)
	}
	memberID, memberName := localMemberIdentity()
	return provider{
		ID:                     providerID,
		Name:                   defaultValue(strings.TrimSpace(shareStatus.ProviderName), providerID),
		SwarmID:                swarmID,
		OwnerMemberID:          memberID,
		OwnerMemberName:        memberName,
		Status:                 status,
		MaintenanceState:       shareStatus.MaintenanceState,
		Modes:                  shareModesForRuntime(runtime.Mode),
		Slots:                  capacity,
		ActiveSessions:         shareStatus.ActiveSessions,
		ServedSessions:         shareStatus.ServedSessions,
		FailedSessions:         shareStatus.FailedSessions,
		UploadedTokensEstimate: shareStatus.UploadedTokensEstimate,
		RecentUploadedTokensPS: shareStatus.RecentUploadedTokensPS,
		LastServedModel:        shareStatus.LastServedModel,
		Hardware:               currentHardwareProfile(),
		ClientBuild:            shareStatus.ClientBuild,
		Models:                 models,
	}, true
}

func statusActiveSwarmName(swarms []swarm, runtime runtimeConfig, shareStatus localShareStatus) string {
	activeSwarmName := swarmName(swarms, runtime.ActiveSwarmID)
	if activeSwarmName == "" {
		activeSwarmName = strings.TrimSpace(shareStatus.ActiveSwarmName)
	}
	if activeSwarmName == "" {
		activeSwarmName = defaultSwarmName(runtime.ActiveSwarmID)
	}
	return activeSwarmName
}

func defaultSwarmName(swarmID string) string {
	if strings.TrimSpace(swarmID) == defaultPublicSwarmID {
		return "OnlyMacs Public"
	}
	return ""
}

func (s *service) preflightHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "preflight requires POST",
			},
		})
		return
	}

	runtime := s.runtime.Get()
	if !modeAllowsUse(runtime.Mode) {
		writeJSON(w, http.StatusConflict, map[string]any{
			"error": map[string]any{
				"code":    "MODE_BLOCKED",
				"message": "requester actions are disabled while the bridge is in share-only mode",
				"mode":    runtime.Mode,
			},
		})
		return
	}
	if runtime.ActiveSwarmID == "" {
		writeJSON(w, http.StatusConflict, map[string]any{
			"error": map[string]any{
				"code":    "NO_ACTIVE_POOL",
				"message": "no active swarm is selected for requester actions",
			},
		})
		return
	}

	var req preflightRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"error": map[string]any{
				"code":    "INVALID_JSON",
				"message": err.Error(),
			},
		})
		return
	}

	req.SwarmID = runtime.ActiveSwarmID
	req.Model = normalizeOpenAICompatibleModelAlias(req.Model)
	if err := s.ensureActiveSwarmCredential(r.Context(), runtime); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]any{
				"code":    "COORDINATOR_UNAVAILABLE",
				"message": err.Error(),
			},
		})
		return
	}
	requesterMemberID, requesterMemberName := localMemberIdentity()
	if strings.TrimSpace(req.RequesterMemberID) == "" {
		req.RequesterMemberID = requesterMemberID
	}
	if strings.TrimSpace(req.RequesterMemberName) == "" {
		req.RequesterMemberName = requesterMemberName
	}
	req.RouteScope = normalizeRouteScope(req.RouteScope)
	if req.RouteScope != routeScopeSwarm {
		req.PreferRemote = false
		req.PreferRemoteSoft = false
	}
	if req.PreferRemote {
		req.PreferRemoteSoft = false
	}
	if req.RouteScope == routeScopeLocalOnly && strings.TrimSpace(req.RouteProviderID) == "" {
		req.RouteProviderID = localProviderIDForRoute()
	}
	avoidProviderIDs, excludeProviderIDs := providerPreferenceIDsForRoute(req.RouteScope, req.PreferRemote, req.PreferRemoteSoft, req.AvoidProviderIDs, req.ExcludeProviderIDs)
	req.ExcludeProviderIDs = excludeProviderIDs
	req.AvoidProviderIDs = avoidProviderIDs
	resp, err := s.coordinator.preflight(req)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]any{
				"code":    "COORDINATOR_UNAVAILABLE",
				"message": err.Error(),
			},
		})
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

func (s *service) chatCompletionsHandler(w http.ResponseWriter, r *http.Request) {
	var req chatCompletionsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"error": map[string]any{
				"code":    "INVALID_JSON",
				"message": err.Error(),
			},
		})
		return
	}

	runtime := s.runtime.Get()
	if !modeAllowsUse(runtime.Mode) {
		writeJSON(w, http.StatusConflict, map[string]any{
			"error": map[string]any{
				"code":    "MODE_BLOCKED",
				"message": "requester actions are disabled while the bridge is in share-only mode",
				"mode":    runtime.Mode,
			},
		})
		return
	}
	if runtime.ActiveSwarmID == "" {
		writeJSON(w, http.StatusConflict, map[string]any{
			"error": map[string]any{
				"code":    "NO_ACTIVE_POOL",
				"message": "no active swarm is selected for requester actions",
			},
		})
		return
	}

	requestedModel := strings.TrimSpace(req.Model)
	req.Model = normalizeOpenAICompatibleModelAlias(requestedModel)
	req.RouteScope = normalizeRouteScope(req.RouteScope)
	if req.RouteScope != routeScopeSwarm {
		req.PreferRemote = false
		req.PreferRemoteSoft = false
	}
	if req.PreferRemote {
		req.PreferRemoteSoft = false
	}
	if req.RouteScope == routeScopeLocalOnly && strings.TrimSpace(req.RouteProviderID) == "" {
		req.RouteProviderID = localProviderIDForRoute()
	}
	avoidProviderIDs, excludeProviderIDs := providerPreferenceIDsForRoute(req.RouteScope, req.PreferRemote, req.PreferRemoteSoft, req.AvoidProviderIDs, req.ExcludeProviderIDs)
	requestTokenEstimate := estimateRequesterTokensFromRequest(req)

	if err := s.ensureActiveSwarmCredential(r.Context(), runtime); err != nil {
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]any{
				"code":    "COORDINATOR_UNAVAILABLE",
				"message": err.Error(),
			},
		})
		return
	}
	requesterMemberID, requesterMemberName := localMemberIdentity()
	reservation, err := s.coordinator.reserve(reserveSessionRequest{
		Model:               req.Model,
		SwarmID:             runtime.ActiveSwarmID,
		RequesterMemberID:   requesterMemberID,
		RequesterMemberName: requesterMemberName,
		RouteScope:          req.RouteScope,
		RouteProviderID:     req.RouteProviderID,
		AvoidProviderIDs:    avoidProviderIDs,
		ExcludeProviderIDs:  excludeProviderIDs,
	})
	if err != nil {
		var httpErr coordinatorHTTPError
		if ok := asCoordinatorHTTPError(err, &httpErr); ok && httpErr.StatusCode == http.StatusConflict {
			preflight, preflightErr := s.coordinator.preflight(preflightRequest{
				Model:               req.Model,
				SwarmID:             runtime.ActiveSwarmID,
				MaxProviders:        1,
				RequesterMemberID:   requesterMemberID,
				RequesterMemberName: requesterMemberName,
				RouteScope:          req.RouteScope,
				RouteProviderID:     req.RouteProviderID,
				AvoidProviderIDs:    avoidProviderIDs,
				ExcludeProviderIDs:  excludeProviderIDs,
			})
			if preflightErr == nil {
				message := "requested model is not available in the current swarm"
				errorCode := "MODEL_UNAVAILABLE"
				if preflight.RequesterReservationBlocked {
					message = fmt.Sprintf("this swarm member already has %d live request slot%s in flight; let one finish or switch this ask to This Mac / your Macs only first", preflight.RequesterActiveReservations, pluralSuffix(preflight.RequesterActiveReservations))
					errorCode = "REQUESTER_POOL_CAP"
				} else if req.PreferRemote && req.RouteScope == routeScopeSwarm {
					message = "no remote Macs are ready for this request right now; remote-first excludes This Mac"
					errorCode = "REMOTE_UNAVAILABLE"
				} else if preflight.RouteScope == routeScopeLocalOnly {
					message = "requested model is not available on This Mac right now"
				} else if preflight.RouteScope == routeScopeTrustedOnly {
					message = "requested model is not available on your Macs right now"
				}
				writeJSON(w, http.StatusConflict, map[string]any{
					"error": map[string]any{
						"code":                          errorCode,
						"message":                       message,
						"requested_model":               defaultValue(requestedModel, req.Model),
						"resolved_model":                preflight.ResolvedModel,
						"route_scope":                   preflight.RouteScope,
						"available_models":              preflight.AvailableModels,
						"requester_active_reservations": preflight.RequesterActiveReservations,
						"requester_reservation_cap":     preflight.RequesterReservationCap,
						"swarm_id":                      runtime.ActiveSwarmID,
					},
				})
				return
			}
		}

		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]any{
				"code":    "COORDINATOR_UNAVAILABLE",
				"message": err.Error(),
			},
		})
		return
	}

	releaseReservation := true
	defer func() {
		if releaseReservation {
			_, _ = s.coordinator.release(releaseSessionRequest{
				SessionID:           reservation.SessionID,
				SwarmID:             runtime.ActiveSwarmID,
				RequesterMemberID:   requesterMemberID,
				RequesterMemberName: requesterMemberName,
			})
		}
	}()
	setOnlyMacsRoutingHeaders(w, reservation, runtime.ActiveSwarmID, req.RouteScope)

	localProviderID, _ := localProviderIdentity()
	if reservation.Provider.ID != localProviderID {
		releaseReservation = false
		if req.Stream {
			countingWriter := newCountingResponseWriter(w, s.requestMetrics.recordStreamChunk)
			if err := s.proxyRemoteRelayStream(r.Context(), countingWriter, reservation, req, runtime.ActiveSwarmID, requesterMemberID); err != nil {
				s.requestMetrics.recordFailure(reservation.ResolvedModel)
				writeJSON(w, http.StatusBadGateway, map[string]any{
					"error": map[string]any{
						"code":     "RELAY_UNAVAILABLE",
						"message":  err.Error(),
						"model":    reservation.ResolvedModel,
						"provider": reservation.Provider.ID,
						"session":  reservation.SessionID,
						"swarm_id": runtime.ActiveSwarmID,
					},
				})
			} else if countingWriter.statusCode < http.StatusBadRequest {
				s.requestMetrics.recordCompletion(
					reservation.ResolvedModel,
					requestTokenEstimate,
					countingWriter.responseTokensEstimate(),
					countingWriter.bytesWritten,
					true,
				)
			} else {
				s.requestMetrics.recordFailure(reservation.ResolvedModel)
			}
			return
		}

		relayResp, err := s.coordinator.executeRelay(
			r.Context(),
			reservation.SessionID,
			reservation.Provider.ID,
			reservation.ResolvedModel,
			runtime.ActiveSwarmID,
			requesterMemberID,
			req,
		)
		if err != nil {
			s.requestMetrics.recordFailure(reservation.ResolvedModel)
			writeJSON(w, http.StatusBadGateway, map[string]any{
				"error": map[string]any{
					"code":     "RELAY_UNAVAILABLE",
					"message":  err.Error(),
					"model":    reservation.ResolvedModel,
					"provider": reservation.Provider.ID,
					"session":  reservation.SessionID,
					"swarm_id": runtime.ActiveSwarmID,
				},
			})
			return
		}

		body, err := decodeRelayBody(relayResp.BodyBase64)
		if err != nil {
			s.requestMetrics.recordFailure(reservation.ResolvedModel)
			writeJSON(w, http.StatusBadGateway, map[string]any{
				"error": map[string]any{
					"code":     "RELAY_UNAVAILABLE",
					"message":  err.Error(),
					"model":    reservation.ResolvedModel,
					"provider": reservation.Provider.ID,
					"session":  reservation.SessionID,
					"swarm_id": runtime.ActiveSwarmID,
				},
			})
			return
		}

		if contentType := strings.TrimSpace(relayResp.ContentType); contentType != "" {
			w.Header().Set("Content-Type", contentType)
		}
		statusCode := relayResp.StatusCode
		if statusCode <= 0 {
			statusCode = http.StatusOK
		}
		w.WriteHeader(statusCode)
		_, _ = w.Write(body)
		if statusCode < http.StatusBadRequest {
			s.requestMetrics.recordCompletion(
				reservation.ResolvedModel,
				requestTokenEstimate,
				estimateResponseTokensFromBody(relayResp.ContentType, body),
				len(body),
				false,
			)
		} else {
			s.requestMetrics.recordFailure(reservation.ResolvedModel)
		}
		return
	}

	if s.cfg.CannedChat {
		countingWriter := newCountingResponseWriter(w, s.requestMetrics.recordStreamChunk)
		writeCannedChatStream(countingWriter, reservation.Provider, reservation.ResolvedModel, reservation.SessionID)
		if countingWriter.statusCode < http.StatusBadRequest {
			s.requestMetrics.recordCompletion(
				reservation.ResolvedModel,
				requestTokenEstimate,
				countingWriter.responseTokensEstimate(),
				countingWriter.bytesWritten,
				true,
			)
		} else {
			s.requestMetrics.recordFailure(reservation.ResolvedModel)
		}
		return
	}

	if req.Stream {
		countingWriter := newCountingResponseWriter(w, s.requestMetrics.recordStreamChunk)
		if err := s.inference.proxyChatCompletions(r.Context(), countingWriter, req, reservation.ResolvedModel); err != nil {
			s.requestMetrics.recordFailure(reservation.ResolvedModel)
			writeJSON(w, http.StatusBadGateway, map[string]any{
				"error": map[string]any{
					"code":     "INFERENCE_UNAVAILABLE",
					"message":  err.Error(),
					"model":    reservation.ResolvedModel,
					"provider": reservation.Provider.ID,
					"session":  reservation.SessionID,
					"swarm_id": runtime.ActiveSwarmID,
				},
			})
			return
		}
		if countingWriter.statusCode < http.StatusBadRequest {
			s.requestMetrics.recordCompletion(
				reservation.ResolvedModel,
				requestTokenEstimate,
				countingWriter.responseTokensEstimate(),
				countingWriter.bytesWritten,
				true,
			)
		} else {
			s.requestMetrics.recordFailure(reservation.ResolvedModel)
		}
		return
	}

	statusCode, headers, body, err := s.inference.executeChatCompletions(r.Context(), req, reservation.ResolvedModel)
	if err != nil {
		s.requestMetrics.recordFailure(reservation.ResolvedModel)
		writeJSON(w, http.StatusBadGateway, map[string]any{
			"error": map[string]any{
				"code":     "INFERENCE_UNAVAILABLE",
				"message":  err.Error(),
				"model":    reservation.ResolvedModel,
				"provider": reservation.Provider.ID,
				"session":  reservation.SessionID,
				"swarm_id": runtime.ActiveSwarmID,
			},
		})
		return
	}
	contentType := ""
	if headers != nil {
		contentType = headers.Get("Content-Type")
		if contentType != "" {
			w.Header().Set("Content-Type", contentType)
		}
	}
	w.WriteHeader(statusCode)
	_, _ = w.Write(body)
	if statusCode < http.StatusBadRequest {
		s.requestMetrics.recordCompletion(
			reservation.ResolvedModel,
			requestTokenEstimate,
			estimateResponseTokensFromBody(contentType, body),
			len(body),
			false,
		)
	} else {
		s.requestMetrics.recordFailure(reservation.ResolvedModel)
	}
}

func normalizeOpenAICompatibleModelAlias(model string) string {
	trimmed := strings.TrimSpace(model)
	switch strings.ToLower(trimmed) {
	case "best", "best-available", "best_available", "onlymacs/best", "onlymacs/best-available", "onlymacs/best_available":
		return ""
	default:
		return trimmed
	}
}

func (s *service) proxyRemoteRelayStream(ctx context.Context, w http.ResponseWriter, reservation reserveSessionResponse, req chatCompletionsRequest, swarmID string, requesterMemberID string) error {
	err := s.coordinator.proxyRelayStream(
		ctx,
		w,
		reservation.SessionID,
		reservation.Provider.ID,
		reservation.ResolvedModel,
		swarmID,
		requesterMemberID,
		req,
	)
	return err
}

func setOnlyMacsRoutingHeaders(w http.ResponseWriter, reservation reserveSessionResponse, swarmID string, routeScope string) {
	headers := w.Header()
	headers.Set("X-OnlyMacs-Session-ID", reservation.SessionID)
	headers.Set("X-OnlyMacs-Resolved-Model", reservation.ResolvedModel)
	headers.Set("X-OnlyMacs-Provider-ID", reservation.Provider.ID)
	headers.Set("X-OnlyMacs-Provider-Name", sanitizeHeaderValue(reservation.Provider.Name))
	headers.Set("X-OnlyMacs-Owner-Member-ID", reservation.Provider.OwnerMemberID)
	headers.Set("X-OnlyMacs-Owner-Member-Name", sanitizeHeaderValue(reservation.Provider.OwnerMemberName))
	headers.Set("X-OnlyMacs-Swarm-ID", swarmID)
	headers.Set("X-OnlyMacs-Route-Scope", routeScope)
}

func sanitizeHeaderValue(value string) string {
	value = strings.TrimSpace(value)
	replacer := strings.NewReplacer("\r", " ", "\n", " ", "\t", " ")
	return replacer.Replace(value)
}

type countingResponseWriter struct {
	target       http.ResponseWriter
	header       http.Header
	statusCode   int
	bytesWritten int
	captured     strings.Builder
	onWrite      func(string, []byte)
}

func newCountingResponseWriter(target http.ResponseWriter, onWrite func(string, []byte)) *countingResponseWriter {
	return &countingResponseWriter{
		target:     target,
		header:     target.Header(),
		statusCode: http.StatusOK,
		onWrite:    onWrite,
	}
}

func (w *countingResponseWriter) Header() http.Header {
	return w.header
}

func (w *countingResponseWriter) WriteHeader(statusCode int) {
	w.statusCode = statusCode
	w.target.WriteHeader(statusCode)
}

func (w *countingResponseWriter) Write(body []byte) (int, error) {
	if w.statusCode == 0 {
		w.statusCode = http.StatusOK
	}
	written, err := w.target.Write(body)
	if written > 0 {
		w.bytesWritten += written
		if w.captured.Len() < 4*1024*1024 {
			remaining := 4*1024*1024 - w.captured.Len()
			if written < remaining {
				remaining = written
			}
			w.captured.Write(body[:remaining])
		}
		w.onWrite(w.Header().Get("Content-Type"), body[:written])
	}
	return written, err
}

func (w *countingResponseWriter) Flush() {
	if flusher, ok := w.target.(http.Flusher); ok {
		flusher.Flush()
	}
}

func (w *countingResponseWriter) responseTokensEstimate() int {
	if w.captured.Len() == 0 {
		return estimateTokensFromResponseBytes(w.bytesWritten)
	}
	return estimateResponseTokensFromBody(w.Header().Get("Content-Type"), []byte(w.captured.String()))
}

func (s *service) providersForRuntime(runtime runtimeConfig) (coordinatorProvidersResponse, error) {
	return s.providersForRuntimeWithContext(context.Background(), runtime)
}

func (s *service) providersForRuntimeWithContext(ctx context.Context, runtime runtimeConfig) (coordinatorProvidersResponse, error) {
	activeSwarmID := strings.TrimSpace(runtime.ActiveSwarmID)
	if activeSwarmID == "" {
		return coordinatorProvidersResponse{}, nil
	}
	if err := s.ensureActiveSwarmCredential(ctx, runtime); err != nil {
		return coordinatorProvidersResponse{}, err
	}
	resp, err := s.coordinator.providersWithContext(ctx, activeSwarmID)
	if !isUnauthorizedCoordinatorError(err) || activeSwarmID != defaultPublicSwarmID {
		return resp, err
	}
	memberID, _ := localMemberIdentity()
	providerID, _ := localProviderIdentity()
	s.coordinator.forgetRequesterToken(activeSwarmID, memberID)
	s.coordinator.forgetProviderToken(providerID)
	s.statusCache.clearCoordinatorState()
	if retryErr := s.ensureActiveSwarmCredential(ctx, runtime); retryErr != nil {
		return resp, err
	}
	return s.coordinator.providersWithContext(ctx, activeSwarmID)
}

func (s *service) swarmsForRuntimeWithContext(ctx context.Context, runtime runtimeConfig) (coordinatorSwarmsResponse, error) {
	resp, err := s.coordinator.swarmsWithContext(ctx)
	if !isUnauthorizedCoordinatorError(err) || strings.TrimSpace(runtime.ActiveSwarmID) == "" {
		return resp, err
	}
	if credentialErr := s.ensureActiveSwarmCredential(ctx, runtime); credentialErr != nil {
		return resp, credentialErr
	}
	return s.coordinator.swarmsWithContext(ctx)
}

func (s *service) statusCoordinatorState(ctx context.Context, runtime runtimeConfig) (coordinatorSwarmsResponse, error, coordinatorProvidersResponse, error, *memberSummaryResponse) {
	statusCtx, cancel := context.WithTimeout(ctx, statusCoordinatorPollTimeout)
	defer cancel()

	var (
		swarmsResp          coordinatorSwarmsResponse
		swarmsErr           error
		providersResp       coordinatorProvidersResponse
		providersErr        error
		memberSummary       *memberSummaryResponse
		wg                  sync.WaitGroup
		swarmsCached        bool
		providersCached     bool
		memberSummaryCached bool
	)
	now := time.Now().UTC()
	activeSwarmID := strings.TrimSpace(runtime.ActiveSwarmID)
	memberID := ""

	if cached, ok := s.statusCache.freshSwarms(now); ok {
		swarmsResp = cached
		swarmsCached = true
	} else {
		wg.Add(1)
		go func() {
			defer wg.Done()
			swarmsResp, swarmsErr = s.swarmsForRuntimeWithContext(statusCtx, runtime)
		}()
	}

	if activeSwarmID == "" {
		providersResp = coordinatorProvidersResponse{}
	} else if cached, ok := s.statusCache.freshProviders(activeSwarmID, now); ok {
		providersResp = cached
		providersCached = true
	} else {
		wg.Add(1)
		go func() {
			defer wg.Done()
			providersResp, providersErr = s.providersForRuntimeWithContext(statusCtx, runtime)
		}()
	}

	if activeSwarmID != "" {
		memberID, _ = localMemberIdentity()
		if cached, ok := s.statusCache.freshMemberSummary(activeSwarmID, memberID, now); ok {
			memberSummary = &cached
			memberSummaryCached = true
		} else {
			wg.Add(1)
			go func() {
				defer wg.Done()
				if summary, err := s.coordinator.memberSummaryWithContext(statusCtx, activeSwarmID, memberID); err == nil {
					memberSummary = &summary
				}
			}()
		}
	}

	wg.Wait()
	if swarmsErr == nil && !swarmsCached {
		s.statusCache.storeSwarms(swarmsResp, now)
	} else if cached, ok := s.statusCache.recentSwarms(now); ok {
		swarmsResp = cached
		swarmsErr = nil
	}
	if providersErr == nil && !providersCached && activeSwarmID != "" {
		s.statusCache.storeProviders(activeSwarmID, providersResp, now)
	} else if cached, ok := s.statusCache.recentProviders(activeSwarmID, now); ok {
		providersResp = cached
		providersErr = nil
	}
	if memberSummary != nil && !memberSummaryCached {
		s.statusCache.storeMemberSummary(activeSwarmID, memberID, *memberSummary, now)
	}
	return swarmsResp, swarmsErr, providersResp, providersErr, memberSummary
}

func isUnauthorizedCoordinatorError(err error) bool {
	var httpErr coordinatorHTTPError
	return asCoordinatorHTTPError(err, &httpErr) && httpErr.StatusCode == http.StatusUnauthorized
}

func isRequesterTokenMismatchCoordinatorError(err error) bool {
	var httpErr coordinatorHTTPError
	if !asCoordinatorHTTPError(err, &httpErr) || httpErr.StatusCode != http.StatusForbidden {
		return false
	}
	return strings.Contains(strings.ToUpper(httpErr.Message), "REQUESTER_TOKEN_REQUIRED") ||
		strings.Contains(strings.ToLower(httpErr.Message), "requester token does not match")
}

func isTransientCoordinatorStateError(err error) bool {
	if err == nil {
		return false
	}
	message := strings.ToLower(err.Error())
	transientFragments := []string{
		"context deadline exceeded",
		"client.timeout",
		"timeout awaiting response headers",
		"i/o timeout",
		"operation timed out",
		"connection reset",
		"connection refused",
		"unexpected eof",
		"returned 502",
		"returned 503",
		"returned 504",
		"bad gateway",
		"service unavailable",
		"gateway timeout",
	}
	for _, fragment := range transientFragments {
		if strings.Contains(message, fragment) {
			return true
		}
	}
	return false
}

func (s *service) swarmMembersForRuntime(runtime runtimeConfig) []swarmMemberSummary {
	if strings.TrimSpace(runtime.ActiveSwarmID) == "" {
		return []swarmMemberSummary{}
	}
	resp, err := s.coordinator.swarmMembers(runtime.ActiveSwarmID)
	if err != nil {
		return []swarmMemberSummary{}
	}
	return resp.Members
}

func buildSwarmMembers(providers []provider, memberSummary *memberSummaryResponse) []swarmMemberSummary {
	membersByID := make(map[string]*swarmMemberSummary)
	for _, provider := range providers {
		memberID := defaultValue(strings.TrimSpace(provider.OwnerMemberID), provider.ID)
		memberName := defaultValue(strings.TrimSpace(provider.OwnerMemberName), defaultValue(strings.TrimSpace(provider.Name), memberID))
		member := membersByID[memberID]
		if member == nil {
			member = &swarmMemberSummary{
				MemberID:    memberID,
				MemberName:  memberName,
				Mode:        "both",
				SwarmID:     provider.SwarmID,
				Status:      "available",
				ClientBuild: provider.ClientBuild,
			}
			membersByID[memberID] = member
		}
		if member.Hardware == nil && provider.Hardware != nil {
			member.Hardware = provider.Hardware
		}
		if member.ClientBuild == nil && provider.ClientBuild != nil {
			member.ClientBuild = provider.ClientBuild
		}
		modelCount, bestModel := providerModelStats(provider)
		if bestModel != "" && (member.BestModel == "" || modelQualityRank(bestModel) > modelQualityRank(member.BestModel)) {
			member.BestModel = bestModel
			if provider.Hardware != nil {
				member.Hardware = provider.Hardware
			}
			if provider.ClientBuild != nil {
				member.ClientBuild = provider.ClientBuild
			}
		}
		member.ProviderCount++
		member.ActiveJobsServing += provider.ActiveSessions
		if member.MaintenanceState == "" && strings.TrimSpace(provider.MaintenanceState) != "" {
			member.MaintenanceState = strings.TrimSpace(provider.MaintenanceState)
		}
		if provider.ActiveSessions > 0 && strings.TrimSpace(provider.ActiveModel) != "" {
			member.ActiveModel = strings.TrimSpace(provider.ActiveModel)
		}
		member.RecentUploadedTokensPS += provider.RecentUploadedTokensPS
		member.TotalModelsAvailable += modelCount
		member.Capabilities = append(member.Capabilities, swarmMemberCapabilitySummary{
			ProviderID:             provider.ID,
			ProviderName:           provider.Name,
			Status:                 provider.Status,
			MaintenanceState:       provider.MaintenanceState,
			ActiveSessions:         provider.ActiveSessions,
			ActiveModel:            provider.ActiveModel,
			Slots:                  provider.Slots,
			ModelCount:             modelCount,
			BestModel:              bestModel,
			RecentUploadedTokensPS: provider.RecentUploadedTokensPS,
			Hardware:               provider.Hardware,
			ClientBuild:            provider.ClientBuild,
			Models:                 provider.Models,
		})
	}

	if memberSummary != nil && strings.TrimSpace(memberSummary.MemberID) != "" {
		memberID := strings.TrimSpace(memberSummary.MemberID)
		member := membersByID[memberID]
		if member == nil {
			member = &swarmMemberSummary{
				MemberID:   memberID,
				MemberName: defaultValue(strings.TrimSpace(memberSummary.MemberName), memberID),
				Mode:       "both",
				SwarmID:    memberSummary.SwarmID,
				Status:     "online",
			}
			membersByID[memberID] = member
		}
		member.ActiveJobsConsuming = memberSummary.ActiveReservations
		if member.BestModel == "" {
			member.BestModel = memberSummary.BestPublishedModel
		}
	}

	members := make([]swarmMemberSummary, 0, len(membersByID))
	for _, member := range membersByID {
		switch {
		case member.ActiveJobsServing > 0 && member.ActiveJobsConsuming > 0:
			member.Status = "serving_and_using"
		case member.ActiveJobsServing > 0:
			member.Status = "serving"
		case member.ActiveJobsConsuming > 0:
			member.Status = "using"
		case member.MaintenanceState != "":
			member.Status = member.MaintenanceState
		case member.ProviderCount > 0:
			member.Status = "available"
		default:
			member.Status = "online"
		}
		members = append(members, *member)
	}
	sort.SliceStable(members, func(i, j int) bool {
		leftActive := members[i].ActiveJobsServing + members[i].ActiveJobsConsuming
		rightActive := members[j].ActiveJobsServing + members[j].ActiveJobsConsuming
		if leftActive != rightActive {
			return leftActive > rightActive
		}
		if members[i].ProviderCount != members[j].ProviderCount {
			return members[i].ProviderCount > members[j].ProviderCount
		}
		return strings.ToLower(members[i].MemberName) < strings.ToLower(members[j].MemberName)
	})
	return members
}

func providerModelStats(provider provider) (int, string) {
	bestModel := ""
	for _, model := range provider.Models {
		if bestModel == "" || modelQualityRank(model.ID) > modelQualityRank(bestModel) {
			bestModel = model.ID
		}
	}
	return len(provider.Models), bestModel
}

func modelQualityRank(modelID string) int {
	lower := strings.ToLower(modelID)
	switch {
	case strings.Contains(lower, "maverick"):
		return 50
	case strings.Contains(lower, "qwen3.6") && (strings.Contains(lower, "q8") || strings.Contains(lower, "8_0")):
		return 48
	case strings.Contains(lower, "qwen3.6"):
		return 44
	case strings.Contains(lower, "32b") || strings.Contains(lower, "35b"):
		return 30
	case strings.Contains(lower, "22b") || strings.Contains(lower, "27b") || strings.Contains(lower, "31b"):
		return 20
	case strings.Contains(lower, "14b"):
		return 10
	default:
		return 0
	}
}

func aggregateModels(providers []provider) []model {
	modelsByID := make(map[string]model)
	for _, provider := range providers {
		for _, model := range provider.Models {
			existing := modelsByID[model.ID]
			if existing.ID == "" {
				existing = model
				existing.SlotsFree = 0
				existing.SlotsTotal = 0
			}
			existing.SlotsFree += model.SlotsFree
			existing.SlotsTotal += model.SlotsTotal
			modelsByID[model.ID] = existing
		}
	}

	models := make([]model, 0, len(modelsByID))
	for _, model := range modelsByID {
		models = append(models, model)
	}

	sort.Slice(models, func(i, j int) bool {
		return compareAggregatedModels(models[i], models[j])
	})

	return models
}

func compareAggregatedModels(left model, right model) bool {
	if (left.SlotsFree > 0) != (right.SlotsFree > 0) {
		return left.SlotsFree > 0
	}
	leftScore := aggregatedModelQualityScore(left.ID)
	rightScore := aggregatedModelQualityScore(right.ID)
	if leftScore != rightScore {
		return leftScore > rightScore
	}
	if left.SlotsFree != right.SlotsFree {
		return left.SlotsFree > right.SlotsFree
	}
	if left.SlotsTotal != right.SlotsTotal {
		return left.SlotsTotal > right.SlotsTotal
	}
	return left.ID < right.ID
}

func aggregatedModelQualityScore(modelID string) int {
	lowered := strings.ToLower(strings.TrimSpace(modelID))
	score := 0
	best := 0
	for index := 0; index < len(lowered); index++ {
		if lowered[index] < '0' || lowered[index] > '9' {
			continue
		}
		start := index
		for index < len(lowered) && lowered[index] >= '0' && lowered[index] <= '9' {
			index++
		}
		if index >= len(lowered) || lowered[index] != 'b' {
			continue
		}
		value, err := strconv.Atoi(lowered[start:index])
		if err == nil && value > best {
			best = value
		}
	}
	score += best * 10

	switch {
	case strings.Contains(lowered, "maverick"):
		score += 2_000
	case strings.Contains(lowered, "235b"):
		score += 1_500
	case strings.Contains(lowered, "deepseek"):
		score += 900
	}

	switch {
	case strings.Contains(lowered, "coder"):
		score += 500
	case strings.Contains(lowered, "codestral"):
		score += 420
	case strings.Contains(lowered, "qwq"):
		score += 380
	case strings.Contains(lowered, "gemma4"):
		score += 340
	case strings.Contains(lowered, "gemma"):
		score += 280
	case strings.Contains(lowered, "llama"):
		score += 320
	}

	return score
}

func aggregateActiveSessions(providers []provider) int {
	total := 0
	for _, provider := range providers {
		total += provider.ActiveSessions
	}
	return total
}

func aggregateProviderSlots(providers []provider) (int, int) {
	free := 0
	total := 0
	for _, provider := range providers {
		free += provider.Slots.Free
		total += provider.Slots.Total
	}
	return free, total
}

func asCoordinatorHTTPError(err error, target *coordinatorHTTPError) bool {
	httpErr, ok := err.(coordinatorHTTPError)
	if !ok {
		return false
	}
	*target = httpErr
	return true
}

func swarmName(swarms []swarm, swarmID string) string {
	for _, swarm := range swarms {
		if swarm.ID == swarmID {
			return swarm.Name
		}
	}
	return ""
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
