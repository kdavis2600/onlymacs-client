package httpapi

import (
	"fmt"
	"strings"
	"time"
)

func pluralSuffix(count int) string {
	if count == 1 {
		return ""
	}
	return "s"
}

func normalizeRouteScope(scope string) string {
	switch strings.ToLower(strings.TrimSpace(scope)) {
	case routeScopeLocalOnly, "local-only", "local":
		return routeScopeLocalOnly
	case routeScopeTrustedOnly, "trusted-only", "trusted":
		return routeScopeTrustedOnly
	default:
		return routeScopeSwarm
	}
}

func executionBoundaryForRouteScope(scope string) string {
	switch normalizeRouteScope(scope) {
	case routeScopeLocalOnly:
		return "requester_local_only"
	case routeScopeTrustedOnly:
		return "requester_trusted_only"
	default:
		return "requester_swarm"
	}
}

func routeScopeSelectionDetail(scope string) string {
	switch normalizeRouteScope(scope) {
	case routeScopeLocalOnly:
		return "Route scope: This Mac only."
	case routeScopeTrustedOnly:
		return "Route scope: your Macs only."
	default:
		return ""
	}
}

func routePreferenceSelectionDetail(scope string, preferRemote bool, preferRemoteSoft bool) string {
	if preferRemote && normalizeRouteScope(scope) == routeScopeSwarm {
		return "Route preference: other Macs only for this request."
	}
	if preferRemoteSoft && normalizeRouteScope(scope) == routeScopeSwarm {
		return "Route preference: prefer the swarm before This Mac for this request."
	}
	return ""
}

func scopedRouteSummary(summary string, routeScope string) string {
	summary = strings.TrimSpace(summary)
	switch normalizeRouteScope(routeScope) {
	case routeScopeLocalOnly:
		if summary == "" {
			return "Route scope: This Mac only."
		}
		return "Route scope: This Mac only. " + summary
	case routeScopeTrustedOnly:
		if summary == "" {
			return "Route scope: your Macs only."
		}
		return "Route scope: your Macs only. " + summary
	default:
		return summary
	}
}

func localProviderIDForRoute() string {
	providerID, _ := localProviderIdentity()
	return providerID
}

func normalizedProviderIDs(providerIDs []string) []string {
	if len(providerIDs) == 0 {
		return nil
	}
	seen := make(map[string]struct{}, len(providerIDs))
	normalized := make([]string, 0, len(providerIDs))
	for _, providerID := range providerIDs {
		trimmed := strings.TrimSpace(providerID)
		if trimmed == "" {
			continue
		}
		if _, exists := seen[trimmed]; exists {
			continue
		}
		seen[trimmed] = struct{}{}
		normalized = append(normalized, trimmed)
	}
	if len(normalized) == 0 {
		return nil
	}
	return normalized
}

func excludedProviderIDsForRoute(scope string, preferRemote bool) []string {
	if !preferRemote || normalizeRouteScope(scope) != routeScopeSwarm {
		return nil
	}
	return normalizedProviderIDs([]string{localProviderIDForRoute()})
}

func avoidedProviderIDsForRoute(scope string, preferRemote bool, preferRemoteSoft bool) []string {
	if preferRemote || !preferRemoteSoft || normalizeRouteScope(scope) != routeScopeSwarm {
		return nil
	}
	return normalizedProviderIDs([]string{localProviderIDForRoute()})
}

func providerPreferenceIDsForRoute(scope string, preferRemote bool, preferRemoteSoft bool, requestedAvoidProviderIDs []string, requestedExcludeProviderIDs []string) ([]string, []string) {
	avoidProviderIDs := normalizedProviderIDs(append(avoidedProviderIDsForRoute(scope, preferRemote, preferRemoteSoft), requestedAvoidProviderIDs...))
	excludeProviderIDs := normalizedProviderIDs(append(excludedProviderIDsForRoute(scope, preferRemote), requestedExcludeProviderIDs...))
	return avoidProviderIDs, excludeProviderIDs
}

