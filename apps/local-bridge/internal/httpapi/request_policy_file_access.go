package httpapi

import "strings"

type requestPolicyFileAccessMode string

const (
	requestFileAccessNone                requestPolicyFileAccessMode = "none"
	requestFileAccessBlockedPublic       requestPolicyFileAccessMode = "blocked_public"
	requestFileAccessCapsuleSnapshot     requestPolicyFileAccessMode = "capsule_snapshot"
	requestFileAccessCapsuleWithRequests requestPolicyFileAccessMode = "capsule_with_context_requests"
	requestFileAccessPrivateProjectLease requestPolicyFileAccessMode = "private_project_lease"
	requestFileAccessGitBackedCheckout   requestPolicyFileAccessMode = "git_backed_checkout"
	requestFileAccessLocalOnly           requestPolicyFileAccessMode = "local_only"
)

type requestPolicyTrustTier string

const (
	requestTrustPublicUntrusted  requestPolicyTrustTier = "public_untrusted"
	requestTrustPrivateStandard  requestPolicyTrustTier = "private_standard"
	requestTrustPrivateTrusted   requestPolicyTrustTier = "private_trusted"
	requestTrustPrivateGitBacked requestPolicyTrustTier = "private_git_backed"
	requestTrustLocal            requestPolicyTrustTier = "local"
)

type requestPolicyFileAccessPlan struct {
	Mode                        requestPolicyFileAccessMode `json:"mode"`
	TrustTier                   requestPolicyTrustTier      `json:"trust_tier"`
	ApprovalRequired            bool                        `json:"approval_required"`
	PublicAllowed               bool                        `json:"public_allowed"`
	PrivateAllowed              bool                        `json:"private_allowed"`
	LocalRecommended            bool                        `json:"local_recommended"`
	SuggestedContextPacks       []string                    `json:"suggested_context_packs,omitempty"`
	SuggestedFiles              []string                    `json:"suggested_files,omitempty"`
	SuggestedExportLevelPublic  string                      `json:"suggested_export_level_public,omitempty"`
	SuggestedExportLevelPrivate string                      `json:"suggested_export_level_private,omitempty"`
	AllowContextRequests        bool                        `json:"allow_context_requests"`
	MaxContextRequestRounds     int                         `json:"max_context_request_rounds"`
	ContextReadMode             string                      `json:"context_read_mode,omitempty"`
	ContextWriteMode            string                      `json:"context_write_mode,omitempty"`
	AllowTestExecution          bool                        `json:"allow_test_execution"`
	AllowDependencyInstall      bool                        `json:"allow_dependency_install"`
	RequireFileLocks            bool                        `json:"require_file_locks"`
	SecretGuardEnabled          bool                        `json:"secret_guard_enabled"`
	AllowSourceMutation         bool                        `json:"allow_source_mutation"`
	AllowStagedMutation         bool                        `json:"allow_staged_mutation"`
	AllowOutputArtifacts        bool                        `json:"allow_output_artifacts"`
	Reason                      string                      `json:"reason,omitempty"`
	UserFacingWarning           string                      `json:"user_facing_warning,omitempty"`
}

