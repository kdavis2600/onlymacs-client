package httpapi

import (
	"fmt"
	"net/http"
	"strings"
	"time"
)

func (s *service) computeSwarmPlan(r *http.Request, rawReq swarmPlanRequest) (swarmPlanResponse, int, map[string]any) {
	runtime := s.runtime.Get()
	if !modeAllowsUse(runtime.Mode) {
		return swarmPlanResponse{}, http.StatusConflict, invalidRequest("MODE_BLOCKED", "requester actions are disabled while the bridge is in share-only mode")
	}
	if runtime.ActiveSwarmID == "" {
		return swarmPlanResponse{}, http.StatusConflict, invalidRequest("NO_ACTIVE_POOL", "no active swarm is selected for requester actions")
	}

	req := normalizeSwarmPlanRequest(rawReq)
	if err := s.ensureActiveSwarmCredential(r.Context(), runtime); err != nil {
		return swarmPlanResponse{}, http.StatusBadGateway, invalidRequest("COORDINATOR_UNAVAILABLE", err.Error())
	}
	requesterMemberID, requesterMemberName := localMemberIdentity()
	contextEstimate := estimateSwarmContext(req)
	if contextEstimate.ExceedsBudget {
		return swarmPlanResponse{}, http.StatusUnprocessableEntity, map[string]any{
			"error": map[string]any{
				"code":    "CONTEXT_TOO_LARGE",
				"message": "request is too large for safe swarm fan-out; summarize or narrow the request first",
				"context": contextEstimate,
			},
		}
	}

	avoidProviderIDs, excludeProviderIDs := providerPreferenceIDsForRoute(req.RouteScope, req.PreferRemote, req.PreferRemoteSoft, nil, nil)
	preflight, err := s.coordinator.preflight(preflightRequest{
		Model:               req.Model,
		SwarmID:             runtime.ActiveSwarmID,
		MaxProviders:        req.MaxAgents,
		RequesterMemberID:   requesterMemberID,
		RequesterMemberName: requesterMemberName,
		RouteScope:          req.RouteScope,
		RouteProviderID:     req.RouteProviderID,
		AvoidProviderIDs:    avoidProviderIDs,
		ExcludeProviderIDs:  excludeProviderIDs,
	})
	if err != nil {
		return swarmPlanResponse{}, http.StatusBadGateway, invalidRequest("COORDINATOR_UNAVAILABLE", err.Error())
	}

	selectionReason := defaultSelectionReason(strings.TrimSpace(req.Model), preflight.ResolvedModel, preflight.SelectionReason)

	plan := swarmPlanResponse{
		SwarmID:              runtime.ActiveSwarmID,
		Title:                defaultValue(strings.TrimSpace(req.Title), deriveSwarmTitle(req.Prompt)),
		RequestedModel:       strings.TrimSpace(req.Model),
		ResolvedModel:        preflight.ResolvedModel,
		RouteScope:           req.RouteScope,
		Strategy:             req.Strategy,
		SelectionReason:      selectionReason,
		SelectionExplanation: preflight.SelectionExplanation,
		Available:            preflight.Available,
		PreferRemote:         req.PreferRemote,
		PreferRemoteSoft:     req.PreferRemoteSoft,
		RequestedAgents:      req.RequestedAgents,
		MaxAgents:            req.MaxAgents,
		Scheduling:           req.Scheduling,
		WorkspaceID:          req.WorkspaceID,
		ThreadID:             req.ThreadID,
		IdempotencyKey:       req.IdempotencyKey,
		ExecutionBoundary:    executionBoundaryForRouteScope(req.RouteScope),
		Context:              contextEstimate,
		Providers:            preflight.Providers,
		AvailableModels:      preflight.AvailableModels,
		Warnings:             nil,
	}
	enrichSwarmPlanExecution(&plan, req)
	if warning := sensitiveRouteWarning(req); warning != "" {
		plan.Warnings = append(plan.Warnings, warning)
	}
	plan.Totals.Providers = preflight.Totals.Providers
	plan.Totals.SlotsFree = preflight.Totals.SlotsFree
	plan.Totals.SlotsTotal = preflight.Totals.SlotsTotal

	if !preflight.Available && req.AllowFallback && len(preflight.AvailableModels) > 0 {
		candidate := firstAvailableModel(preflight.AvailableModels)
		if candidate.ID != "" && candidate.ID != strings.TrimSpace(req.Model) {
			fallbackPreflight, fallbackErr := s.coordinator.preflight(preflightRequest{
				Model:               candidate.ID,
				SwarmID:             runtime.ActiveSwarmID,
				MaxProviders:        req.MaxAgents,
				RequesterMemberID:   requesterMemberID,
				RequesterMemberName: requesterMemberName,
				RouteScope:          req.RouteScope,
				RouteProviderID:     req.RouteProviderID,
				AvoidProviderIDs:    avoidProviderIDs,
				ExcludeProviderIDs:  excludeProviderIDs,
			})
			if fallbackErr == nil && fallbackPreflight.Available {
				preflight = fallbackPreflight
				plan.Available = true
				plan.ResolvedModel = fallbackPreflight.ResolvedModel
				plan.SelectionReason = defaultSelectionReason(candidate.ID, fallbackPreflight.ResolvedModel, fallbackPreflight.SelectionReason)
				plan.SelectionExplanation = fallbackPreflight.SelectionExplanation
				plan.Providers = fallbackPreflight.Providers
				plan.AvailableModels = fallbackPreflight.AvailableModels
				plan.Totals.Providers = fallbackPreflight.Totals.Providers
				plan.Totals.SlotsFree = fallbackPreflight.Totals.SlotsFree
				plan.Totals.SlotsTotal = fallbackPreflight.Totals.SlotsTotal
				enrichSwarmPlanExecution(&plan, req)
				plan.FallbackUsed = true
				plan.Warnings = append(plan.Warnings, fmt.Sprintf("resolved fallback model %s because %s was unavailable", candidate.ID, defaultValue(strings.TrimSpace(req.Model), "the requested default")))
			}
		}
	}
	if req.PreferRemote {
		plan.SelectionExplanation = ""
	}

	if !plan.Available && !plan.FallbackUsed {
		if warning := premiumMisuseWarning(req, plan); warning != "" {
			plan.Warnings = append(plan.Warnings, warning)
		}
		if req.RouteScope != routeScopeSwarm && len(plan.AvailableModels) == 0 {
			plan.QueueReason = "trust_scope"
		} else if len(plan.AvailableModels) == 0 {
			plan.QueueReason = "model_unavailable"
		} else if isPremiumContentionRequest(plan) {
			plan.QueueReason = "premium_contention"
		} else {
			plan.QueueReason = "swarm_capacity"
		}
		plan.QueuePosition = s.swarms.queueDepth() + 1
		plan.ETASeconds = estimateQueueETA(plan.QueuePosition, plan.Totals.SlotsFree, plan.QueueReason)
		plan.SelectionExplanation = explainSwarmSelection(req, plan)
		return plan, http.StatusOK, nil
	}

	freeSlots := plan.Totals.SlotsFree
	memberRemaining := req.MaxAgents
	if preflight.RequesterReservationCap > 0 {
		memberRemaining = maxInt(0, preflight.RequesterReservationCap-preflight.RequesterActiveReservations)
	}
	globalRemaining := maxInt(0, defaultGlobalConcurrency-s.swarms.activeReservations())
	workspaceRemaining := defaultWorkspaceConcurrency
	if req.WorkspaceID != "" {
		workspaceRemaining = maxInt(0, defaultWorkspaceConcurrency-s.swarms.activeReservationsForWorkspace(req.WorkspaceID))
	}
	threadRemaining := defaultThreadConcurrency
	if req.WorkspaceID != "" && req.ThreadID != "" {
		threadRemaining = maxInt(0, defaultThreadConcurrency-s.swarms.activeReservationsForThread(req.WorkspaceID, req.ThreadID))
	}
	workspaceQueued := s.swarms.queuedSessionsForWorkspace(req.WorkspaceID)
	threadQueued := s.swarms.queuedSessionsForThread(req.WorkspaceID, req.ThreadID)
	if budgetWarning, budgetReason := requesterQueueBudgetWarning(req, workspaceQueued, threadQueued); budgetReason != "" {
		plan.AdmittedAgents = 0
		plan.QueueRemainder = req.RequestedAgents
		plan.QueuePosition = s.swarms.queueDepth() + 1
		plan.QueueReason = budgetReason
		plan.ETASeconds = estimateQueueETA(plan.QueuePosition, plan.Totals.SlotsFree, plan.QueueReason)
		plan.Warnings = append(plan.Warnings, budgetWarning)
		plan.SelectionExplanation = explainSwarmSelection(req, plan)
		return plan, http.StatusOK, nil
	}
	if budgetWarning, budgetReason := requesterMemberCapWarning(req, preflight.RequesterActiveReservations, preflight.RequesterReservationCap); budgetReason != "" {
		plan.AdmittedAgents = 0
		plan.QueueRemainder = req.RequestedAgents
		plan.QueuePosition = s.swarms.queueDepth() + 1
		plan.QueueReason = budgetReason
		plan.ETASeconds = estimateQueueETA(plan.QueuePosition, plan.Totals.SlotsFree, plan.QueueReason)
		plan.Warnings = append(plan.Warnings, budgetWarning)
		plan.SelectionExplanation = explainSwarmSelection(req, plan)
		return plan, http.StatusOK, nil
	}
	workspacePremium := s.swarms.premiumSessionsForWorkspace(req.WorkspaceID)
	threadPremium := s.swarms.premiumSessionsForThread(req.WorkspaceID, req.ThreadID)
	if budgetWarning, budgetReason := premiumQueueBudgetWarning(req, plan, workspacePremium, threadPremium); budgetReason != "" {
		plan.AdmittedAgents = 0
		plan.QueueRemainder = req.RequestedAgents
		plan.QueuePosition = s.swarms.queueDepth() + 1
		plan.QueueReason = budgetReason
		plan.ETASeconds = estimateQueueETA(plan.QueuePosition, plan.Totals.SlotsFree, plan.QueueReason)
		plan.Warnings = append(plan.Warnings, budgetWarning)
		plan.SelectionExplanation = explainSwarmSelection(req, plan)
		return plan, http.StatusOK, nil
	}
	now := time.Now().UTC()
	workspaceCooldown := s.swarms.recentPremiumCooldownForWorkspace(req.WorkspaceID, now)
	threadCooldown := s.swarms.recentPremiumCooldownForThread(req.WorkspaceID, req.ThreadID, now)
	cooldownETA := s.swarms.maxPremiumCooldownRemaining(req.WorkspaceID, req.ThreadID, now)
	if budgetWarning, budgetReason := premiumCooldownWarning(req, plan, workspaceCooldown, threadCooldown); budgetReason != "" {
		plan.AdmittedAgents = 0
		plan.QueueRemainder = req.RequestedAgents
		plan.QueuePosition = s.swarms.queueDepth() + 1
		plan.QueueReason = budgetReason
		if cooldownETA > 0 {
			plan.ETASeconds = cooldownETA
		} else {
			plan.ETASeconds = estimateQueueETA(plan.QueuePosition, plan.Totals.SlotsFree, plan.QueueReason)
		}
		plan.Warnings = append(plan.Warnings, budgetWarning)
		plan.SelectionExplanation = explainSwarmSelection(req, plan)
		return plan, http.StatusOK, nil
	}

	plan.AdmittedAgents = minPositive(req.MaxAgents, freeSlots, memberRemaining, globalRemaining, workspaceRemaining, threadRemaining)
	plan.QueueRemainder = maxInt(0, req.RequestedAgents-plan.AdmittedAgents)
	if plan.QueueRemainder > 0 || plan.AdmittedAgents == 0 {
		plan.QueuePosition = s.swarms.queueDepth() + 1
		plan.QueueReason = admissionClampReason(plan.RequestedAgents, freeSlots, memberRemaining, globalRemaining, workspaceRemaining, threadRemaining, plan.Available, isPremiumContentionRequest(plan))
		plan.ETASeconds = estimateQueueETA(plan.QueuePosition, freeSlots, plan.QueueReason)
	}
	if plan.AdmittedAgents < req.RequestedAgents {
		plan.Warnings = append(plan.Warnings, fmt.Sprintf("admitted %d of %d requested agents", plan.AdmittedAgents, req.RequestedAgents))
	}
	if req.Scheduling == "sticky" && req.MaxAgents > 1 {
		plan.Warnings = append(plan.Warnings, "sticky scheduling keeps worker identity stable but can reduce swarm utilization")
	}
	if warning := premiumMisuseWarning(req, plan); warning != "" {
		plan.Warnings = append(plan.Warnings, warning)
	}
	plan.SelectionExplanation = explainSwarmSelection(req, plan)

	return plan, http.StatusOK, nil
}

