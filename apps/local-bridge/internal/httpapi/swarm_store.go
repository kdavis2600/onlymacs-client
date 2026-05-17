package httpapi

import (
	"fmt"
	"sort"
	"strings"
	"time"
)

func (s *swarmStore) activeSessionCount() int {
	s.mu.RLock()
	defer s.mu.RUnlock()

	total := 0
	for _, session := range s.sessions {
		if session.Status == "running" {
			total++
		}
	}
	return total
}

func (s *swarmStore) queuedSessionCount() int {
	s.mu.RLock()
	defer s.mu.RUnlock()

	total := 0
	for _, session := range s.sessions {
		if session.Status == "queued" {
			total++
		}
	}
	return total
}

func (s *swarmStore) activeReservations() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.activeReservationsLocked()
}

func (s *swarmStore) activeReservationsForWorkspace(workspaceID string) int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.activeReservationsForWorkspaceLocked(workspaceID)
}

func (s *swarmStore) activeReservationsForThread(workspaceID string, threadID string) int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.activeReservationsForThreadLocked(workspaceID, threadID)
}

func (s *swarmStore) queueDepth() int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.queueDepthLocked()
}

func (s *swarmStore) queuedSessionsForWorkspace(workspaceID string) int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.queuedSessionsForWorkspaceLocked(workspaceID)
}

func (s *swarmStore) queuedSessionsForThread(workspaceID string, threadID string) int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.queuedSessionsForThreadLocked(workspaceID, threadID)
}

func (s *swarmStore) premiumSessionsForWorkspace(workspaceID string) int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.premiumSessionsForWorkspaceLocked(workspaceID)
}

func (s *swarmStore) premiumSessionsForThread(workspaceID string, threadID string) int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.premiumSessionsForThreadLocked(workspaceID, threadID)
}

func (s *swarmStore) recentPremiumCooldownForWorkspace(workspaceID string, now time.Time) int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.recentPremiumCooldownForWorkspaceLocked(workspaceID, now)
}

func (s *swarmStore) recentPremiumCooldownForThread(workspaceID string, threadID string, now time.Time) int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.recentPremiumCooldownForThreadLocked(workspaceID, threadID, now)
}

func (s *swarmStore) maxPremiumCooldownRemaining(workspaceID string, threadID string, now time.Time) int {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.maxPremiumCooldownRemainingLocked(workspaceID, threadID, now)
}

func (s *swarmStore) queueSummary() swarmQueueSummary {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return summarizeQueueSessionsLocked(s.sessions)
}

func (s *swarmStore) reapStaleQueuedSessions(now time.Time) int {
	s.mu.Lock()
	defer s.mu.Unlock()

	reaped := 0
	for id, session := range s.sessions {
		if session.Status != "queued" || !isStaleQueuedSession(session, now) {
			continue
		}
		session.Status = "cancelled"
		session.QueueRemainder = 0
		session.QueuePosition = 0
		session.QueueReason = "stale_queue"
		session.ETASeconds = 0
		session.Reservations = nil
		session.PreferredProviders = nil
		session.Warnings = uniqueStrings(append(session.Warnings, "OnlyMacs cancelled this queued swarm after it sat in queue too long. Start it again if you still want fresh capacity."))
		session.Checkpoint = &swarmCheckpoint{
			Status:        "cancelled",
			Partial:       false,
			OutputBytes:   0,
			OutputPreview: "OnlyMacs cancelled this queued swarm after it went stale in the queue.",
			UpdatedAt:     now,
		}
		session.UpdatedAt = now
		s.sessions[id] = session
		if session.IdempotencyKey != "" {
			delete(s.idempotency, session.IdempotencyKey)
		}
		reaped++
	}
	return reaped
}

func (s *swarmStore) savedTokensEstimate() int {
	s.mu.RLock()
	defer s.mu.RUnlock()

	total := 0
	for _, session := range s.sessions {
		total += session.SavedTokensEstimate
	}
	return total
}

func (s *swarmStore) list(sessionID string, queueOnly bool) []swarmSessionSummary {
	s.mu.RLock()
	defer s.mu.RUnlock()

	sessions := make([]swarmSessionSummary, 0, len(s.sessions))
	for _, session := range s.sessions {
		if sessionID != "" && session.ID != sessionID {
			continue
		}
		if queueOnly && session.Status != "queued" {
			continue
		}
		sessions = append(sessions, session)
	}

	sort.Slice(sessions, func(i, j int) bool {
		return sessions[i].CreatedAt.Before(sessions[j].CreatedAt)
	})
	return sessions
}