func normalizeSwarmPlanRequest(req swarmPlanRequest) swarmPlanRequest {
	req.Title = strings.TrimSpace(req.Title)
	req.Model = normalizeOpenAICompatibleModelAlias(req.Model)
	req.RouteScope = normalizeRouteScope(req.RouteScope)
	req.Strategy = normalizeSwarmStrategy(req.Strategy)
	req.RouteProviderID = strings.TrimSpace(req.RouteProviderID)
	req.WorkspaceID = strings.TrimSpace(req.WorkspaceID)
	req.ThreadID = strings.TrimSpace(req.ThreadID)
	req.IdempotencyKey = strings.TrimSpace(req.IdempotencyKey)
	req.Prompt = strings.TrimSpace(req.Prompt)
	if req.RequestedAgents <= 0 {
		req.RequestedAgents = defaultRequestedAgents
	}
	if req.MaxAgents <= 0 || req.MaxAgents > req.RequestedAgents {
		req.MaxAgents = req.RequestedAgents
	}
	req.Scheduling = strings.ToLower(strings.TrimSpace(req.Scheduling))
	if req.Scheduling != "sticky" {
		req.Scheduling = "elastic"
	}
	if req.RouteScope != routeScopeSwarm {
		req.PreferRemote = false
		req.PreferRemoteSoft = false
	}
	if req.PreferRemote {
		req.PreferRemoteSoft = false
	}
	if req.RouteScope == routeScopeLocalOnly && req.RouteProviderID == "" {
		req.RouteProviderID = localProviderIDForRoute()
	}
	return req
}

func normalizeSwarmStrategy(strategy string) string {
	switch strings.ToLower(strings.TrimSpace(strategy)) {
	case "go_wide", "go-wide", "wide", "fanout", "fan-out", "parallel":
		return "go_wide"
	case "remote_first", "remote-first", "remote":
		return "remote_first"
	case "local_first", "local-first", "local":
		return "local_first"
	case "trusted_only", "trusted-only", "trusted":
		return "trusted_only"
	case "offload_max", "offload-max", "offload":
		return "offload_max"
	case "", "single", "single_best", "best":
		return "single_best"
	default:
		normalized := strings.ToLower(strings.TrimSpace(strategy))
		normalized = strings.ReplaceAll(normalized, "-", "_")
		return strings.Join(strings.Fields(normalized), "_")
	}
}

func deriveSwarmTitle(prompt string) string {
	prompt = strings.TrimSpace(prompt)
	if prompt == "" {
		return ""
	}
	prompt = strings.Join(strings.Fields(prompt), " ")
	if len(prompt) <= 48 {
		return prompt
	}
	return strings.TrimSpace(prompt[:45]) + "..."
}

func sensitiveRouteWarning(req swarmPlanRequest) string {
	if normalizeRouteScope(req.RouteScope) != routeScopeSwarm {
		return ""
	}
	if !swarmPromptLooksSensitive(req.Prompt, req.Messages) {
		return ""
	}
	return "This request looks sensitive and the current route can leave your trusted Macs. Consider `local-first` to keep it on This Mac or `trusted-only` / `offload-max` to keep it on your Macs."
}

func premiumMisuseWarning(req swarmPlanRequest, plan swarmPlanResponse) string {
	if !swarmPromptLooksTrivial(req.Prompt, req.Messages) {
		return ""
	}
	requested := strings.TrimSpace(req.Model)
	resolved := strings.TrimSpace(plan.ResolvedModel)
	if !looksPremiumModelID(requested) && !looksPremiumModelID(resolved) && strings.TrimSpace(plan.SelectionReason) != "scarce_premium_fallback" {
		return ""
	}
	return "This request looks lightweight for a scarce premium or beast-capacity slot. Consider the plain path or `offload-max` unless the stronger model truly matters."
}

func swarmPromptLooksSensitive(prompt string, messages []chatMessage) bool {
	return requestPolicyLooksSensitive(prompt, messages)
}

func swarmPromptLooksTrivial(prompt string, messages []chatMessage) bool {
	return requestPolicyLooksTrivial(prompt, messages)
}

