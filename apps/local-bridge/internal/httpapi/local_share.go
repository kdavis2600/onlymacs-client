package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unicode"
)

var (
	cachedNodeID string
	nodeIDMu     sync.Mutex
	nodeIDOnce   sync.Once
)

type createLocalSwarmRequest struct {
	Name         string `json:"name"`
	MemberName   string `json:"member_name"`
	Mode         string `json:"mode"`
	JoinPassword string `json:"join_password,omitempty"`
}

type createLocalSwarmResponse struct {
	Swarm   swarm         `json:"swarm"`
	Invite  swarmInvite   `json:"invite"`
	Member  swarmMember   `json:"member"`
	Runtime runtimeConfig `json:"runtime"`
}

type createLocalInviteRequest struct {
	SwarmID string `json:"swarm_id,omitempty"`
}

type createLocalInviteResponse struct {
	Invite swarmInvite `json:"invite"`
}

type joinLocalSwarmRequest struct {
	SwarmID      string `json:"swarm_id,omitempty"`
	InviteToken  string `json:"invite_token"`
	MemberName   string `json:"member_name"`
	Mode         string `json:"mode"`
	JoinPassword string `json:"join_password,omitempty"`
}

type joinLocalSwarmResponse struct {
	Swarm   swarm         `json:"swarm"`
	Member  swarmMember   `json:"member"`
	Runtime runtimeConfig `json:"runtime"`
}

type publishLocalShareRequest struct {
	SlotsTotal       int      `json:"slots_total,omitempty"`
	ModelIDs         []string `json:"model_ids,omitempty"`
	MaintenanceState string   `json:"maintenance_state,omitempty"`
}

type localShareStatus struct {
	ProviderID             string             `json:"provider_id"`
	ProviderName           string             `json:"provider_name"`
	Mode                   string             `json:"mode"`
	ActiveSwarmID          string             `json:"active_swarm_id,omitempty"`
	ActiveSwarmName        string             `json:"active_swarm_name,omitempty"`
	Published              bool               `json:"published"`
	Status                 string             `json:"status"`
	MaintenanceState       string             `json:"maintenance_state,omitempty"`
	ActiveSessions         int                `json:"active_sessions"`
	Slots                  slots              `json:"slots"`
	DiscoveredModels       []model            `json:"discovered_models"`
	PublishedModels        []model            `json:"published_models"`
	ServedSessions         int                `json:"served_sessions"`
	ServedStreamSessions   int                `json:"served_stream_sessions"`
	FailedSessions         int                `json:"failed_sessions"`
	UploadedTokensEstimate int                `json:"uploaded_tokens_estimate"`
	RecentUploadedTokensPS float64            `json:"recent_uploaded_tokens_per_second,omitempty"`
	LastServedModel        string             `json:"last_served_model,omitempty"`
	LastServedAt           *time.Time         `json:"last_served_at,omitempty"`
	ClientBuild            *clientBuild       `json:"client_build,omitempty"`
	RecentProviderActivity []providerActivity `json:"recent_provider_activity,omitempty"`
	Error                  string             `json:"error,omitempty"`
}

func shareCapacityForActiveSessions(slotCount int, activeSessions int) (slots, string) {
	if slotCount <= 0 {
		slotCount = 1
	}
	if activeSessions < 0 {
		activeSessions = 0
	}
	freeSlots := slotCount - activeSessions
	if freeSlots < 0 {
		freeSlots = 0
	}
	status := "available"
	if freeSlots == 0 && activeSessions > 0 {
		status = "busy"
	}
	return slots{Free: freeSlots, Total: slotCount}, status
}

