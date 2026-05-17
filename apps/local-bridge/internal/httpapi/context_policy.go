package httpapi

import "strings"

const (
	bridgeSwarmContextPolicyVersion = 1

	bridgeContextReadManualApproval  = "manual_approval"
	bridgeContextReadRememberedPacks = "remembered_context_packs"
	bridgeContextReadFullProject     = "full_project_folder"
	bridgeContextReadGitBacked       = "git_backed_checkout"

	bridgeContextWriteInbox    = "inbox"
	bridgeContextWriteStaged   = "staged_apply"
	bridgeContextWriteDirect   = "direct_write"
	bridgeContextWriteReadOnly = "read_only"
)

func defaultBridgeSwarmContextPolicy(visibility string) *swarmContextPolicy {
	switch strings.ToLower(strings.TrimSpace(visibility)) {
	case "public":
		return &swarmContextPolicy{
			Version:                  bridgeSwarmContextPolicyVersion,
			ContextReadMode:          bridgeContextReadManualApproval,
			ContextWriteMode:         bridgeContextWriteInbox,
			AllowTestExecution:       false,
			AllowDependencyInstall:   false,
			RequireFileLocks:         true,
			SecretGuardEnabled:       true,
			MaxContextRequestRounds:  1,
			DirectWriteRequiresAdmin: true,
		}
	case "private":
		return &swarmContextPolicy{
			Version:                  bridgeSwarmContextPolicyVersion,
			ContextReadMode:          bridgeContextReadFullProject,
			ContextWriteMode:         bridgeContextWriteStaged,
			AllowTestExecution:       true,
			AllowDependencyInstall:   false,
			RequireFileLocks:         true,
			SecretGuardEnabled:       true,
			MaxContextRequestRounds:  3,
			DirectWriteRequiresAdmin: true,
		}
	default:
		return &swarmContextPolicy{
			Version:                  bridgeSwarmContextPolicyVersion,
			ContextReadMode:          bridgeContextReadManualApproval,
			ContextWriteMode:         bridgeContextWriteInbox,
			AllowTestExecution:       false,
			AllowDependencyInstall:   false,
			RequireFileLocks:         true,
			SecretGuardEnabled:       true,
			MaxContextRequestRounds:  1,
			DirectWriteRequiresAdmin: true,
		}
	}
}

func normalizedBridgeSwarmContextPolicy(policy *swarmContextPolicy, visibility string) *swarmContextPolicy {
	defaults := defaultBridgeSwarmContextPolicy(visibility)
	if policy == nil {
		return defaults
	}
	normalized := *defaults
	normalized.Version = bridgeSwarmContextPolicyVersion
	if readMode := normalizeBridgeContextReadMode(policy.ContextReadMode); readMode != "" {
		normalized.ContextReadMode = readMode
	}
	if writeMode := normalizeBridgeContextWriteMode(policy.ContextWriteMode); writeMode != "" {
		normalized.ContextWriteMode = writeMode
	}
	normalized.AllowTestExecution = policy.AllowTestExecution
	normalized.AllowDependencyInstall = policy.AllowDependencyInstall
	normalized.RequireFileLocks = policy.RequireFileLocks
	normalized.SecretGuardEnabled = policy.SecretGuardEnabled
	normalized.DirectWriteRequiresAdmin = policy.DirectWriteRequiresAdmin
	normalized.MaxContextRequestRounds = policy.MaxContextRequestRounds
	if normalized.MaxContextRequestRounds < 0 {
		normalized.MaxContextRequestRounds = 0
	}
	if normalized.MaxContextRequestRounds > 5 {
		normalized.MaxContextRequestRounds = 5
	}
	normalized.AllowedContextPacks = append([]string(nil), policy.AllowedContextPacks...)

	if strings.EqualFold(strings.TrimSpace(visibility), "public") {
		normalized.ContextReadMode = bridgeContextReadManualApproval
		normalized.ContextWriteMode = bridgeContextWriteInbox
		normalized.AllowTestExecution = false
		normalized.AllowDependencyInstall = false
		normalized.RequireFileLocks = true
		normalized.SecretGuardEnabled = true
		normalized.MaxContextRequestRounds = 1
		normalized.DirectWriteRequiresAdmin = true
	}
	return &normalized
}

func normalizeBridgeContextReadMode(mode string) string {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "", "default":
		return ""
	case bridgeContextReadManualApproval, "manual", "manual_approved":
		return bridgeContextReadManualApproval
	case bridgeContextReadRememberedPacks, "packs", "context_packs", "remembered_packs":
		return bridgeContextReadRememberedPacks
	case bridgeContextReadFullProject, "full_project", "full-project", "full", "project":
		return bridgeContextReadFullProject
	case bridgeContextReadGitBacked, "git", "checkout", "git_checkout":
		return bridgeContextReadGitBacked
	default:
		return ""
	}
}

func normalizeBridgeContextWriteMode(mode string) string {
	switch strings.ToLower(strings.TrimSpace(mode)) {
	case "", "default":
		return ""
	case bridgeContextWriteInbox:
		return bridgeContextWriteInbox
	case bridgeContextWriteStaged, "staged", "staged-apply", "apply":
		return bridgeContextWriteStaged
	case bridgeContextWriteDirect, "direct", "direct-write":
		return bridgeContextWriteDirect
	case bridgeContextWriteReadOnly, "readonly", "read-only":
		return bridgeContextWriteReadOnly
	default:
		return ""
	}
}
