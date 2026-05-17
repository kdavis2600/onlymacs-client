package httpapi

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"
)

func (s *service) swarmPlanHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, invalidRequest("METHOD_NOT_ALLOWED", "swarm plan requires POST"))
		return
	}
	s.swarms.reapStaleQueuedSessions(time.Now().UTC())

	var req swarmPlanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_JSON", err.Error()))
		return
	}

	plan, status, errPayload := s.computeSwarmPlan(r, req)
	if errPayload != nil {
		writeJSON(w, status, errPayload)
		return
	}

	writeJSON(w, http.StatusOK, plan)
}

func (s *service) swarmStartHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, invalidRequest("METHOD_NOT_ALLOWED", "swarm start requires POST"))
		return
	}
	s.swarms.reapStaleQueuedSessions(time.Now().UTC())

	var req swarmPlanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_JSON", err.Error()))
		return
	}

	req = normalizeSwarmPlanRequest(req)
	if existing, ok := s.swarms.existingByIdempotency(req.IdempotencyKey); ok {
		writeJSON(w, http.StatusOK, swarmStartResponse{
			Session:   existing,
			Duplicate: true,
		})
		return
	}

	plan, status, errPayload := s.computeSwarmPlan(r, req)
	if errPayload != nil {
		writeJSON(w, status, errPayload)
		return
	}

	session := s.swarms.create(plan, req)
	if session.AdmittedAgents > 0 {
		reservations, preferredProviders, warnings := s.reserveForSwarm(runtimeSwarmID(s.runtime.Get()), session, nil)
		session.Reservations = reservations
		session.PreferredProviders = preferredProviders
		session.RouteSummary = summarizeSwarmRoute(reservations, session.RouteScope)
		session.AdmittedAgents = len(reservations)
		session.SavedTokensEstimate = estimateSavedTokens(session.Context.EstimatedTokens, len(reservations))
		session.QueueRemainder = maxInt(0, session.RequestedAgents-len(reservations))
		if len(reservations) == 0 {
			session.Status = "queued"
		}
		if session.QueueRemainder > 0 && session.QueueReason == "" {
			session.QueueReason = "swarm_capacity"
		}
		if session.QueueRemainder > 0 && session.QueuePosition == 0 {
			session.QueuePosition = s.swarms.queueDepth() + 1
		}
		session.Warnings = append(session.Warnings, warnings...)
		if len(reservations) > 0 {
			session.Checkpoint = &swarmCheckpoint{
				Status:        "running",
				Partial:       session.QueueRemainder > 0,
				OutputBytes:   0,
				OutputPreview: fmt.Sprintf("Swarm session is running on %d provider%s.", len(reservations), pluralSuffix(len(reservations))),
				UpdatedAt:     time.Now().UTC(),
			}
		}
	}

	session = s.swarms.update(session)
	s.maybeStartSwarmExecution(session)
	writeJSON(w, http.StatusCreated, swarmStartResponse{
		Session:   session,
		Duplicate: false,
	})
}

func (s *service) swarmSessionsHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, invalidRequest("METHOD_NOT_ALLOWED", "swarm session listing requires GET"))
		return
	}
	s.swarms.reapStaleQueuedSessions(time.Now().UTC())

	sessionID := strings.TrimSpace(r.URL.Query().Get("session_id"))
	writeJSON(w, http.StatusOK, swarmSessionsResponse{
		Sessions: s.swarms.list(sessionID, false),
	})
}

func (s *service) swarmQueueHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, invalidRequest("METHOD_NOT_ALLOWED", "swarm queue requires GET"))
		return
	}
	s.swarms.reapStaleQueuedSessions(time.Now().UTC())

	sessionID := strings.TrimSpace(r.URL.Query().Get("session_id"))
	writeJSON(w, http.StatusOK, swarmQueueResponse{
		QueuedSessionCount: s.swarms.queuedSessionCount(),
		ActiveSessionCount: s.swarms.activeSessionCount(),
		QueueSummary:       s.swarms.queueSummary(),
		Sessions:           s.swarms.list(sessionID, true),
	})
}

func (s *service) swarmPauseHandler(w http.ResponseWriter, r *http.Request) {
	s.handleSwarmAction(w, r, "paused")
}