func (s *service) createSwarmHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "swarm create requires POST",
			},
		})
		return
	}

	var req createLocalSwarmRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]any{
			"error": map[string]any{
				"code":    "INVALID_JSON",
				"message": err.Error(),
			},
		})
		return
	}

	mode, err := resolveMode(req.Mode, s.runtime.Get().Mode)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_MODE", err.Error()))
		return
	}

	memberID, defaultMemberName := localMemberIdentity()
	memberName := defaultValue(strings.TrimSpace(req.MemberName), defaultMemberName)

	createReq := createSwarmRequest{
		Name:            strings.TrimSpace(req.Name),
		Visibility:      "private",
		Discoverability: "unlisted",
		OwnerMemberID:   memberID,
		OwnerMemberName: memberName,
		OwnerMode:       mode,
		JoinPolicy:      &swarmJoinPolicy{Version: 1, Mode: "invite_link"},
		ClientBuild:     s.cfg.ClientBuild,
	}
	if joinPassword := strings.TrimSpace(req.JoinPassword); joinPassword != "" {
		createReq.JoinPassword = joinPassword
		createReq.JoinPolicy = &swarmJoinPolicy{Version: 1, Mode: "password"}
	}
	swarmResp, err := s.coordinator.createSwarm(createReq)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, invalidRequest("COORDINATOR_UNAVAILABLE", err.Error()))
		return
	}

	inviteResp, err := s.coordinator.createInvite(swarmResp.Swarm.ID)
	if err != nil {
		writeJSON(w, http.StatusBadGateway, invalidRequest("COORDINATOR_UNAVAILABLE", err.Error()))
		return
	}

	joinResp, err := s.coordinator.joinSwarm(joinSwarmRequest{
		InviteToken:  inviteResp.Invite.InviteToken,
		MemberID:     memberID,
		MemberName:   memberName,
		Mode:         mode,
		JoinPassword: strings.TrimSpace(req.JoinPassword),
		ClientBuild:  s.cfg.ClientBuild,
	})
	if err != nil {
		writeJSON(w, http.StatusBadGateway, invalidRequest("COORDINATOR_UNAVAILABLE", err.Error()))
		return
	}

	runtime := s.runtime.Set(runtimeConfig{
		Mode:          mode,
		ActiveSwarmID: joinResp.Swarm.ID,
	})
	writeJSON(w, http.StatusCreated, createLocalSwarmResponse{
		Swarm:   joinResp.Swarm,
		Invite:  inviteResp.Invite,
		Member:  joinResp.Member,
		Runtime: runtime,
	})
}

func (s *service) inviteHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "swarm invite requires POST",
			},
		})
		return
	}

	var req createLocalInviteRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && err != io.EOF {
		writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_JSON", err.Error()))
		return
	}

	swarmID := strings.TrimSpace(req.SwarmID)
	if swarmID == "" {
		swarmID = s.runtime.Get().ActiveSwarmID
	}
	if swarmID == "" {
		writeJSON(w, http.StatusConflict, invalidRequest("NO_ACTIVE_POOL", "no active swarm is selected"))
		return
	}

	resp, err := s.coordinator.createInvite(swarmID)
	if err != nil {
		writeCoordinatorError(w, err, "POOL_NOT_FOUND", "swarm could not be found")
		return
	}

	writeJSON(w, http.StatusCreated, createLocalInviteResponse{
		Invite: resp.Invite,
	})
}

func (s *service) joinSwarmHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "swarm join requires POST",
			},
		})
		return
	}

	var req joinLocalSwarmRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_JSON", err.Error()))
		return
	}

	mode, err := resolveMode(req.Mode, s.runtime.Get().Mode)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_MODE", err.Error()))
		return
	}
	inviteToken := strings.TrimSpace(req.InviteToken)
	swarmID := strings.TrimSpace(req.SwarmID)
	if inviteToken == "" && swarmID == "" && s.runtime.Get().ActiveSwarmID == defaultPublicSwarmID {
		swarmID = defaultPublicSwarmID
	}
	if inviteToken == "" && swarmID == "" {
		writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_INVITE", "invite_token is required unless joining an open public swarm"))
		return
	}

	memberID, defaultMemberName := localMemberIdentity()
	joinReq := joinSwarmRequest{
		SwarmID:      swarmID,
		InviteToken:  inviteToken,
		MemberID:     memberID,
		MemberName:   defaultValue(strings.TrimSpace(req.MemberName), defaultMemberName),
		Mode:         mode,
		JoinPassword: strings.TrimSpace(req.JoinPassword),
		ClientBuild:  s.cfg.ClientBuild,
	}
	joinResp, err := s.coordinator.joinSwarm(joinReq)
	if err != nil && inviteToken == "" && swarmID == defaultPublicSwarmID && isRequesterTokenMismatchCoordinatorError(err) {
		if _, ok := rotateLocalNodeIDForRecovery(); ok {
			memberID, defaultMemberName = localMemberIdentity()
			joinReq.MemberID = memberID
			joinReq.MemberName = defaultValue(strings.TrimSpace(req.MemberName), defaultMemberName)
			joinResp, err = s.coordinator.joinSwarm(joinReq)
		}
	}
	if err != nil {
		writeCoordinatorError(w, err, "INVITE_NOT_FOUND", "invite token could not be resolved")
		return
	}

	runtime := s.runtime.Set(runtimeConfig{
		Mode:          mode,
		ActiveSwarmID: joinResp.Swarm.ID,
	})
	writeJSON(w, http.StatusOK, joinLocalSwarmResponse{
		Swarm:   joinResp.Swarm,
		Member:  joinResp.Member,
		Runtime: runtime,
	})
}