func buildRequestPolicyFileAccessPlan(
	classification requestPolicyClassification,
	decision requestPolicyDecision,
	routeScope string,
	activeSwarmVisibility string,
	policies ...*swarmContextPolicy,
) requestPolicyFileAccessPlan {
	routeScope = normalizeRouteScope(routeScope)
	activeSwarmVisibility = strings.TrimSpace(strings.ToLower(activeSwarmVisibility))
	policy := normalizedBridgeSwarmContextPolicy(firstSwarmContextPolicy(policies), activeSwarmVisibility)

	plan := requestPolicyFileAccessPlan{
		Mode:                        requestFileAccessNone,
		TrustTier:                   requestTrustPublicUntrusted,
		PublicAllowed:               !classification.RequiresLocalFiles,
		PrivateAllowed:              classification.RequiresLocalFiles,
		LocalRecommended:            routeScope == routeScopeLocalOnly || classification.Sensitivity == requestSensitivityHigh,
		SuggestedContextPacks:       suggestedContextPacksForClassification(classification),
		SuggestedFiles:              suggestedFilesForClassification(classification),
		SuggestedExportLevelPublic:  suggestedPublicExportLevel(classification),
		SuggestedExportLevelPrivate: suggestedPrivateExportLevel(classification),
		AllowContextRequests:        classification.RequiresLocalFiles && classification.Sensitivity != requestSensitivityHigh,
		MaxContextRequestRounds:     maxContextRequestRounds(classification, activeSwarmVisibility),
		ContextReadMode:             policy.ContextReadMode,
		ContextWriteMode:            policy.ContextWriteMode,
		AllowTestExecution:          policy.AllowTestExecution,
		AllowDependencyInstall:      policy.AllowDependencyInstall,
		RequireFileLocks:            policy.RequireFileLocks,
		SecretGuardEnabled:          policy.SecretGuardEnabled,
		AllowSourceMutation:         false,
		AllowStagedMutation:         classification.RequiresLocalFiles && classification.WantsWriteAccess,
		AllowOutputArtifacts:        classification.RequiresLocalFiles,
	}
	plan.MaxContextRequestRounds = boundedContextRequestRounds(plan.MaxContextRequestRounds, policy)

	switch routeScope {
	case routeScopeLocalOnly:
		plan.Mode = requestFileAccessLocalOnly
		plan.TrustTier = requestTrustLocal
		plan.ApprovalRequired = false
		plan.PublicAllowed = false
		plan.PrivateAllowed = false
		plan.AllowContextRequests = false
		plan.MaxContextRequestRounds = 0
		plan.ContextReadMode = "local_only"
		plan.ContextWriteMode = bridgeContextWriteDirect
		plan.AllowTestExecution = true
		plan.AllowDependencyInstall = true
		plan.RequireFileLocks = false
		plan.SecretGuardEnabled = true
		plan.AllowStagedMutation = classification.WantsWriteAccess
		plan.AllowSourceMutation = classification.WantsWriteAccess
		plan.Reason = "This request is already staying on This Mac, so OnlyMacs does not need to export a context capsule."
		return plan
	}

	if classification.Sensitivity == requestSensitivityHigh {
		plan.Mode = requestFileAccessLocalOnly
		plan.TrustTier = requestTrustLocal
		plan.ApprovalRequired = false
		plan.PublicAllowed = false
		plan.PrivateAllowed = false
		plan.AllowContextRequests = false
		plan.MaxContextRequestRounds = 0
		plan.ContextReadMode = "local_only"
		plan.ContextWriteMode = bridgeContextWriteInbox
		plan.AllowTestExecution = false
		plan.AllowDependencyInstall = false
		plan.RequireFileLocks = false
		plan.SecretGuardEnabled = true
		plan.AllowStagedMutation = classification.WantsWriteAccess
		plan.Reason = "This request looks sensitive enough that OnlyMacs should keep the work on This Mac."
		plan.UserFacingWarning = "Sensitive files, credentials, or personal records should stay local."
		return plan
	}

	if !classification.RequiresLocalFiles {
		plan.Mode = requestFileAccessNone
		plan.TrustTier = trustTierForVisibility(activeSwarmVisibility)
		plan.ApprovalRequired = false
		plan.PublicAllowed = true
		plan.PrivateAllowed = true
		plan.AllowContextRequests = false
		plan.MaxContextRequestRounds = 0
		plan.AllowOutputArtifacts = false
		plan.Reason = "This request is prompt-only, so OnlyMacs does not need file access."
		return plan
	}

	switch decision {
	case requestPolicyBlockedPublic:
		plan.Mode = requestFileAccessBlockedPublic
		plan.TrustTier = requestTrustPublicUntrusted
		plan.ApprovalRequired = true
		plan.PublicAllowed = false
		plan.PrivateAllowed = true
		plan.AllowContextRequests = false
		plan.MaxContextRequestRounds = 0
		plan.ContextReadMode = bridgeContextReadManualApproval
		plan.ContextWriteMode = bridgeContextWriteInbox
		plan.AllowTestExecution = false
		plan.AllowDependencyInstall = false
		plan.RequireFileLocks = true
		plan.SecretGuardEnabled = true
		plan.Reason = "Open swarms are prompt-only. Local files must move through an approved context capsule on a private or local route."
		plan.UserFacingWarning = "Use a private swarm or This Mac for repo and file-aware work."
	case requestPolicyPublicExport:
		plan.Mode = requestFileAccessCapsuleSnapshot
		plan.TrustTier = requestTrustPublicUntrusted
		plan.ApprovalRequired = true
		plan.PublicAllowed = true
		plan.PrivateAllowed = true
		plan.LocalRecommended = false
		plan.AllowContextRequests = true
		plan.MaxContextRequestRounds = 1
		plan.ContextReadMode = bridgeContextReadManualApproval
		plan.ContextWriteMode = bridgeContextWriteInbox
		plan.AllowTestExecution = false
		plan.AllowDependencyInstall = false
		plan.RequireFileLocks = true
		plan.SecretGuardEnabled = true
		plan.AllowSourceMutation = false
		plan.AllowStagedMutation = false
		plan.AllowOutputArtifacts = true
		plan.Reason = "This request can use a public-safe context capsule with explicit approval and excerpt-only export rules."
		plan.UserFacingWarning = "Only approved excerpts will leave this Mac. Public workers cannot browse your repo or write back to local files."
	case requestPolicyPrivateExport:
		plan.Mode = requestFileAccessCapsuleSnapshot
		plan.TrustTier = trustTierForVisibility(activeSwarmVisibility)
		plan.ApprovalRequired = true
		plan.PublicAllowed = false
		plan.PrivateAllowed = true
		if classification.Complexity == requestComplexityHeavy {
			plan.Mode = requestFileAccessCapsuleWithRequests
		}
		switch policy.ContextReadMode {
		case bridgeContextReadRememberedPacks:
			plan.Mode = requestFileAccessCapsuleWithRequests
		case bridgeContextReadFullProject:
			plan.Mode = requestFileAccessPrivateProjectLease
			plan.TrustTier = requestTrustPrivateTrusted
		case bridgeContextReadGitBacked:
			plan.Mode = requestFileAccessGitBackedCheckout
			plan.TrustTier = requestTrustPrivateGitBacked
		}
		if classification.Complexity == requestComplexityHeavy && classification.WantsWriteAccess {
			plan.Mode = requestFileAccessPrivateProjectLease
			plan.TrustTier = requestTrustPrivateTrusted
		}
		if classification.LooksLikeCodeContext && classification.WantsWriteAccess {
			plan.Mode = requestFileAccessGitBackedCheckout
			plan.TrustTier = requestTrustPrivateGitBacked
		}
		if classification.WantsWriteAccess {
			switch policy.ContextWriteMode {
			case bridgeContextWriteDirect:
				plan.AllowStagedMutation = true
				plan.AllowSourceMutation = true
				plan.UserFacingWarning = "This private swarm allows direct-write capable artifacts; OnlyMacs still expects ticket locks, validation, and source-side apply controls."
			case bridgeContextWriteStaged:
				plan.AllowStagedMutation = true
				plan.AllowSourceMutation = false
				plan.UserFacingWarning = "Remote workers can return patches/artifacts for staged apply; your local checkout is not changed until apply."
			case bridgeContextWriteReadOnly:
				plan.AllowStagedMutation = false
				plan.AllowSourceMutation = false
				plan.UserFacingWarning = "This private swarm policy is read-only for context-aware work."
			default:
				plan.AllowStagedMutation = false
				plan.AllowSourceMutation = false
				plan.UserFacingWarning = "Remote workers can suggest outputs or patches, but they cannot mutate your local checkout directly."
			}
		}
		plan.Reason = "This request needs context export before a trusted swarm can work on it."
	case requestPolicyBlockedUnverified:
		plan.Mode = requestFileAccessBlockedPublic
		plan.TrustTier = requestTrustPublicUntrusted
		plan.ApprovalRequired = true
		plan.PublicAllowed = false
		plan.PrivateAllowed = true
		plan.AllowContextRequests = false
		plan.MaxContextRequestRounds = 0
		plan.ContextReadMode = bridgeContextReadManualApproval
		plan.ContextWriteMode = bridgeContextWriteInbox
		plan.AllowTestExecution = false
		plan.AllowDependencyInstall = false
		plan.Reason = "OnlyMacs could not verify that the current swarm is private, so it will not export local files."
		plan.UserFacingWarning = "Switch to a verified private swarm or keep the work on This Mac."
	default:
		plan.Mode = requestFileAccessNone
		plan.TrustTier = trustTierForVisibility(activeSwarmVisibility)
		plan.Reason = "OnlyMacs can keep the current route because this request does not require an export decision."
	}

	return plan
}