func (s *service) swarmResumeHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, invalidRequest("METHOD_NOT_ALLOWED", "swarm resume requires POST"))
		return
	}

	var req swarmSessionActionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_JSON", err.Error()))
		return
	}
	req.SessionID = strings.TrimSpace(req.SessionID)
	if req.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_SESSION", "session_id is required"))
		return
	}

	session, ok := s.swarms.get(req.SessionID)
	if !ok {
		writeJSON(w, http.StatusNotFound, invalidRequest("SESSION_NOT_FOUND", "session could not be found"))
		return
	}
	if session.Status != "paused" && session.Status != "queued" {
		writeJSON(w, http.StatusConflict, invalidRequest("INVALID_SESSION_STATE", "only paused or queued sessions can be resumed"))
		return
	}

	planReq := swarmPlanRequest{
		Model:            defaultValue(session.RequestedModel, session.ResolvedModel),
		RouteScope:       session.RouteScope,
		Strategy:         session.Strategy,
		PreferRemote:     session.PreferRemote,
		PreferRemoteSoft: session.PreferRemoteSoft,
		OnlyMacsArtifact: session.OnlyMacsArtifact,
		RequestedAgents:  session.RequestedAgents,
		MaxAgents:        session.MaxAgents,
		Scheduling:       session.Scheduling,
		WorkspaceID:      session.WorkspaceID,
		ThreadID:         session.ThreadID,
		IdempotencyKey:   session.IdempotencyKey,
		Prompt:           session.Prompt,
		Messages:         append([]chatMessage(nil), session.Messages...),
	}
	plan, status, errPayload := s.computeSwarmPlan(r, planReq)
	if errPayload != nil {
		writeJSON(w, status, errPayload)
		return
	}

	previousResolvedModel := session.ResolvedModel
	session.ResolvedModel = plan.ResolvedModel
	session.SelectionReason = plan.SelectionReason
	session.SelectionExplanation = plan.SelectionExplanation
	session.RouteScope = plan.RouteScope
	session.Strategy = plan.Strategy
	session.AdmittedAgents = plan.AdmittedAgents
	session.QueueRemainder = plan.QueueRemainder
	session.QueuePosition = plan.QueuePosition
	session.QueueReason = plan.QueueReason
	session.ETASeconds = plan.ETASeconds
	reservations, preferredProviders, warnings := s.reserveForSwarm(runtimeSwarmID(s.runtime.Get()), session, session.PreferredProviders)
	session.Reservations = reservations
	session.PreferredProviders = preferredProviders
	session.RouteSummary = summarizeSwarmRoute(reservations, session.RouteScope)
	session.CapabilityMatrix = append([]swarmCapabilityRow(nil), plan.CapabilityMatrix...)
	session.WorkerRoles = append([]swarmWorkerRole(nil), plan.WorkerRoles...)
	session.Quorum = plan.Quorum
	session.AdmittedAgents = len(reservations)
	session.SavedTokensEstimate = maxInt(session.SavedTokensEstimate, estimateSavedTokens(session.Context.EstimatedTokens, len(reservations)))
	session.QueueRemainder = maxInt(0, session.RequestedAgents-len(reservations))
	if len(reservations) > 0 {
		session.Status = "running"
	} else {
		session.Status = "queued"
	}
	session.QueueReason = plan.QueueReason
	session.QueuePosition = plan.QueuePosition
	session.ETASeconds = plan.ETASeconds
	session.Warnings = append(uniqueStrings(plan.Warnings), warnings...)
	if warning := resumeContinuityWarning(session.RequestedModel, previousResolvedModel, plan); warning != "" {
		session.Warnings = append(session.Warnings, warning)
		session.Warnings = uniqueStrings(session.Warnings)
	}
	session.Checkpoint = &swarmCheckpoint{
		Status:        "resumed",
		Partial:       false,
		OutputBytes:   0,
		OutputPreview: "Swarm session resumed and is executing inference work.",
		UpdatedAt:     time.Now().UTC(),
	}
	session = s.swarms.update(session)
	s.maybeStartSwarmExecution(session)
	writeJSON(w, http.StatusOK, swarmStartResponse{
		Session:   session,
		Duplicate: false,
	})
}

func (s *service) swarmCancelHandler(w http.ResponseWriter, r *http.Request) {
	s.handleSwarmAction(w, r, "cancelled")
}

func (s *service) handleSwarmAction(w http.ResponseWriter, r *http.Request, targetStatus string) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, invalidRequest("METHOD_NOT_ALLOWED", "swarm action requires POST"))
		return
	}

	var req swarmSessionActionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_JSON", err.Error()))
		return
	}
	req.SessionID = strings.TrimSpace(req.SessionID)
	if req.SessionID == "" {
		writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_SESSION", "session_id is required"))
		return
	}

	session, ok := s.swarms.get(req.SessionID)
	if !ok {
		writeJSON(w, http.StatusNotFound, invalidRequest("SESSION_NOT_FOUND", "session could not be found"))
		return
	}
	if isTerminalSwarmStatus(session.Status) {
		writeJSON(w, http.StatusConflict, invalidRequest("INVALID_SESSION_STATE", "session is already terminal"))
		return
	}

	s.swarmRuns.cancel(session.ID)
	s.releaseSwarmReservations(session)
	session.Reservations = nil
	session.RouteSummary = ""
	session.AdmittedAgents = 0
	session.Status = targetStatus
	session.QueuePosition = 0
	session.ETASeconds = 0
	if targetStatus == "paused" {
		session.QueueReason = "manual_pause"
		session.Checkpoint = &swarmCheckpoint{
			Status:        "paused",
			Partial:       false,
			OutputBytes:   0,
			OutputPreview: "Swarm session paused before or between inference steps.",
			UpdatedAt:     time.Now().UTC(),
		}
	} else {
		session.QueueReason = "cancelled"
		session.Checkpoint = &swarmCheckpoint{
			Status:        "cancelled",
			Partial:       false,
			OutputBytes:   0,
			OutputPreview: "Swarm session cancelled and reservations were released.",
			UpdatedAt:     time.Now().UTC(),
		}
	}
	session = s.swarms.update(session)
	writeJSON(w, http.StatusOK, swarmStartResponse{
		Session:   session,
		Duplicate: false,
	})
}