func (s *service) localShareStatusHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "share status requires GET",
			},
		})
		return
	}

	if !s.statusCache.shareReconcileFresh(time.Now().UTC()) {
		if err := s.reconcileSharePublication(r.Context()); err == nil {
			s.statusCache.markShareReconciled(time.Now().UTC())
		}
	}
	status := s.localShareSnapshotCached(r.Context())
	writeJSON(w, http.StatusOK, status)
}

func (s *service) publishLocalShareHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "share publish requires POST",
			},
		})
		return
	}

	var req publishLocalShareRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil && err != io.EOF {
		writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_JSON", err.Error()))
		return
	}

	runtime := s.runtime.Get()
	if runtime.ActiveSwarmID == "" {
		writeJSON(w, http.StatusConflict, invalidRequest("NO_ACTIVE_POOL", "no active swarm is selected"))
		return
	}
	if !modeAllowsShare(runtime.Mode) {
		runtime = s.runtime.Set(runtimeConfig{
			Mode:          "both",
			ActiveSwarmID: runtime.ActiveSwarmID,
		})
	}

	models, err := s.inference.listModels(r.Context())
	if err != nil {
		writeJSON(w, http.StatusBadGateway, invalidRequest("INFERENCE_UNAVAILABLE", err.Error()))
		return
	}
	selected := selectModels(models, req.ModelIDs)
	if len(selected) == 0 {
		writeJSON(w, http.StatusBadRequest, invalidRequest("NO_MODELS_SELECTED", "no local models are available to publish"))
		return
	}
	slotCount := req.SlotsTotal
	if slotCount <= 0 {
		slotCount = 1
	}
	for idx := range selected {
		selected[idx].SlotsFree = slotCount
		selected[idx].SlotsTotal = slotCount
	}

	if runtime.ActiveSwarmID == defaultPublicSwarmID {
		if err := s.ensurePublicSwarmMembership(r.Context(), runtime); err != nil {
			writeJSON(w, http.StatusBadGateway, invalidRequest("COORDINATOR_UNAVAILABLE", err.Error()))
			return
		}
	}

	providerID, providerName := localProviderIdentity()
	memberID, memberName := localMemberIdentity()
	shareMetrics := s.shareMetrics.snapshotValue()
	maintenanceState := normalizeMaintenanceState(req.MaintenanceState)
	resp, err := s.coordinator.registerProvider(registerProviderRequest{
		Provider: provider{
			ID:               providerID,
			Name:             providerName,
			SwarmID:          runtime.ActiveSwarmID,
			OwnerMemberID:    memberID,
			OwnerMemberName:  memberName,
			Status:           "available",
			MaintenanceState: maintenanceState,
			Modes:            shareModesForRuntime(runtime.Mode),
			Slots: slots{
				Free:  slotCount,
				Total: slotCount,
			},
			ServedSessions:         shareMetrics.ServedSessions,
			FailedSessions:         shareMetrics.FailedSessions,
			UploadedTokensEstimate: shareMetrics.UploadedTokensEstimate,
			RecentUploadedTokensPS: shareMetrics.RecentUploadedTokensPS,
			LastServedModel:        shareMetrics.LastServedModel,
			Hardware:               currentHardwareProfile(),
			ClientBuild:            s.cfg.ClientBuild,
			Models:                 selected,
		},
	})
	if err != nil {
		writeJSON(w, http.StatusBadGateway, invalidRequest("COORDINATOR_UNAVAILABLE", err.Error()))
		return
	}
	s.statusCache.clearCoordinatorState()

	writeJSON(w, http.StatusCreated, map[string]any{
		"status":   resp.Status,
		"provider": resp.Provider,
		"sharing":  s.localShareSnapshot(r.Context()),
	})
}