func enrichSwarmPlanExecution(plan *swarmPlanResponse, req swarmPlanRequest) {
	if plan == nil {
		return
	}
	plan.Strategy = defaultValue(strings.TrimSpace(req.Strategy), "single_best")
	plan.CapabilityMatrix = buildSwarmCapabilityMatrix(plan.Providers, req)
	plan.WorkerRoles = buildSwarmWorkerRoles(plan.Strategy, plan.Providers, plan.ResolvedModel)
	plan.Quorum = buildSwarmQuorumPlan(plan.Strategy, plan.RequestedAgents, plan.AdmittedAgents)
	plan.Warnings = append(plan.Warnings, goWideCapabilityWarnings(plan.Strategy, plan.CapabilityMatrix)...)
}

func buildSwarmCapabilityMatrix(providers []preflightProvider, req swarmPlanRequest) []swarmCapabilityRow {
	if len(providers) == 0 {
		return nil
	}
	rows := make([]swarmCapabilityRow, 0, len(providers))
	for idx, provider := range providers {
		bestModel := ""
		if len(provider.MatchingModels) > 0 {
			bestModel = provider.MatchingModels[0].ID
		}
		tier := capabilityTierForProvider(provider)
		role := suggestedRoleForCapability(provider, idx)
		row := swarmCapabilityRow{
			ProviderID:              provider.ID,
			ProviderName:            provider.Name,
			OwnerMemberID:           provider.OwnerMemberID,
			OwnerMemberName:         provider.OwnerMemberName,
			BestModel:               bestModel,
			TotalModels:             len(provider.MatchingModels),
			SlotsFree:               provider.Slots.Free,
			SlotsTotal:              provider.Slots.Total,
			ActiveSessions:          provider.ActiveSessions,
			CurrentLoad:             provider.ActiveSessions + maxInt(0, provider.Slots.Total-provider.Slots.Free),
			RecentTokensPerSecond:   provider.RecentUploadedTokensPS,
			CapabilityTier:          tier,
			RouteTrust:              routeTrustForScope(req.RouteScope, provider),
			FileAccessApprovalState: fileAccessApprovalStateForPlan(req),
			AssignmentPolicy:        assignmentPolicyForCapability(role, tier),
			SuggestedRole:           role,
			MaintenanceState:        provider.MaintenanceState,
		}
		if provider.Hardware != nil {
			row.CPU = provider.Hardware.CPUBrand
			row.MemoryGB = provider.Hardware.MemoryGB
		}
		if role == "idle_underpowered" {
			row.IdleReason = "left idle for this job because the member is below the minimum capability tier for generation"
		}
		rows = append(rows, row)
	}
	return rows
}