func summarizeSwarmRoute(reservations []swarmSessionReservation, routeScope string) string {
	if len(reservations) == 0 {
		return ""
	}

	localProviderID, _ := localProviderIdentity()
	uniqueProviders := make(map[string]string)
	localCount := 0
	remoteCount := 0
	firstRemoteName := ""
	for _, reservation := range reservations {
		if reservation.ProviderID == "" {
			continue
		}
		uniqueProviders[reservation.ProviderID] = reservation.ProviderName
		if reservation.ProviderID == localProviderID {
			localCount++
		} else {
			remoteCount++
			if firstRemoteName == "" {
				firstRemoteName = reservation.ProviderName
			}
		}
	}

	switch {
	case remoteCount == 0:
		return scopedRouteSummary("Running on This Mac.", routeScope)
	case localCount == 0 && len(uniqueProviders) == 1:
		return scopedRouteSummary(fmt.Sprintf("Running on %s.", defaultValue(firstRemoteName, "a remote Mac")), routeScope)
	case localCount == 0:
		return scopedRouteSummary(fmt.Sprintf("Running across %d remote Macs, led by %s.", len(uniqueProviders), defaultValue(firstRemoteName, "the strongest open provider")), routeScope)
	default:
		remoteHosts := len(uniqueProviders)
		if _, ok := uniqueProviders[localProviderID]; ok {
			remoteHosts--
		}
		if remoteHosts <= 0 {
			return scopedRouteSummary("Running on This Mac.", routeScope)
		}
		return scopedRouteSummary(fmt.Sprintf("Running across This Mac and %d remote Mac%s.", remoteHosts, pluralSuffix(remoteHosts)), routeScope)
	}
}

func (s *service) reserveForSwarm(swarmID string, session swarmSessionSummary, preferredProviders []string) ([]swarmSessionReservation, []string, []string) {
	reservations := make([]swarmSessionReservation, 0, session.AdmittedAgents)
	preferredProviders = append([]string(nil), preferredProviders...)
	runtime := s.runtime.Get()
	runtime.ActiveSwarmID = swarmID
	if err := s.ensureActiveSwarmCredential(context.Background(), runtime); err != nil {
		return reservations, uniqueStrings(preferredProviders), []string{err.Error()}
	}
	requesterMemberID, requesterMemberName := localMemberIdentity()
	baseAvoidProviderIDs, baseExcludeProviderIDs := providerPreferenceIDsForRoute(session.RouteScope, session.PreferRemote, session.PreferRemoteSoft, nil, nil)
	for idx := 0; idx < session.AdmittedAgents; idx++ {
		req := reserveSessionRequest{
			Model:               session.ResolvedModel,
			SwarmID:             swarmID,
			RequesterMemberID:   requesterMemberID,
			RequesterMemberName: requesterMemberName,
			RouteScope:          session.RouteScope,
			AvoidProviderIDs:    append([]string(nil), baseAvoidProviderIDs...),
			ExcludeProviderIDs:  append([]string(nil), baseExcludeProviderIDs...),
		}
		if session.RouteScope == routeScopeLocalOnly {
			req.RouteProviderID = localProviderIDForRoute()
		}
		if session.Scheduling == "sticky" && idx < len(preferredProviders) {
			req.PreferredProviderID = preferredProviders[idx]
		} else if session.Scheduling != "sticky" {
			req.AvoidProviderIDs = append(req.AvoidProviderIDs, providerIDsFromReservations(reservations)...)
		}

		reserveResp, err := s.coordinator.reserve(req)
		if err != nil {
			return reservations, uniqueStrings(preferredProviders), []string{fmt.Sprintf("reserved %d of %d requested admitted slots", len(reservations), session.AdmittedAgents)}
		}
		reservations = append(reservations, swarmSessionReservation{
			ReservationID: reserveResp.SessionID,
			ProviderID:    reserveResp.Provider.ID,
			ProviderName:  reserveResp.Provider.Name,
			ModelID:       reserveResp.ResolvedModel,
			Status:        reserveResp.Status,
		})
		if session.Scheduling == "sticky" && !containsString(preferredProviders, reserveResp.Provider.ID) {
			preferredProviders = append(preferredProviders, reserveResp.Provider.ID)
		}
	}

	return reservations, uniqueStrings(providerIDsFromReservations(reservations)), nil
}

func (s *service) releaseSwarmReservations(session swarmSessionSummary) {
	swarmID, requesterMemberID := s.swarmRequesterContext(session)
	requesterMemberName := ""
	if requesterMemberID != "" {
		_, requesterMemberName = localMemberIdentity()
	}
	for _, reservation := range session.Reservations {
		_, _ = s.coordinator.release(releaseSessionRequest{
			SessionID:           reservation.ReservationID,
			SwarmID:             swarmID,
			RequesterMemberID:   requesterMemberID,
			RequesterMemberName: requesterMemberName,
		})
	}
}