func (s *swarmStore) recent(limit int) []swarmSessionSummary {
	s.mu.RLock()
	defer s.mu.RUnlock()

	sessions := make([]swarmSessionSummary, 0, len(s.sessions))
	for _, session := range s.sessions {
		sessions = append(sessions, session)
	}

	sort.Slice(sessions, func(i, j int) bool {
		if sessions[i].UpdatedAt.Equal(sessions[j].UpdatedAt) {
			return sessions[i].CreatedAt.After(sessions[j].CreatedAt)
		}
		return sessions[i].UpdatedAt.After(sessions[j].UpdatedAt)
	})

	if limit > 0 && len(sessions) > limit {
		sessions = sessions[:limit]
	}
	return sessions
}

func (s *swarmStore) get(sessionID string) (swarmSessionSummary, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	session, ok := s.sessions[sessionID]
	return session, ok
}

func (s *swarmStore) existingByIdempotency(key string) (swarmSessionSummary, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	key = strings.TrimSpace(key)
	if key == "" {
		return swarmSessionSummary{}, false
	}
	sessionID, ok := s.idempotency[key]
	if !ok {
		return swarmSessionSummary{}, false
	}
	session, ok := s.sessions[sessionID]
	if !ok || isTerminalSwarmStatus(session.Status) {
		return swarmSessionSummary{}, false
	}
	return session, true
}

func (s *swarmStore) create(plan swarmPlanResponse, req swarmPlanRequest) swarmSessionSummary {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.nextID++
	sessionID := fmt.Sprintf("swarm-%06d", s.nextID)
	now := time.Now().UTC()
	status := "queued"
	if plan.AdmittedAgents > 0 {
		status = "running"
	}
	session := swarmSessionSummary{
		ID:                   sessionID,
		SwarmID:              plan.SwarmID,
		Title:                plan.Title,
		Status:               status,
		RequestedModel:       plan.RequestedModel,
		ResolvedModel:        plan.ResolvedModel,
		RouteScope:           plan.RouteScope,
		Strategy:             plan.Strategy,
		SelectionReason:      plan.SelectionReason,
		SelectionExplanation: plan.SelectionExplanation,
		PreferRemote:         plan.PreferRemote,
		PreferRemoteSoft:     plan.PreferRemoteSoft,
		RequestedAgents:      plan.RequestedAgents,
		MaxAgents:            plan.MaxAgents,
		AdmittedAgents:       plan.AdmittedAgents,
		QueueRemainder:       plan.QueueRemainder,
		QueuePosition:        plan.QueuePosition,
		QueueReason:          plan.QueueReason,
		ETASeconds:           plan.ETASeconds,
		Scheduling:           plan.Scheduling,
		WorkspaceID:          plan.WorkspaceID,
		ThreadID:             plan.ThreadID,
		IdempotencyKey:       plan.IdempotencyKey,
		ExecutionBoundary:    plan.ExecutionBoundary,
		Context:              plan.Context,
		CapabilityMatrix:     append([]swarmCapabilityRow(nil), plan.CapabilityMatrix...),
		WorkerRoles:          append([]swarmWorkerRole(nil), plan.WorkerRoles...),
		Quorum:               plan.Quorum,
		OnlyMacsArtifact:     req.OnlyMacsArtifact,
		Warnings:             append([]string(nil), plan.Warnings...),
		Prompt:               req.Prompt,
		Messages:             append([]chatMessage(nil), req.Messages...),
		CreatedAt:            now,
		UpdatedAt:            now,
	}
	s.sessions[session.ID] = session
	if session.IdempotencyKey != "" {
		s.idempotency[session.IdempotencyKey] = session.ID
	}
	return session
}

func (s *swarmStore) update(session swarmSessionSummary) swarmSessionSummary {
	s.mu.Lock()
	defer s.mu.Unlock()

	session.UpdatedAt = time.Now().UTC()
	s.sessions[session.ID] = session
	if session.IdempotencyKey != "" {
		if isTerminalSwarmStatus(session.Status) {
			delete(s.idempotency, session.IdempotencyKey)
		} else {
			s.idempotency[session.IdempotencyKey] = session.ID
		}
	}
	return session
}