func (s *service) unpublishLocalShareHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{
			"error": map[string]any{
				"code":    "METHOD_NOT_ALLOWED",
				"message": "share unpublish requires POST",
			},
		})
		return
	}

	providerID, _ := localProviderIdentity()
	resp, err := s.coordinator.unregisterProvider(providerID)
	if err != nil {
		var httpErr coordinatorHTTPError
		if asCoordinatorHTTPError(err, &httpErr) && httpErr.StatusCode == http.StatusNotFound {
			writeJSON(w, http.StatusOK, map[string]any{
				"status":      "not_published",
				"provider_id": providerID,
				"sharing":     s.localShareSnapshot(r.Context()),
			})
			return
		}
		writeJSON(w, http.StatusBadGateway, invalidRequest("COORDINATOR_UNAVAILABLE", err.Error()))
		return
	}
	s.statusCache.clearCoordinatorState()

	writeJSON(w, http.StatusOK, map[string]any{
		"status":      resp.Status,
		"provider_id": resp.ProviderID,
		"sharing":     s.localShareSnapshot(r.Context()),
	})
}

func (s *service) localShareSnapshot(ctx context.Context) localShareStatus {
	status := s.localShareSnapshotFast(ctx)
	memberID, _ := localMemberIdentity()
	status.RecentProviderActivity = s.recentProviderActivity(status.ProviderID, memberID, status.ActiveSwarmID)

	runtime := s.runtime.Get()
	swarmsResp, swarmsErr := s.swarmsForRuntimeWithContext(ctx, runtime)
	if swarmsErr == nil {
		s.statusCache.storeSwarms(swarmsResp, time.Now().UTC())
		status.ActiveSwarmName = swarmName(swarmsResp.Swarms, status.ActiveSwarmID)
	}

	providersResp, providersErr := s.providersForRuntimeWithContext(ctx, runtime)
	if providersErr != nil {
		status.Error = providersErr.Error()
		status.Status = "degraded"
		return status
	}

	s.statusCache.storeProviders(status.ActiveSwarmID, providersResp, time.Now().UTC())
	s.enrichLocalShareSnapshotFromCoordinator(&status, providersResp.Providers, swarmsResp.Swarms)
	return status
}

func (s *service) localShareSnapshotCached(ctx context.Context) localShareStatus {
	status := s.localShareSnapshotFast(ctx)
	memberID, _ := localMemberIdentity()
	status.RecentProviderActivity = s.recentProviderActivityCached(status.ProviderID, memberID, status.ActiveSwarmID)
	runtime := s.runtime.Get()

	now := time.Now().UTC()
	var swarmsResp coordinatorSwarmsResponse
	if cached, ok := s.statusCache.freshSwarms(now); ok {
		swarmsResp = cached
		status.ActiveSwarmName = swarmName(swarmsResp.Swarms, status.ActiveSwarmID)
	} else if resp, err := s.swarmsForRuntimeWithContext(ctx, runtime); err == nil {
		swarmsResp = resp
		s.statusCache.storeSwarms(resp, time.Now().UTC())
		status.ActiveSwarmName = swarmName(resp.Swarms, status.ActiveSwarmID)
	}

	if cached, ok := s.statusCache.freshProviders(status.ActiveSwarmID, time.Now().UTC()); ok {
		s.enrichLocalShareSnapshotFromCoordinator(&status, cached.Providers, swarmsResp.Swarms)
		return status
	}

	providersResp, providersErr := s.providersForRuntimeWithContext(ctx, runtime)
	if providersErr != nil {
		if cached, ok := s.statusCache.recentProviders(status.ActiveSwarmID, time.Now().UTC()); ok {
			s.enrichLocalShareSnapshotFromCoordinator(&status, cached.Providers, swarmsResp.Swarms)
			return status
		}
		status.Error = providersErr.Error()
		status.Status = "degraded"
		return status
	}

	s.statusCache.storeProviders(status.ActiveSwarmID, providersResp, time.Now().UTC())
	s.enrichLocalShareSnapshotFromCoordinator(&status, providersResp.Providers, swarmsResp.Swarms)
	return status
}

func (s *service) localShareSnapshotFast(ctx context.Context) localShareStatus {
	providerID, providerName := localProviderIdentity()
	runtime := s.runtime.Get()
	shareMetrics := s.shareMetrics.snapshotValue()
	status := localShareStatus{
		ProviderID:             providerID,
		ProviderName:           providerName,
		Mode:                   runtime.Mode,
		ActiveSwarmID:          runtime.ActiveSwarmID,
		Status:                 "offline",
		ActiveSessions:         0,
		Slots:                  slots{Free: 1, Total: 1},
		ServedSessions:         shareMetrics.ServedSessions,
		ServedStreamSessions:   shareMetrics.ServedStreamSessions,
		FailedSessions:         shareMetrics.FailedSessions,
		UploadedTokensEstimate: shareMetrics.UploadedTokensEstimate,
		RecentUploadedTokensPS: shareMetrics.RecentUploadedTokensPS,
		LastServedModel:        shareMetrics.LastServedModel,
		LastServedAt:           shareMetrics.LastServedAt,
		ClientBuild:            s.cfg.ClientBuild,
	}

	models, err := s.inference.listModels(ctx)
	if err != nil {
		status.Error = err.Error()
		return status
	}
	status.DiscoveredModels = models
	status.Status = "ready"
	return status
}