func requesterQueueBudgetWarning(req swarmPlanRequest, workspaceQueued int, threadQueued int) (string, string) {
	if req.ThreadID != "" && threadQueued >= defaultThreadQueueBudget {
		return fmt.Sprintf("OnlyMacs already has %d queued swarm%s for this thread. Let one start, or pause/cancel an older queued swarm first.", threadQueued, pluralSuffix(threadQueued)), "requester_budget"
	}
	if req.WorkspaceID != "" && workspaceQueued >= defaultWorkspaceQueueBudget {
		return fmt.Sprintf("OnlyMacs already has %d queued swarm%s for this workspace. Let one start, or pause/cancel an older queued swarm first.", workspaceQueued, pluralSuffix(workspaceQueued)), "requester_budget"
	}
	return "", ""
}

func requesterMemberCapWarning(req swarmPlanRequest, activeReservations int, reservationCap int) (string, string) {
	if normalizeRouteScope(req.RouteScope) != routeScopeSwarm || reservationCap <= 0 || activeReservations < reservationCap {
		return "", ""
	}
	return fmt.Sprintf("OnlyMacs already has %d live request slot%s in this swarm for this member. Let one finish, or switch this ask to `local-first` / `trusted-only` if it does not need the broader swarm right now.", activeReservations, pluralSuffix(activeReservations)), "member_cap"
}

func premiumQueueBudgetWarning(req swarmPlanRequest, plan swarmPlanResponse, workspacePremium int, threadPremium int) (string, string) {
	if !isPremiumContentionRequest(plan) {
		return "", ""
	}
	if req.ThreadID != "" && threadPremium >= defaultThreadPremiumBudget {
		return fmt.Sprintf("OnlyMacs already has %d scarce premium swarm%s active or queued for this thread. Let that run first, or switch this ask to the plain path / offload-max unless the same strong model truly matters.", threadPremium, pluralSuffix(threadPremium)), "premium_budget"
	}
	if req.WorkspaceID != "" && workspacePremium >= defaultWorkspacePremiumBudget {
		return fmt.Sprintf("OnlyMacs already has %d scarce premium swarm%s active or queued for this workspace. Let an existing premium ask clear before stacking another one.", workspacePremium, pluralSuffix(workspacePremium)), "premium_budget"
	}
	return "", ""
}

func premiumCooldownWarning(req swarmPlanRequest, plan swarmPlanResponse, workspaceCooldown int, threadCooldown int) (string, string) {
	if !isPremiumContentionRequest(plan) {
		return "", ""
	}
	if req.ThreadID != "" && threadCooldown > 0 {
		return "OnlyMacs just released a scarce premium swarm for this thread. Resume that swarm if continuity matters, or give the rare slot a moment before launching another one.", "premium_cooldown"
	}
	if req.WorkspaceID != "" && workspaceCooldown > 0 {
		return "OnlyMacs just released scarce premium work for this workspace. Give the rare slot a moment to clear, or move the next ask onto the plain path / offload-max unless it truly needs the same premium model.", "premium_cooldown"
	}
	return "", ""
}

func estimateSwarmContext(req swarmPlanRequest) swarmContextEstimate {
	inputBytes := len(req.Prompt)
	for _, message := range req.Messages {
		inputBytes += len(message.Role)
		inputBytes += len(message.Content)
	}
	inputBytes += estimateOnlyMacsArtifactBytes(req.OnlyMacsArtifact)
	if inputBytes == 0 {
		inputBytes = len(req.Model)
	}

	estimatedTokens := inputBytes / 4
	if estimatedTokens == 0 && inputBytes > 0 {
		estimatedTokens = 1
	}
	fanoutBytes := inputBytes * maxInt(1, req.RequestedAgents)
	estimate := swarmContextEstimate{
		InputBytes:      inputBytes,
		EstimatedTokens: estimatedTokens,
		FanoutBytes:     fanoutBytes,
	}
	if inputBytes > maxSwarmInputBytes {
		estimate.ExceedsBudget = true
		estimate.LimitReason = "input_bytes"
	}
	if fanoutBytes > maxSwarmFanoutBytes {
		estimate.ExceedsBudget = true
		estimate.LimitReason = "fanout_bytes"
	}
	return estimate
}

func firstAvailableModel(models []model) model {
	if len(models) == 0 {
		return model{}
	}
	return models[0]
}