func boundedContextRequestRounds(defaultRounds int, policy *swarmContextPolicy) int {
	if policy == nil || policy.MaxContextRequestRounds <= 0 {
		return defaultRounds
	}
	if defaultRounds <= 0 {
		return 0
	}
	if policy.MaxContextRequestRounds < defaultRounds {
		return policy.MaxContextRequestRounds
	}
	return defaultRounds
}

func trustTierForVisibility(visibility string) requestPolicyTrustTier {
	switch strings.TrimSpace(strings.ToLower(visibility)) {
	case "private":
		return requestTrustPrivateStandard
	case "public":
		return requestTrustPublicUntrusted
	default:
		return requestTrustPrivateStandard
	}
}

func suggestedContextPacksForClassification(classification requestPolicyClassification) []string {
	if !classification.RequiresLocalFiles {
		return nil
	}

	packs := []string{}
	add := func(pack string) {
		for _, existing := range packs {
			if existing == pack {
				return
			}
		}
		packs = append(packs, pack)
	}

	switch classification.TaskKind {
	case requestTaskReview:
		add("docs-review")
		if classification.Complexity == requestComplexityHeavy {
			add("content-pipeline")
		}
	case requestTaskDebug:
		add("code-review-core")
	case requestTaskGenerate:
		add("schema-generation")
		if classification.Complexity == requestComplexityHeavy {
			add("content-pipeline")
		}
	case requestTaskTransform:
		add("transform-context")
		add("schema-generation")
	default:
		add("docs-review")
	}

	if classification.DataAccess == requestDataWorkspaceWrite {
		add("transform-context")
	}

	if classification.Complexity == requestComplexityHeavy && classification.TaskKind != requestTaskDebug {
		add("content-pipeline")
	}

	return packs
}