func (s *service) enrichLocalShareSnapshotFromCoordinator(status *localShareStatus, providers []provider, swarms []swarm) {
	if status == nil {
		return
	}
	if status.ActiveSwarmName == "" {
		status.ActiveSwarmName = swarmName(swarms, status.ActiveSwarmID)
	}

	for _, candidate := range providers {
		if candidate.ID != status.ProviderID {
			continue
		}
		localActiveSessions := s.shareMetrics.activeSessionCount()
		status.Published = true
		status.ActiveSwarmID = candidate.SwarmID
		if status.ActiveSwarmName == "" {
			status.ActiveSwarmName = swarmName(swarms, candidate.SwarmID)
		}
		status.ActiveSessions = candidate.ActiveSessions
		status.Status = candidate.Status
		status.MaintenanceState = candidate.MaintenanceState
		status.Slots = candidate.Slots
		status.PublishedModels = candidate.Models
		if candidate.ClientBuild != nil {
			status.ClientBuild = candidate.ClientBuild
		}
		if localActiveSessions > status.ActiveSessions {
			status.ActiveSessions = localActiveSessions
		}
		normalizeLocalShareCapacityStatus(status)
		return
	}
}

func normalizeLocalShareCapacityStatus(status *localShareStatus) {
	if status == nil || status.ActiveSessions <= 0 {
		return
	}
	capacity, computedStatus := shareCapacityForActiveSessions(status.Slots.Total, status.ActiveSessions)
	status.Slots = capacity
	if computedStatus == "busy" {
		status.Status = computedStatus
	}
	for idx := range status.PublishedModels {
		if status.PublishedModels[idx].SlotsTotal <= 0 {
			status.PublishedModels[idx].SlotsTotal = status.Slots.Total
		}
		if status.Slots.Free == 0 {
			status.PublishedModels[idx].SlotsFree = 0
		}
	}
}

func (s *service) recentProviderActivity(providerID string, ownerMemberID string, swarmID string) []providerActivity {
	resp, err := s.coordinator.providerActivities(providerID, ownerMemberID, swarmID, 8)
	if err == nil {
		s.statusCache.storeProviderActivities(providerID, ownerMemberID, swarmID, resp, time.Now().UTC())
		return resp.Activities
	}
	var httpErr coordinatorHTTPError
	if asCoordinatorHTTPError(err, &httpErr) && (httpErr.StatusCode == http.StatusNotFound || httpErr.StatusCode == http.StatusMethodNotAllowed) {
		return nil
	}
	return nil
}

func (s *service) recentProviderActivityCached(providerID string, ownerMemberID string, swarmID string) []providerActivity {
	now := time.Now().UTC()
	if cached, ok := s.statusCache.freshProviderActivities(providerID, ownerMemberID, swarmID, now); ok {
		return cached.Activities
	}
	return s.recentProviderActivity(providerID, ownerMemberID, swarmID)
}

func (s *service) ensurePublicSwarmMembership(ctx context.Context, runtime runtimeConfig) error {
	swarmID := strings.TrimSpace(runtime.ActiveSwarmID)
	if swarmID == "" || swarmID != defaultPublicSwarmID {
		return nil
	}
	return s.upsertActiveMemberWithRecovery(ctx, runtime)
}