func admissionClampReason(requestedAgents int, freeSlots int, memberRemaining int, globalRemaining int, workspaceRemaining int, threadRemaining int, modelAvailable bool, premiumContention bool) string {
	switch {
	case !modelAvailable && premiumContention:
		return "premium_contention"
	case !modelAvailable:
		return "model_unavailable"
	case memberRemaining >= 0 && memberRemaining < requestedAgents:
		return "member_cap"
	case globalRemaining >= 0 && globalRemaining < requestedAgents:
		return "global_cap"
	case workspaceRemaining >= 0 && workspaceRemaining < requestedAgents:
		return "workspace_cap"
	case threadRemaining >= 0 && threadRemaining < requestedAgents:
		return "thread_cap"
	case premiumContention && freeSlots <= 0:
		return "premium_contention"
	case premiumContention && freeSlots < requestedAgents:
		return "premium_contention"
	case freeSlots <= 0:
		return "swarm_capacity"
	case freeSlots < requestedAgents:
		return "swarm_capacity"
	case memberRemaining <= 0:
		return "member_cap"
	case globalRemaining <= 0:
		return "global_cap"
	case workspaceRemaining <= 0:
		return "workspace_cap"
	case threadRemaining <= 0:
		return "thread_cap"
	default:
		return "requested_width"
	}
}

func estimateQueueETA(queuePosition int, freeSlots int, queueReason string) int {
	if queuePosition <= 0 {
		return 0
	}
	baseSeconds := defaultQueueETASeconds
	if queueReason == "premium_contention" {
		baseSeconds = 90
	} else if queueReason == "premium_budget" {
		baseSeconds = 75
	} else if queueReason == "premium_cooldown" {
		baseSeconds = 60
	} else if queueReason == "requester_budget" {
		baseSeconds = 60
	} else if queueReason == "member_cap" {
		baseSeconds = 60
	}
	multiplier := queuePosition
	if freeSlots > 0 {
		multiplier = maxInt(1, queuePosition-1)
	}
	return multiplier * baseSeconds
}