func (s *swarmStore) activeReservationsLocked() int {
	total := 0
	for _, session := range s.sessions {
		if session.Status == "running" {
			total += len(session.Reservations)
		}
	}
	return total
}

func (s *swarmStore) activeReservationsForWorkspaceLocked(workspaceID string) int {
	if strings.TrimSpace(workspaceID) == "" {
		return 0
	}
	total := 0
	for _, session := range s.sessions {
		if session.Status == "running" && session.WorkspaceID == workspaceID {
			total += len(session.Reservations)
		}
	}
	return total
}

func (s *swarmStore) activeReservationsForThreadLocked(workspaceID string, threadID string) int {
	if strings.TrimSpace(workspaceID) == "" || strings.TrimSpace(threadID) == "" {
		return 0
	}
	total := 0
	for _, session := range s.sessions {
		if session.Status == "running" && session.WorkspaceID == workspaceID && session.ThreadID == threadID {
			total += len(session.Reservations)
		}
	}
	return total
}

func (s *swarmStore) queueDepthLocked() int {
	total := 0
	for _, session := range s.sessions {
		if session.Status == "queued" {
			total++
		}
	}
	return total
}

func (s *swarmStore) queuedSessionsForWorkspaceLocked(workspaceID string) int {
	if strings.TrimSpace(workspaceID) == "" {
		return 0
	}
	total := 0
	for _, session := range s.sessions {
		if session.Status == "queued" && session.WorkspaceID == workspaceID {
			total++
		}
	}
	return total
}

func (s *swarmStore) queuedSessionsForThreadLocked(workspaceID string, threadID string) int {
	if strings.TrimSpace(workspaceID) == "" || strings.TrimSpace(threadID) == "" {
		return 0
	}
	total := 0
	for _, session := range s.sessions {
		if session.Status == "queued" && session.WorkspaceID == workspaceID && session.ThreadID == threadID {
			total++
		}
	}
	return total
}

func (s *swarmStore) premiumSessionsForWorkspaceLocked(workspaceID string) int {
	if strings.TrimSpace(workspaceID) == "" {
		return 0
	}
	total := 0
	for _, session := range s.sessions {
		if session.WorkspaceID == workspaceID && isPremiumSwarmSession(session) {
			total++
		}
	}
	return total
}

func (s *swarmStore) premiumSessionsForThreadLocked(workspaceID string, threadID string) int {
	if strings.TrimSpace(workspaceID) == "" || strings.TrimSpace(threadID) == "" {
		return 0
	}
	total := 0
	for _, session := range s.sessions {
		if session.WorkspaceID == workspaceID && session.ThreadID == threadID && isPremiumSwarmSession(session) {
			total++
		}
	}
	return total
}

func (s *swarmStore) recentPremiumCooldownForWorkspaceLocked(workspaceID string, now time.Time) int {
	if strings.TrimSpace(workspaceID) == "" {
		return 0
	}
	total := 0
	for _, session := range s.sessions {
		if session.WorkspaceID == workspaceID && isRecentPremiumCooldownSession(session, now) {
			total++
		}
	}
	return total
}

func (s *swarmStore) recentPremiumCooldownForThreadLocked(workspaceID string, threadID string, now time.Time) int {
	if strings.TrimSpace(workspaceID) == "" || strings.TrimSpace(threadID) == "" {
		return 0
	}
	total := 0
	for _, session := range s.sessions {
		if session.WorkspaceID == workspaceID && session.ThreadID == threadID && isRecentPremiumCooldownSession(session, now) {
			total++
		}
	}
	return total
}

func (s *swarmStore) maxPremiumCooldownRemainingLocked(workspaceID string, threadID string, now time.Time) int {
	maxRemaining := 0
	for _, session := range s.sessions {
		if strings.TrimSpace(workspaceID) != "" && session.WorkspaceID != workspaceID {
			continue
		}
		if strings.TrimSpace(threadID) != "" && session.ThreadID != threadID {
			continue
		}
		if !isRecentPremiumCooldownSession(session, now) {
			continue
		}
		remaining := int(premiumCooldownAfterRelease.Seconds()) - int(now.Sub(session.UpdatedAt).Seconds())
		if remaining > maxRemaining {
			maxRemaining = remaining
		}
	}
	return maxInt(0, maxRemaining)
}