func (s *service) upsertActiveMemberWithRecovery(ctx context.Context, runtime runtimeConfig) error {
	swarmID := strings.TrimSpace(runtime.ActiveSwarmID)
	if swarmID == "" {
		return nil
	}
	memberID, memberName := localMemberIdentity()
	_, err := s.coordinator.upsertMemberWithContext(ctx, upsertMemberRequest{
		SwarmID:     swarmID,
		MemberID:    memberID,
		MemberName:  memberName,
		Mode:        defaultValue(strings.TrimSpace(runtime.Mode), "use"),
		ClientBuild: s.cfg.ClientBuild,
	})
	var httpErr coordinatorHTTPError
	if err != nil && asCoordinatorHTTPError(err, &httpErr) && (httpErr.StatusCode == http.StatusNotFound || httpErr.StatusCode == http.StatusMethodNotAllowed) {
		return nil
	}
	if err != nil && swarmID == defaultPublicSwarmID && isRequesterTokenMismatchCoordinatorError(err) {
		if _, ok := rotateLocalNodeIDForRecovery(); ok {
			memberID, memberName = localMemberIdentity()
			_, retryErr := s.coordinator.upsertMemberWithContext(ctx, upsertMemberRequest{
				SwarmID:     swarmID,
				MemberID:    memberID,
				MemberName:  memberName,
				Mode:        defaultValue(strings.TrimSpace(runtime.Mode), "use"),
				ClientBuild: s.cfg.ClientBuild,
			})
			if retryErr == nil {
				s.statusCache.clearCoordinatorState()
				return nil
			}
			return retryErr
		}
	}
	return err
}

func (s *service) ensureActiveSwarmCredential(ctx context.Context, runtime runtimeConfig) error {
	swarmID := strings.TrimSpace(runtime.ActiveSwarmID)
	if swarmID == "" {
		return nil
	}
	memberID, _ := localMemberIdentity()
	if s.coordinator.requesterToken(swarmID, memberID) != "" {
		return nil
	}
	if swarmID != defaultPublicSwarmID {
		return nil
	}
	return s.upsertActiveMemberWithRecovery(ctx, runtime)
}

func (s *service) refreshLocalMembership(ctx context.Context) error {
	runtime := s.runtime.Get()
	swarmID := strings.TrimSpace(runtime.ActiveSwarmID)
	if swarmID != "" {
		if err := s.upsertActiveMemberWithRecovery(ctx, runtime); err != nil {
			return err
		}
	}
	return s.reconcileSharePublication(ctx)
}

func (s *service) removePublicSwarmMembership(ctx context.Context) error {
	memberID, _ := localMemberIdentity()
	_, err := s.coordinator.removeMemberWithContext(ctx, removeMemberRequest{
		SwarmID:  defaultPublicSwarmID,
		MemberID: memberID,
	})
	var httpErr coordinatorHTTPError
	if err != nil && asCoordinatorHTTPError(err, &httpErr) && httpErr.StatusCode == http.StatusNotFound {
		return nil
	}
	if err == nil {
		s.statusCache.clearCoordinatorState()
	}
	return err
}

func (s *service) reconcileSharePublication(ctx context.Context) error {
	runtime := s.runtime.Get()
	if err := s.ensureActiveSwarmCredential(ctx, runtime); err != nil {
		return err
	}
	activeSwarmID := strings.TrimSpace(runtime.ActiveSwarmID)
	published, err := s.currentPublishedProvider(ctx)
	if err != nil {
		return err
	}
	hadPublishedPublic := published != nil && strings.TrimSpace(published.SwarmID) == defaultPublicSwarmID

	if !modeAllowsShare(runtime.Mode) || activeSwarmID == "" {
		if err := s.unpublishCurrentProvider(ctx, published); err != nil {
			return err
		}
		if hadPublishedPublic {
			return s.removePublicSwarmMembership(ctx)
		}
		return nil
	}

	models, modelErr := s.inference.listModels(ctx)
	wantsPublicMembership := activeSwarmID == defaultPublicSwarmID
	if modelErr != nil || len(models) == 0 {
		if err := s.unpublishCurrentProvider(ctx, published); err != nil {
			return err
		}
		if hadPublishedPublic && !wantsPublicMembership {
			return s.removePublicSwarmMembership(ctx)
		}
		return nil
	}

	shouldAutoPublish := wantsPublicMembership || published != nil
	if !wantsPublicMembership && hadPublishedPublic {
		if err := s.removePublicSwarmMembership(ctx); err != nil {
			return err
		}
	}

	if !shouldAutoPublish {
		return nil
	}

	providerID, providerName := localProviderIdentity()
	memberID, memberName := localMemberIdentity()
	selected := models
	if published != nil && strings.TrimSpace(published.SwarmID) == activeSwarmID && len(published.Models) > 0 {
		filtered := selectModels(models, modelIDs(published.Models))
		if len(filtered) > 0 {
			selected = filtered
		}
	}

	shareMetrics := s.shareMetrics.snapshotValue()
	slotCount := 1
	if published != nil {
		if published.Slots.Total > 0 {
			slotCount = published.Slots.Total
		}
	}
	activeSessions := s.shareMetrics.activeSessionCount()
	activeModel := s.shareMetrics.activeModel()
	maintenanceState := ""
	if published != nil {
		maintenanceState = normalizeMaintenanceState(published.MaintenanceState)
	}
	capacity, status := shareCapacityForActiveSessions(slotCount, activeSessions)
	for idx := range selected {
		selected[idx].SlotsFree = capacity.Free
		selected[idx].SlotsTotal = slotCount
	}

	_, err = s.coordinator.registerProviderWithContext(ctx, registerProviderRequest{
		Provider: provider{
			ID:                     providerID,
			Name:                   providerName,
			SwarmID:                activeSwarmID,
			OwnerMemberID:          memberID,
			OwnerMemberName:        memberName,
			Status:                 status,
			MaintenanceState:       maintenanceState,
			Modes:                  shareModesForRuntime(runtime.Mode),
			Slots:                  capacity,
			ActiveSessions:         activeSessions,
			ActiveModel:            activeModel,
			ServedSessions:         shareMetrics.ServedSessions,
			FailedSessions:         shareMetrics.FailedSessions,
			UploadedTokensEstimate: shareMetrics.UploadedTokensEstimate,
			RecentUploadedTokensPS: shareMetrics.RecentUploadedTokensPS,
			LastServedModel:        shareMetrics.LastServedModel,
			Hardware:               currentHardwareProfile(),
			ClientBuild:            s.cfg.ClientBuild,
			Models:                 selected,
		},
	})
	if err != nil {
		return err
	}
	s.statusCache.clearCoordinatorState()
	if wantsPublicMembership {
		if err := s.ensurePublicSwarmMembership(ctx, runtime); err != nil {
			_, _ = s.coordinator.unregisterProviderWithContext(ctx, providerID)
			return err
		}
	}
	return nil
}