func buildSwarmWorkerRoles(strategy string, providers []preflightProvider, resolvedModel string) []swarmWorkerRole {
	if len(providers) == 0 {
		return nil
	}
	roles := make([]swarmWorkerRole, 0, len(providers))
	for idx, provider := range providers {
		modelID := strings.TrimSpace(resolvedModel)
		if modelID == "" && len(provider.MatchingModels) > 0 {
			modelID = provider.MatchingModels[0].ID
		}
		role := suggestedRoleForCapability(provider, idx)
		rationale := "best available worker for the admitted request"
		if normalizeSwarmStrategy(strategy) == "go_wide" {
			switch role {
			case "primary_generation":
				rationale = "highest-capability admitted worker gets the hardest generation or architecture slice"
			case "validation_review":
				rationale = "secondary worker is best used for independent checks, repair, or narrower slices"
			default:
				rationale = "additional worker should receive bounded parallel slices that match its capacity"
			}
		}
		roles = append(roles, swarmWorkerRole{
			ProviderID:      provider.ID,
			OwnerMemberName: defaultValue(provider.OwnerMemberName, provider.Name),
			Role:            role,
			Model:           modelID,
			Rationale:       rationale,
		})
	}
	return roles
}

func suggestedRoleForCapability(provider preflightProvider, index int) string {
	if strings.TrimSpace(provider.MaintenanceState) != "" {
		return "maintenance_unavailable"
	}
	if provider.Slots.Free <= 0 {
		return "busy"
	}
	tier := capabilityTierForProvider(provider)
	if index == 0 {
		return "primary_generation"
	}
	switch {
	case tier == "tier_128gb_power":
		if index == 1 {
			return "secondary_reviewer"
		}
		if index >= 4 {
			return "final_handoff_assembler"
		}
		return "parallel_generation"
	case tier == "tier_64gb_power":
		if index == 1 {
			return "validation_review"
		}
		if index == 3 {
			return "conflict_checker"
		}
		if index >= 4 {
			return "final_handoff_assembler"
		}
		return "integration_reviewer"
	case tier == "tier_32gb_light":
		if index == 1 {
			return "schema_validator"
		}
		if index == 2 {
			return "conflict_checker"
		}
		if index >= 4 {
			return "final_handoff_assembler"
		}
		return "light_validation"
	}
	return "idle_underpowered"
}