func summarizeQueueSessionsLocked(sessions map[string]swarmSessionSummary) swarmQueueSummary {
	summary := swarmQueueSummary{}
	minETA := 0
	maxETA := 0
	now := time.Now().UTC()

	for _, session := range sessions {
		if session.Status != "queued" {
			continue
		}

		summary.QueuedSessionCount++
		if isStaleQueuedSession(session, now) {
			summary.StaleQueuedCount++
		}
		switch session.QueueReason {
		case "premium_contention":
			summary.PremiumContentionCount++
		case "premium_budget":
			summary.PremiumBudgetCount++
		case "premium_cooldown":
			summary.PremiumCooldownCount++
		case "requester_budget":
			summary.RequesterBudgetCount++
		case "member_cap":
			summary.MemberCapCount++
		case "trust_scope":
			summary.CapacityWaitCount++
		case "requested_width", "workspace_cap", "thread_cap", "global_cap":
			summary.WidthLimitedCount++
		case "swarm_capacity", "model_unavailable":
			summary.CapacityWaitCount++
		}

		if session.ETASeconds > 0 {
			if minETA == 0 || session.ETASeconds < minETA {
				minETA = session.ETASeconds
			}
			if session.ETASeconds > maxETA {
				maxETA = session.ETASeconds
			}
		}
	}

	summary.NextETASeconds = minETA
	summary.MaxETASeconds = maxETA

	switch {
	case summary.PremiumCooldownCount > 0:
		summary.PrimaryReason = "premium_cooldown"
		summary.PrimaryDetail = "A scarce premium slot was just released and OnlyMacs is giving it a short cooldown before another request from the same workspace/thread can grab it."
		summary.SuggestedAction = "Resume the earlier premium swarm if continuity matters, or wait a moment before launching another rare-slot request."
	case summary.PremiumBudgetCount > 0:
		summary.PrimaryReason = "premium_budget"
		summary.PrimaryDetail = "This workspace or thread already has enough scarce premium work in flight. OnlyMacs is holding the next premium ask so one requester does not camp on the rarest capacity."
		summary.SuggestedAction = "Let an existing premium swarm finish, or move lightweight work onto the plain path / offload-max before asking for another rare slot."
	case summary.PremiumContentionCount > 0:
		summary.PrimaryReason = "premium_contention"
		summary.PrimaryDetail = "Rare flagship capacity is tight right now. OnlyMacs may wait for a premium opening or keep swarms moving on the strongest safe fallback."
		summary.SuggestedAction = "Wait for the premium opening if quality matters most, or keep using the strongest fallback to stay moving."
	case summary.MemberCapCount > 0:
		summary.PrimaryReason = "member_cap"
		summary.PrimaryDetail = "This swarm member already has enough live request slots in flight. OnlyMacs is holding the next ask so one requester identity does not quietly monopolize the shared swarm."
		summary.SuggestedAction = "Let one running request finish, or move the next ask onto This Mac / your Macs if it does not need the broader swarm."
	case summary.RequesterBudgetCount > 0:
		summary.PrimaryReason = "requester_budget"
		summary.PrimaryDetail = "This workspace or thread already has enough queued swarms waiting. OnlyMacs is holding the next one so a single requester does not bury the swarm."
		summary.SuggestedAction = "Let an older queued swarm start, or pause/cancel stale queued work before launching more."
	case hasQueuedReason(sessions, "trust_scope"):
		summary.PrimaryReason = "trust_scope"
		summary.PrimaryDetail = "The selected trust scope is tighter than the open capacity right now. OnlyMacs is waiting for a matching model inside that safer route."
		summary.SuggestedAction = "Keep the safer route, or widen the route scope if this task does not need to stay on your Macs."
	case summary.CapacityWaitCount > 0:
		summary.PrimaryReason = "swarm_capacity"
		summary.PrimaryDetail = "The swarm is saturated right now. Queued swarms will start as slots open."
		summary.SuggestedAction = "Keep the queue running, or add more shared capacity from This Mac or a friend."
	case summary.WidthLimitedCount > 0:
		summary.PrimaryReason = "requested_width"
		summary.PrimaryDetail = "OnlyMacs intentionally narrowed at least one swarm so the workspace, thread, and swarm stay healthy."
		summary.SuggestedAction = "Keep the current width, or request fewer agents if you want new swarms to start sooner."
	}

	if summary.StaleQueuedCount > 0 {
		staleDetail := fmt.Sprintf("%d queued swarm%s has been waiting long enough that it may be worth refreshing the route.", summary.StaleQueuedCount, pluralSuffix(summary.StaleQueuedCount))
		if summary.PrimaryDetail == "" {
			summary.PrimaryReason = "stale_queue"
			summary.PrimaryDetail = staleDetail
			summary.SuggestedAction = "Pause/resume or cancel/restart stale swarms if the route or model should be refreshed."
		} else {
			summary.PrimaryDetail = summary.PrimaryDetail + " " + staleDetail
			summary.SuggestedAction = summary.SuggestedAction + " Pause/resume or cancel/restart stale swarms if the route or model should be refreshed."
		}
	}

	return summary
}

func isStaleQueuedSession(session swarmSessionSummary, now time.Time) bool {
	if session.Status != "queued" {
		return false
	}
	if session.UpdatedAt.IsZero() {
		return false
	}
	return now.Sub(session.UpdatedAt) >= staleQueuedSessionAfter
}

func hasQueuedReason(sessions map[string]swarmSessionSummary, reason string) bool {
	for _, session := range sessions {
		if session.Status == "queued" && session.QueueReason == reason {
			return true
		}
	}
	return false
}

func isPremiumContentionRequest(plan swarmPlanResponse) bool {
	if strings.TrimSpace(plan.SelectionReason) == "scarce_premium_fallback" {
		return true
	}
	return looksPremiumModelID(plan.RequestedModel) || looksPremiumModelID(plan.ResolvedModel)
}

func isPremiumSwarmSession(session swarmSessionSummary) bool {
	if session.Status != "queued" && session.Status != "running" {
		return false
	}
	if session.QueueReason == "premium_budget" || session.QueueReason == "premium_contention" {
		return true
	}
	if strings.TrimSpace(session.SelectionReason) == "scarce_premium_fallback" {
		return true
	}
	return looksPremiumModelID(session.RequestedModel) || looksPremiumModelID(session.ResolvedModel)
}