func (s *service) currentPublishedProvider(ctx context.Context) (*provider, error) {
	providerID, _ := localProviderIdentity()
	runtime := s.runtime.Get()
	providersResp, err := s.providersForRuntimeWithContext(ctx, runtime)
	if err != nil {
		return nil, err
	}
	if strings.TrimSpace(runtime.ActiveSwarmID) != "" {
		s.statusCache.storeProviders(runtime.ActiveSwarmID, providersResp, time.Now().UTC())
	}
	for _, candidate := range providersResp.Providers {
		if candidate.ID != providerID {
			continue
		}
		copy := candidate
		return &copy, nil
	}
	return nil, nil
}

func (s *service) unpublishCurrentProvider(ctx context.Context, published *provider) error {
	if published == nil {
		return nil
	}
	providerID, _ := localProviderIdentity()
	_, err := s.coordinator.unregisterProviderWithContext(ctx, providerID)
	var httpErr coordinatorHTTPError
	if err != nil && asCoordinatorHTTPError(err, &httpErr) && httpErr.StatusCode == http.StatusNotFound {
		return nil
	}
	if err == nil {
		s.statusCache.clearCoordinatorState()
	}
	return err
}

func modelIDs(models []model) []string {
	ids := make([]string, 0, len(models))
	for _, current := range models {
		if id := strings.TrimSpace(current.ID); id != "" {
			ids = append(ids, id)
		}
	}
	return ids
}

func selectModels(discovered []model, requestedIDs []string) []model {
	if len(requestedIDs) == 0 {
		return discovered
	}

	selected := make([]model, 0, len(requestedIDs))
	for _, candidate := range discovered {
		if containsString(requestedIDs, candidate.ID) {
			selected = append(selected, candidate)
		}
	}
	return selected
}

func shareModesForRuntime(mode string) []string {
	if mode == "share" {
		return []string{"share"}
	}
	return []string{"share", "both"}
}

func resolveMode(requested string, fallback string) (string, error) {
	mode := strings.TrimSpace(requested)
	if mode == "" {
		mode = strings.TrimSpace(fallback)
	}
	if mode == "" {
		mode = "use"
	}
	switch mode {
	case "use", "share", "both":
		return mode, nil
	default:
		return "", fmt.Errorf("mode must be one of use, share, or both")
	}
}

func localProviderIdentity() (string, string) {
	name := strings.TrimSpace(os.Getenv("ONLYMACS_PROVIDER_NAME"))
	if name == "" {
		_, name = localMemberIdentity()
	}
	return "provider-" + localNodeID(), name
}