func capabilityTierForProvider(provider preflightProvider) string {
	memoryGB := 0
	if provider.Hardware != nil {
		memoryGB = provider.Hardware.MemoryGB
	}
	switch {
	case memoryGB >= 96:
		return "tier_128gb_power"
	case memoryGB >= 48:
		return "tier_64gb_power"
	case memoryGB >= 24:
		return "tier_32gb_light"
	case memoryGB > 0:
		return "tier_underpowered"
	default:
		return "tier_unknown"
	}
}

func routeTrustForScope(routeScope string, provider preflightProvider) string {
	switch normalizeRouteScope(routeScope) {
	case routeScopeLocalOnly:
		return "local"
	case routeScopeTrustedOnly:
		return "trusted"
	default:
		if strings.TrimSpace(provider.OwnerMemberID) != "" || strings.TrimSpace(provider.OwnerMemberName) != "" {
			return "public_member"
		}
		return "public"
	}
}

func fileAccessApprovalStateForPlan(req swarmPlanRequest) string {
	if req.OnlyMacsArtifact == nil {
		return "prompt_only"
	}
	switch normalizeRouteScope(req.RouteScope) {
	case routeScopeSwarm:
		return "blocked_public_file_access"
	case routeScopeTrustedOnly, routeScopeLocalOnly:
		return "approval_required"
	default:
		return "approval_required"
	}
}