func isRecentPremiumCooldownSession(session swarmSessionSummary, now time.Time) bool {
	if session.Status != "paused" && session.Status != "cancelled" {
		return false
	}
	if session.UpdatedAt.IsZero() {
		return false
	}
	if now.Sub(session.UpdatedAt) > premiumCooldownAfterRelease {
		return false
	}
	if strings.TrimSpace(session.QueueReason) != "manual_pause" && strings.TrimSpace(session.QueueReason) != "cancelled" {
		return false
	}
	if strings.TrimSpace(session.SelectionReason) == "scarce_premium_fallback" {
		return true
	}
	return looksPremiumModelID(session.RequestedModel) || looksPremiumModelID(session.ResolvedModel)
}

func resumeContinuityWarning(requestedModel string, previousResolvedModel string, plan swarmPlanResponse) string {
	requestedModel = strings.TrimSpace(requestedModel)
	previousResolvedModel = strings.TrimSpace(previousResolvedModel)
	currentResolvedModel := strings.TrimSpace(plan.ResolvedModel)
	if previousResolvedModel == "" || currentResolvedModel == "" || previousResolvedModel == currentResolvedModel {
		return ""
	}
	if requestedModel != "" {
		return fmt.Sprintf("Resume could not keep %s. OnlyMacs reopened this swarm on %s instead.", requestedModel, currentResolvedModel)
	}
	if looksPremiumModelID(previousResolvedModel) || looksPremiumModelID(currentResolvedModel) || strings.TrimSpace(plan.SelectionReason) == "scarce_premium_fallback" {
		return fmt.Sprintf("Resume reopened this swarm on %s because the earlier premium model was not still open.", currentResolvedModel)
	}
	return ""
}

func looksPremiumModelID(modelID string) bool {
	modelID = strings.ToLower(strings.TrimSpace(modelID))
	if modelID == "" {
		return false
	}
	for _, marker := range []string{
		"maverick",
		"405b",
		"400b",
		"235b",
		"236b",
		"120b",
		"110b",
		"90b",
		"72b",
		"70b",
		"qwq-32b",
		"gemma-4-31b",
	} {
		if strings.Contains(modelID, marker) {
			return true
		}
	}
	return false
}

func estimateSavedTokens(contextTokens int, admittedAgents int) int {
	if contextTokens <= 0 || admittedAgents <= 0 {
		return 0
	}
	return contextTokens * admittedAgents
}

func isTerminalSwarmStatus(status string) bool {
	switch status {
	case "cancelled", "completed", "failed":
		return true
	default:
		return false
	}
}

func providerIDsFromReservations(reservations []swarmSessionReservation) []string {
	ids := make([]string, 0, len(reservations))
	for _, reservation := range reservations {
		if reservation.ProviderID == "" {
			continue
		}
		ids = append(ids, reservation.ProviderID)
	}
	return ids
}

func uniqueStrings(items []string) []string {
	seen := make(map[string]struct{}, len(items))
	out := make([]string, 0, len(items))
	for _, item := range items {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		if _, ok := seen[item]; ok {
			continue
		}
		seen[item] = struct{}{}
		out = append(out, item)
	}
	return out
}

func minPositive(values ...int) int {
	initialized := false
	result := 0
	for _, value := range values {
		if value < 0 {
			value = 0
		}
		if !initialized || value < result {
			result = value
			initialized = true
		}
	}
	return result
}

func defaultSelectionReason(requestedModel string, resolvedModel string, selectionReason string) string {
	selectionReason = strings.TrimSpace(selectionReason)
	if selectionReason != "" {
		return selectionReason
	}
	requestedModel = strings.TrimSpace(requestedModel)
	resolvedModel = strings.TrimSpace(resolvedModel)
	switch {
	case requestedModel != "" && resolvedModel == requestedModel:
		return "requested_exact"
	case requestedModel == "" && resolvedModel != "":
		return "best_available"
	default:
		return ""
	}
}

func maxInt(left int, right int) int {
	if left > right {
		return left
	}
	return right
}

func runtimeSwarmID(runtime runtimeConfig) string {
	return strings.TrimSpace(runtime.ActiveSwarmID)
}