func localMemberIdentity() (string, string) {
	return "member-" + localNodeID(), localIdentityName()
}

func slugify(value string) string {
	var builder strings.Builder
	for _, r := range strings.ToLower(strings.TrimSpace(value)) {
		switch {
		case unicode.IsLetter(r), unicode.IsDigit(r):
			builder.WriteRune(r)
		case r == ' ', r == '-', r == '_', r == '.':
			if builder.Len() > 0 && !strings.HasSuffix(builder.String(), "-") {
				builder.WriteByte('-')
			}
		}
	}

	result := strings.Trim(builder.String(), "-")
	if result == "" {
		return ""
	}
	return result
}

func invalidRequest(code string, message string) map[string]any {
	return map[string]any{
		"error": map[string]any{
			"code":    code,
			"message": message,
		},
	}
}

func defaultValue(value string, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

func normalizeMaintenanceState(state string) string {
	switch strings.ToLower(strings.TrimSpace(state)) {
	case "installing_model", "installing-model", "model_install", "model-install", "downloading_model", "downloading-model":
		return "installing_model"
	case "importing_model", "importing-model":
		return "importing_model"
	case "updating_app", "updating-app", "app_update", "app-update":
		return "updating_app"
	case "serving", "idle", "ready", "available", "none":
		return ""
	default:
		return strings.Join(strings.Fields(strings.TrimSpace(state)), " ")
	}
}

func containsString(items []string, target string) bool {
	for _, item := range items {
		if item == target {
			return true
		}
	}
	return false
}

func localNodeID() string {
	if override := slugify(os.Getenv("ONLYMACS_NODE_ID")); override != "" {
		return override
	}

	nodeIDOnce.Do(func() {
		nodeID := readOrCreateNodeID()
		nodeIDMu.Lock()
		cachedNodeID = nodeID
		nodeIDMu.Unlock()
	})

	nodeIDMu.Lock()
	nodeID := cachedNodeID
	nodeIDMu.Unlock()
	if nodeID == "" {
		return "local-node"
	}
	return nodeID
}

func readOrCreateNodeID() string {
	path, err := nodeIDPath()
	if err != nil {
		return ""
	}

	if data, readErr := os.ReadFile(path); readErr == nil { // #nosec G304 -- node id path is derived from the user config directory.
		if existing := slugify(string(data)); existing != "" {
			return existing
		}
	}

	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return ""
	}

	buffer := make([]byte, 8)
	if _, err := rand.Read(buffer); err != nil {
		return ""
	}
	generated := hex.EncodeToString(buffer)
	if writeErr := os.WriteFile(path, []byte(generated), 0o600); writeErr != nil {
		return generated
	}
	return generated
}

func rotateLocalNodeIDForRecovery() (string, bool) {
	if slugify(os.Getenv("ONLYMACS_NODE_ID")) != "" {
		return "", false
	}
	path, err := nodeIDPath()
	if err != nil {
		return "", false
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return "", false
	}
	buffer := make([]byte, 8)
	if _, err := rand.Read(buffer); err != nil {
		return "", false
	}
	generated := hex.EncodeToString(buffer)
	if err := os.WriteFile(path, []byte(generated), 0o600); err != nil {
		return "", false
	}
	nodeIDMu.Lock()
	cachedNodeID = generated
	nodeIDMu.Unlock()
	return generated, true
}

func nodeIDPath() (string, error) {
	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(configDir, "OnlyMacs", "node-id"), nil
}

func writeCoordinatorError(w http.ResponseWriter, err error, notFoundCode string, notFoundMessage string) {
	var httpErr coordinatorHTTPError
	if asCoordinatorHTTPError(err, &httpErr) {
		switch httpErr.StatusCode {
		case http.StatusNotFound:
			writeJSON(w, http.StatusNotFound, invalidRequest(notFoundCode, notFoundMessage))
			return
		case http.StatusGone:
			writeJSON(w, http.StatusGone, invalidRequest("INVITE_EXPIRED", "invite token has expired; create a fresh invite"))
			return
		case http.StatusBadRequest:
			writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_REQUEST", httpErr.Message))
			return
		case http.StatusConflict:
			writeJSON(w, http.StatusConflict, invalidRequest("COORDINATOR_CONFLICT", httpErr.Message))
			return
		}
	}

	writeJSON(w, http.StatusBadGateway, invalidRequest("COORDINATOR_UNAVAILABLE", err.Error()))
}