func suggestedFilesForClassification(classification requestPolicyClassification) []string {
	if !classification.RequiresLocalFiles {
		return nil
	}

	switch classification.TaskKind {
	case requestTaskReview:
		return []string{"README.md", "pipeline docs", "master docs", "content-generation/README.md"}
	case requestTaskDebug:
		return []string{"src/", "tests/", "package.json", "tsconfig.json"}
	case requestTaskGenerate:
		return []string{"schema files", "example outputs", "glossary", "pipeline docs"}
	case requestTaskTransform:
		return []string{"target file", "supporting schema", "example inputs", "config"}
	default:
		return []string{"README.md", "relevant docs", "example files"}
	}
}

func suggestedPublicExportLevel(classification requestPolicyClassification) string {
	if !classification.RequiresLocalFiles {
		return "none"
	}
	if classification.Sensitivity == requestSensitivityHigh {
		return "blocked"
	}
	return "excerpt_capsule"
}

func suggestedPrivateExportLevel(classification requestPolicyClassification) string {
	if !classification.RequiresLocalFiles {
		return "none"
	}
	if classification.WantsWriteAccess || classification.Complexity == requestComplexityHeavy {
		return "review_grade_capsule"
	}
	return "trusted_context_capsule"
}

func maxContextRequestRounds(classification requestPolicyClassification, activeSwarmVisibility string) int {
	if !classification.RequiresLocalFiles || classification.Sensitivity == requestSensitivityHigh {
		return 0
	}
	if strings.TrimSpace(strings.ToLower(activeSwarmVisibility)) == "public" {
		return 1
	}
	if classification.Complexity == requestComplexityHeavy {
		return 2
	}
	return 1
}