func assignmentPolicyForCapability(role string, tier string) string {
	switch role {
	case "primary_generation", "parallel_generation":
		return "generation_or_planning"
	case "secondary_reviewer", "validation_review", "integration_reviewer":
		return "independent_review_or_integration"
	case "schema_validator", "light_validation":
		return "bounded_validation_or_formatting"
	case "conflict_checker":
		return "target_path_and_diff_conflict_check"
	case "final_handoff_assembler":
		return "assemble_validated_outputs_for_local_review"
	case "idle_underpowered":
		return "idle_for_this_job"
	default:
		return tier
	}
}

func goWideCapabilityWarnings(strategy string, rows []swarmCapabilityRow) []string {
	if normalizeSwarmStrategy(strategy) != "go_wide" {
		return nil
	}
	var warnings []string
	for _, row := range rows {
		if row.SuggestedRole == "idle_underpowered" {
			warnings = append(warnings, fmt.Sprintf("%s is visible to the swarm but will be left idle or assigned checks only for this job because it is below the generation tier.", defaultValue(row.OwnerMemberName, row.ProviderName)))
		}
	}
	return warnings
}

func buildSwarmQuorumPlan(strategy string, requestedAgents int, admittedAgents int) *swarmQuorumPlan {
	if normalizeSwarmStrategy(strategy) != "go_wide" && requestedAgents <= 1 {
		return nil
	}
	minimumReviewers := 0
	if admittedAgents > 1 {
		minimumReviewers = 1
	}
	preferredReviewers := 1
	if admittedAgents >= 3 {
		preferredReviewers = 2
	}
	return &swarmQuorumPlan{
		Mode:               "validate_before_merge",
		MinimumReviewers:   minimumReviewers,
		PreferredReviewers: preferredReviewers,
		Description:        "Generation slices should be validated by a different admitted worker or by the requester before merge.",
	}
}

func explainSwarmSelection(req swarmPlanRequest, plan swarmPlanResponse) string {
	if selection := strings.TrimSpace(plan.SelectionExplanation); selection != "" {
		return selection
	}
	resolved := strings.TrimSpace(plan.ResolvedModel)
	requested := strings.TrimSpace(req.Model)
	scopeDetail := routeScopeSelectionDetail(req.RouteScope)
	preferenceDetail := routePreferenceSelectionDetail(req.RouteScope, req.PreferRemote, req.PreferRemoteSoft)
	composeDetails := func(message string) string {
		if scopeDetail != "" && preferenceDetail != "" {
			return fmt.Sprintf("%s %s %s", scopeDetail, preferenceDetail, message)
		}
		if scopeDetail != "" {
			return fmt.Sprintf("%s %s", scopeDetail, message)
		}
		if preferenceDetail != "" {
			return fmt.Sprintf("%s %s", preferenceDetail, message)
		}
		return message
	}
	if resolved == "" {
		if requested == "" {
			if req.PreferRemote && normalizeRouteScope(req.RouteScope) == routeScopeSwarm {
				return composeDetails("OnlyMacs is still waiting for a remote Mac with any ready model and an open slot.")
			}
			return composeDetails("OnlyMacs is still waiting for a model with an open slot.")
		}
		if req.PreferRemote && normalizeRouteScope(req.RouteScope) == routeScopeSwarm {
			return composeDetails(fmt.Sprintf("OnlyMacs is still waiting for a remote Mac that can serve %s.", requested))
		}
		return composeDetails(fmt.Sprintf("OnlyMacs is still waiting for %s to become available.", requested))
	}

	if requested == "" {
		if plan.Available {
			if req.PreferRemote && normalizeRouteScope(req.RouteScope) == routeScopeSwarm {
				return composeDetails(fmt.Sprintf("OnlyMacs chose %s because it is the strongest remote model with an open slot right now.", resolved))
			}
			return composeDetails(fmt.Sprintf("OnlyMacs chose %s because it is the strongest model with an open slot right now.", resolved))
		}
		if req.PreferRemote && normalizeRouteScope(req.RouteScope) == routeScopeSwarm {
			return composeDetails(fmt.Sprintf("OnlyMacs would prefer %s next, but no remote Mac has a free slot yet.", resolved))
		}
		return composeDetails(fmt.Sprintf("OnlyMacs would prefer %s next, but the swarm does not have a free slot yet.", resolved))
	}

	if plan.FallbackUsed && resolved != requested {
		return composeDetails(fmt.Sprintf("OnlyMacs switched from %s to %s because fallback was allowed and the requested model was unavailable.", requested, resolved))
	}

	if resolved == requested {
		if plan.Available {
			if req.PreferRemote && normalizeRouteScope(req.RouteScope) == routeScopeSwarm {
				return composeDetails(fmt.Sprintf("OnlyMacs can serve %s on a remote Mac right now.", resolved))
			}
			return composeDetails(fmt.Sprintf("OnlyMacs can serve %s right now.", resolved))
		}
		if req.PreferRemote && normalizeRouteScope(req.RouteScope) == routeScopeSwarm {
			return composeDetails(fmt.Sprintf("OnlyMacs is waiting for a remote Mac to free up %s.", resolved))
		}
		return composeDetails(fmt.Sprintf("OnlyMacs is waiting for %s to free up.", resolved))
	}

	if scopeDetail != "" {
		return fmt.Sprintf("%s OnlyMacs resolved %s to %s for this swarm.", scopeDetail, requested, resolved)
	}
	return fmt.Sprintf("OnlyMacs resolved %s to %s for this swarm.", requested, resolved)
}
