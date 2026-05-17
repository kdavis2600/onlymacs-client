package httpapi

import "encoding/json"

type chatCompletionsRequest struct {
	Model              string                   `json:"model"`
	Stream             bool                     `json:"stream"`
	MaxTokens          int                      `json:"max_tokens,omitempty"`
	ReasoningEffort    string                   `json:"reasoning_effort,omitempty"`
	Reasoning          json.RawMessage          `json:"reasoning,omitempty"`
	Think              json.RawMessage          `json:"think,omitempty"`
	RouteScope         string                   `json:"route_scope,omitempty"`
	RouteProviderID    string                   `json:"route_provider_id,omitempty"`
	AvoidProviderIDs   []string                 `json:"avoid_provider_ids,omitempty"`
	ExcludeProviderIDs []string                 `json:"exclude_provider_ids,omitempty"`
	PreferRemote       bool                     `json:"prefer_remote,omitempty"`
	PreferRemoteSoft   bool                     `json:"prefer_remote_soft,omitempty"`
	OnlyMacsArtifact   *onlyMacsArtifactPayload `json:"onlymacs_artifact,omitempty"`
	Messages           []chatMessage            `json:"messages"`
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type onlyMacsArtifactPayload struct {
	ExportMode   string                   `json:"export_mode,omitempty"`
	BundleBase64 string                   `json:"bundle_base64,omitempty"`
	BundleSHA256 string                   `json:"bundle_sha256,omitempty"`
	Manifest     onlyMacsArtifactManifest `json:"manifest"`
}

type onlyMacsArtifactPermissions struct {
	AllowContextRequests    bool `json:"allow_context_requests,omitempty"`
	MaxContextRequestRounds int  `json:"max_context_request_rounds,omitempty"`
	AllowSourceMutation     bool `json:"allow_source_mutation,omitempty"`
	AllowStagedMutation     bool `json:"allow_staged_mutation,omitempty"`
	AllowOutputArtifacts    bool `json:"allow_output_artifacts,omitempty"`
}

type onlyMacsArtifactBudgets struct {
	MaxFileBytes      int  `json:"max_file_bytes,omitempty"`
	MaxTotalBytes     int  `json:"max_total_bytes,omitempty"`
	MaxScanBytes      int  `json:"max_scan_bytes,omitempty"`
	RequiresFullFiles bool `json:"requires_full_files,omitempty"`
	AllowTrimming     bool `json:"allow_trimming,omitempty"`
}

type onlyMacsArtifactBlockedFile struct {
	RelativePath string `json:"relative_path,omitempty"`
	Status       string `json:"status,omitempty"`
	Reason       string `json:"reason,omitempty"`
}

type onlyMacsArtifactApproval struct {
	ApprovalRequired bool   `json:"approval_required,omitempty"`
	RequestedAt      string `json:"requested_at,omitempty"`
	ApprovedAt       string `json:"approved_at,omitempty"`
	SelectedCount    int    `json:"selected_count,omitempty"`
	ExportableCount  int    `json:"exportable_count,omitempty"`
}

type onlyMacsArtifactContextPack struct {
	ID           string   `json:"id,omitempty"`
	Description  string   `json:"description,omitempty"`
	Scope        string   `json:"scope,omitempty"`
	Source       string   `json:"source,omitempty"`
	MatchedFiles []string `json:"matched_files,omitempty"`
}

type onlyMacsArtifactLease struct {
	ID        string `json:"id,omitempty"`
	Mode      string `json:"mode,omitempty"`
	Round     int    `json:"round,omitempty"`
	MaxRounds int    `json:"max_rounds,omitempty"`
	ExpiresAt string `json:"expires_at,omitempty"`
}

type onlyMacsArtifactWorkspace struct {
	Kind         string   `json:"kind,omitempty"`
	VCS          string   `json:"vcs,omitempty"`
	GitHead      string   `json:"git_head,omitempty"`
	GitBranch    string   `json:"git_branch,omitempty"`
	GitDirty     bool     `json:"git_dirty,omitempty"`
	TrackedFiles []string `json:"tracked_files,omitempty"`
}

type onlyMacsArtifactManifest struct {
	Schema                string                         `json:"schema,omitempty"`
	CapsuleID             string                         `json:"capsule_id,omitempty"`
	ID                    string                         `json:"id"`
	RequestID             string                         `json:"request_id,omitempty"`
	CreatedAt             string                         `json:"created_at,omitempty"`
	ExpiresAt             string                         `json:"expires_at,omitempty"`
	WorkspaceRoot         string                         `json:"workspace_root,omitempty"`
	WorkspaceRootLabel    string                         `json:"workspace_root_label,omitempty"`
	WorkspaceFingerprint  string                         `json:"workspace_fingerprint,omitempty"`
	RouteScope            string                         `json:"route_scope,omitempty"`
	TrustTier             string                         `json:"trust_tier,omitempty"`
	AbsolutePathsIncluded bool                           `json:"absolute_paths_included,omitempty"`
	SwarmName             string                         `json:"swarm_name,omitempty"`
	ToolName              string                         `json:"tool_name,omitempty"`
	PromptSummary         string                         `json:"prompt_summary,omitempty"`
	RequestIntent         string                         `json:"request_intent,omitempty"`
	ExportMode            string                         `json:"export_mode,omitempty"`
	OutputContract        string                         `json:"output_contract,omitempty"`
	RequiredSections      []string                       `json:"required_sections,omitempty"`
	GroundingRules        []string                       `json:"grounding_rules,omitempty"`
	ContextRequestRules   []string                       `json:"context_request_rules,omitempty"`
	Permissions           onlyMacsArtifactPermissions    `json:"permissions,omitempty"`
	Budgets               onlyMacsArtifactBudgets        `json:"budgets,omitempty"`
	Lease                 onlyMacsArtifactLease          `json:"lease,omitempty"`
	Workspace             onlyMacsArtifactWorkspace      `json:"workspace,omitempty"`
	ContextPacks          []onlyMacsArtifactContextPack  `json:"context_packs,omitempty"`
	Files                 []onlyMacsArtifactManifestFile `json:"files"`
	Blocked               []onlyMacsArtifactBlockedFile  `json:"blocked,omitempty"`
	Warnings              []string                       `json:"warnings,omitempty"`
	Approval              onlyMacsArtifactApproval       `json:"approval,omitempty"`
	TotalSelectedBytes    int                            `json:"total_selected_bytes,omitempty"`
	TotalExportBytes      int                            `json:"total_export_bytes,omitempty"`
}

type onlyMacsArtifactManifestFile struct {
	Path            string                           `json:"path,omitempty"`
	RelativePath    string                           `json:"relative_path"`
	Category        string                           `json:"category,omitempty"`
	SelectionReason string                           `json:"selection_reason,omitempty"`
	IsRecommended   bool                             `json:"is_recommended,omitempty"`
	ReviewPriority  int                              `json:"review_priority,omitempty"`
	EvidenceHints   []string                         `json:"evidence_hints,omitempty"`
	EvidenceAnchors []onlyMacsArtifactEvidenceAnchor `json:"evidence_anchors,omitempty"`
	OriginalBytes   int                              `json:"original_bytes,omitempty"`
	ExportedBytes   int                              `json:"exported_bytes,omitempty"`
	Status          string                           `json:"status,omitempty"`
	Reason          string                           `json:"reason,omitempty"`
	SHA256          string                           `json:"sha256,omitempty"`
}

type onlyMacsArtifactEvidenceAnchor struct {
	Kind      string `json:"kind,omitempty"`
	LineStart int    `json:"line_start,omitempty"`
	LineEnd   int    `json:"line_end,omitempty"`
	Text      string `json:"text,omitempty"`
}

func (p *onlyMacsArtifactPermissions) UnmarshalJSON(data []byte) error {
	type rawPermissions struct {
		AllowContextRequests       bool `json:"allow_context_requests,omitempty"`
		AllowContextRequestsAlt    bool `json:"allowContextRequests,omitempty"`
		MaxContextRequestRounds    int  `json:"max_context_request_rounds,omitempty"`
		MaxContextRequestRoundsAlt int  `json:"maxContextRequestRounds,omitempty"`
		AllowSourceMutation        bool `json:"allow_source_mutation,omitempty"`
		AllowSourceMutationAlt     bool `json:"allowSourceMutation,omitempty"`
		AllowStagedMutation        bool `json:"allow_staged_mutation,omitempty"`
		AllowStagedMutationAlt     bool `json:"allowStagedMutation,omitempty"`
		AllowOutputArtifacts       bool `json:"allow_output_artifacts,omitempty"`
		AllowOutputArtifactsAlt    bool `json:"allowOutputArtifacts,omitempty"`
	}
	var raw rawPermissions
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	p.AllowContextRequests = raw.AllowContextRequests || raw.AllowContextRequestsAlt
	p.MaxContextRequestRounds = firstNonZero(raw.MaxContextRequestRounds, raw.MaxContextRequestRoundsAlt)
	p.AllowSourceMutation = raw.AllowSourceMutation || raw.AllowSourceMutationAlt
	p.AllowStagedMutation = raw.AllowStagedMutation || raw.AllowStagedMutationAlt
	p.AllowOutputArtifacts = raw.AllowOutputArtifacts || raw.AllowOutputArtifactsAlt
	return nil
}

func (b *onlyMacsArtifactBudgets) UnmarshalJSON(data []byte) error {
	type rawBudgets struct {
		MaxFileBytes         int  `json:"max_file_bytes,omitempty"`
		MaxFileBytesAlt      int  `json:"maxFileBytes,omitempty"`
		MaxTotalBytes        int  `json:"max_total_bytes,omitempty"`
		MaxTotalBytesAlt     int  `json:"maxTotalBytes,omitempty"`
		MaxScanBytes         int  `json:"max_scan_bytes,omitempty"`
		MaxScanBytesAlt      int  `json:"maxScanBytes,omitempty"`
		RequiresFullFiles    bool `json:"requires_full_files,omitempty"`
		RequiresFullFilesAlt bool `json:"requiresFullFiles,omitempty"`
		AllowTrimming        bool `json:"allow_trimming,omitempty"`
		AllowTrimmingAlt     bool `json:"allowTrimming,omitempty"`
	}
	var raw rawBudgets
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	b.MaxFileBytes = firstNonZero(raw.MaxFileBytes, raw.MaxFileBytesAlt)
	b.MaxTotalBytes = firstNonZero(raw.MaxTotalBytes, raw.MaxTotalBytesAlt)
	b.MaxScanBytes = firstNonZero(raw.MaxScanBytes, raw.MaxScanBytesAlt)
	b.RequiresFullFiles = raw.RequiresFullFiles || raw.RequiresFullFilesAlt
	b.AllowTrimming = raw.AllowTrimming || raw.AllowTrimmingAlt
	return nil
}

func (b *onlyMacsArtifactBlockedFile) UnmarshalJSON(data []byte) error {
	type rawBlocked struct {
		RelativePath    string `json:"relative_path,omitempty"`
		RelativePathAlt string `json:"relativePath,omitempty"`
		Status          string `json:"status,omitempty"`
		Reason          string `json:"reason,omitempty"`
	}
	var raw rawBlocked
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	b.RelativePath = firstNonEmpty(raw.RelativePath, raw.RelativePathAlt)
	b.Status = raw.Status
	b.Reason = raw.Reason
	return nil
}

func (a *onlyMacsArtifactApproval) UnmarshalJSON(data []byte) error {
	type rawApproval struct {
		ApprovalRequired    bool   `json:"approval_required,omitempty"`
		ApprovalRequiredAlt bool   `json:"approvalRequired,omitempty"`
		RequestedAt         string `json:"requested_at,omitempty"`
		RequestedAtAlt      string `json:"requestedAt,omitempty"`
		ApprovedAt          string `json:"approved_at,omitempty"`
		ApprovedAtAlt       string `json:"approvedAt,omitempty"`
		SelectedCount       int    `json:"selected_count,omitempty"`
		SelectedCountAlt    int    `json:"selectedCount,omitempty"`
		ExportableCount     int    `json:"exportable_count,omitempty"`
		ExportableCountAlt  int    `json:"exportableCount,omitempty"`
	}
	var raw rawApproval
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	a.ApprovalRequired = raw.ApprovalRequired || raw.ApprovalRequiredAlt
	a.RequestedAt = firstNonEmpty(raw.RequestedAt, raw.RequestedAtAlt)
	a.ApprovedAt = firstNonEmpty(raw.ApprovedAt, raw.ApprovedAtAlt)
	a.SelectedCount = firstNonZero(raw.SelectedCount, raw.SelectedCountAlt)
	a.ExportableCount = firstNonZero(raw.ExportableCount, raw.ExportableCountAlt)
	return nil
}

func (c *onlyMacsArtifactContextPack) UnmarshalJSON(data []byte) error {
	type rawContextPack struct {
		ID              string   `json:"id,omitempty"`
		Description     string   `json:"description,omitempty"`
		Scope           string   `json:"scope,omitempty"`
		Source          string   `json:"source,omitempty"`
		MatchedFiles    []string `json:"matched_files,omitempty"`
		MatchedFilesAlt []string `json:"matchedFiles,omitempty"`
	}
	var raw rawContextPack
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}
	c.ID = raw.ID
	c.Description = raw.Description
	c.Scope = raw.Scope
	c.Source = raw.Source
	c.MatchedFiles = firstNonEmptyStrings(raw.MatchedFiles, raw.MatchedFilesAlt)
	return nil
}

func (a *onlyMacsArtifactEvidenceAnchor) UnmarshalJSON(data []byte) error {
	type rawAnchor struct {
		Kind           string `json:"kind,omitempty"`
		LineStart      int    `json:"line_start,omitempty"`
		LineStartCamel int    `json:"lineStart,omitempty"`
		LineEnd        int    `json:"line_end,omitempty"`
		LineEndCamel   int    `json:"lineEnd,omitempty"`
		Text           string `json:"text,omitempty"`
	}

	var raw rawAnchor
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}

	a.Kind = raw.Kind
	a.LineStart = firstNonZero(raw.LineStart, raw.LineStartCamel)
	a.LineEnd = firstNonZero(raw.LineEnd, raw.LineEndCamel)
	a.Text = raw.Text
	return nil
}

func (m *onlyMacsArtifactManifest) UnmarshalJSON(data []byte) error {
	type rawManifest struct {
		Schema                   string                         `json:"schema,omitempty"`
		CapsuleID                string                         `json:"capsule_id,omitempty"`
		CapsuleIDCamel           string                         `json:"capsuleID,omitempty"`
		ID                       string                         `json:"id"`
		RequestID                string                         `json:"request_id,omitempty"`
		RequestIDCamel           string                         `json:"requestID,omitempty"`
		CreatedAt                string                         `json:"created_at,omitempty"`
		CreatedAtCamel           string                         `json:"createdAt,omitempty"`
		ExpiresAt                string                         `json:"expires_at,omitempty"`
		ExpiresAtCamel           string                         `json:"expiresAt,omitempty"`
		WorkspaceRoot            string                         `json:"workspace_root,omitempty"`
		WorkspaceRootCamel       string                         `json:"workspaceRoot,omitempty"`
		WorkspaceRootLabel       string                         `json:"workspace_root_label,omitempty"`
		WorkspaceRootLabelAlt    string                         `json:"workspaceRootLabel,omitempty"`
		WorkspaceFingerprint     string                         `json:"workspace_fingerprint,omitempty"`
		WorkspaceFingerprintAlt  string                         `json:"workspaceFingerprint,omitempty"`
		RouteScope               string                         `json:"route_scope,omitempty"`
		RouteScopeCamel          string                         `json:"routeScope,omitempty"`
		TrustTier                string                         `json:"trust_tier,omitempty"`
		TrustTierCamel           string                         `json:"trustTier,omitempty"`
		AbsolutePathsIncluded    bool                           `json:"absolute_paths_included,omitempty"`
		AbsolutePathsIncludedAlt bool                           `json:"absolutePathsIncluded,omitempty"`
		SwarmName                string                         `json:"swarm_name,omitempty"`
		SwarmNameCamel           string                         `json:"swarmName,omitempty"`
		ToolName                 string                         `json:"tool_name,omitempty"`
		ToolNameCamel            string                         `json:"toolName,omitempty"`
		PromptSummary            string                         `json:"prompt_summary,omitempty"`
		PromptSummaryCamel       string                         `json:"promptSummary,omitempty"`
		RequestIntent            string                         `json:"request_intent,omitempty"`
		RequestIntentCamel       string                         `json:"requestIntent,omitempty"`
		ExportMode               string                         `json:"export_mode,omitempty"`
		ExportModeCamel          string                         `json:"exportMode,omitempty"`
		OutputContract           string                         `json:"output_contract,omitempty"`
		OutputContractCamel      string                         `json:"outputContract,omitempty"`
		RequiredSections         []string                       `json:"required_sections,omitempty"`
		RequiredSectionsCamel    []string                       `json:"requiredSections,omitempty"`
		GroundingRules           []string                       `json:"grounding_rules,omitempty"`
		GroundingRulesCamel      []string                       `json:"groundingRules,omitempty"`
		ContextRequestRules      []string                       `json:"context_request_rules,omitempty"`
		ContextRequestRulesCamel []string                       `json:"contextRequestRules,omitempty"`
		Permissions              onlyMacsArtifactPermissions    `json:"permissions,omitempty"`
		Budgets                  onlyMacsArtifactBudgets        `json:"budgets,omitempty"`
		Lease                    onlyMacsArtifactLease          `json:"lease,omitempty"`
		Workspace                onlyMacsArtifactWorkspace      `json:"workspace,omitempty"`
		ContextPacks             []onlyMacsArtifactContextPack  `json:"context_packs,omitempty"`
		ContextPacksCamel        []onlyMacsArtifactContextPack  `json:"contextPacks,omitempty"`
		Files                    []onlyMacsArtifactManifestFile `json:"files"`
		Blocked                  []onlyMacsArtifactBlockedFile  `json:"blocked,omitempty"`
		Warnings                 []string                       `json:"warnings,omitempty"`
		Approval                 onlyMacsArtifactApproval       `json:"approval,omitempty"`
		TotalSelectedBytes       int                            `json:"total_selected_bytes,omitempty"`
		TotalSelectedBytesAlt    int                            `json:"totalSelectedBytes,omitempty"`
		TotalExportBytes         int                            `json:"total_export_bytes,omitempty"`
		TotalExportBytesAlt      int                            `json:"totalExportBytes,omitempty"`
	}

	var raw rawManifest
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}

	m.Schema = raw.Schema
	m.CapsuleID = firstNonEmpty(raw.CapsuleID, raw.CapsuleIDCamel)
	m.ID = raw.ID
	m.RequestID = firstNonEmpty(raw.RequestID, raw.RequestIDCamel)
	m.CreatedAt = firstNonEmpty(raw.CreatedAt, raw.CreatedAtCamel)
	m.ExpiresAt = firstNonEmpty(raw.ExpiresAt, raw.ExpiresAtCamel)
	m.WorkspaceRoot = firstNonEmpty(raw.WorkspaceRoot, raw.WorkspaceRootCamel)
	m.WorkspaceRootLabel = firstNonEmpty(raw.WorkspaceRootLabel, raw.WorkspaceRootLabelAlt)
	m.WorkspaceFingerprint = firstNonEmpty(raw.WorkspaceFingerprint, raw.WorkspaceFingerprintAlt)
	m.RouteScope = firstNonEmpty(raw.RouteScope, raw.RouteScopeCamel)
	m.TrustTier = firstNonEmpty(raw.TrustTier, raw.TrustTierCamel)
	m.AbsolutePathsIncluded = raw.AbsolutePathsIncluded || raw.AbsolutePathsIncludedAlt
	m.SwarmName = firstNonEmpty(raw.SwarmName, raw.SwarmNameCamel)
	m.ToolName = firstNonEmpty(raw.ToolName, raw.ToolNameCamel)
	m.PromptSummary = firstNonEmpty(raw.PromptSummary, raw.PromptSummaryCamel)
	m.RequestIntent = firstNonEmpty(raw.RequestIntent, raw.RequestIntentCamel)
	m.ExportMode = firstNonEmpty(raw.ExportMode, raw.ExportModeCamel)
	m.OutputContract = firstNonEmpty(raw.OutputContract, raw.OutputContractCamel)
	m.RequiredSections = firstNonEmptyStrings(raw.RequiredSections, raw.RequiredSectionsCamel)
	m.GroundingRules = firstNonEmptyStrings(raw.GroundingRules, raw.GroundingRulesCamel)
	m.ContextRequestRules = firstNonEmptyStrings(raw.ContextRequestRules, raw.ContextRequestRulesCamel)
	m.Permissions = raw.Permissions
	m.Budgets = raw.Budgets
	m.Lease = raw.Lease
	m.Workspace = raw.Workspace
	m.ContextPacks = firstNonEmptyContextPacks(raw.ContextPacks, raw.ContextPacksCamel)
	m.Files = raw.Files
	m.Blocked = raw.Blocked
	m.Warnings = raw.Warnings
	m.Approval = raw.Approval
	m.TotalSelectedBytes = firstNonZero(raw.TotalSelectedBytes, raw.TotalSelectedBytesAlt)
	m.TotalExportBytes = firstNonZero(raw.TotalExportBytes, raw.TotalExportBytesAlt)
	return nil
}

func (f *onlyMacsArtifactManifestFile) UnmarshalJSON(data []byte) error {
	type rawFile struct {
		Path               string                           `json:"path,omitempty"`
		RelativePath       string                           `json:"relative_path,omitempty"`
		RelativePathCamel  string                           `json:"relativePath,omitempty"`
		Category           string                           `json:"category,omitempty"`
		SelectionReason    string                           `json:"selection_reason,omitempty"`
		SelectionReasonAlt string                           `json:"selectionReason,omitempty"`
		IsRecommended      bool                             `json:"is_recommended,omitempty"`
		IsRecommendedAlt   bool                             `json:"isRecommended,omitempty"`
		ReviewPriority     int                              `json:"review_priority,omitempty"`
		ReviewPriorityAlt  int                              `json:"reviewPriority,omitempty"`
		EvidenceHints      []string                         `json:"evidence_hints,omitempty"`
		EvidenceHintsAlt   []string                         `json:"evidenceHints,omitempty"`
		EvidenceAnchors    []onlyMacsArtifactEvidenceAnchor `json:"evidence_anchors,omitempty"`
		EvidenceAnchorsAlt []onlyMacsArtifactEvidenceAnchor `json:"evidenceAnchors,omitempty"`
		OriginalBytes      int                              `json:"original_bytes,omitempty"`
		OriginalBytesCamel int                              `json:"originalBytes,omitempty"`
		ExportedBytes      int                              `json:"exported_bytes,omitempty"`
		ExportedBytesCamel int                              `json:"exportedBytes,omitempty"`
		Status             string                           `json:"status,omitempty"`
		Reason             string                           `json:"reason,omitempty"`
		SHA256             string                           `json:"sha256,omitempty"`
	}

	var raw rawFile
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}

	f.Path = raw.Path
	f.RelativePath = firstNonEmpty(raw.RelativePath, raw.RelativePathCamel)
	f.Category = raw.Category
	f.SelectionReason = firstNonEmpty(raw.SelectionReason, raw.SelectionReasonAlt)
	f.IsRecommended = raw.IsRecommended || raw.IsRecommendedAlt
	f.ReviewPriority = firstNonZero(raw.ReviewPriority, raw.ReviewPriorityAlt)
	f.EvidenceHints = firstNonEmptyStrings(raw.EvidenceHints, raw.EvidenceHintsAlt)
	f.EvidenceAnchors = firstNonEmptyEvidenceAnchors(raw.EvidenceAnchors, raw.EvidenceAnchorsAlt)
	f.OriginalBytes = firstNonZero(raw.OriginalBytes, raw.OriginalBytesCamel)
	f.ExportedBytes = firstNonZero(raw.ExportedBytes, raw.ExportedBytesCamel)
	f.Status = raw.Status
	f.Reason = raw.Reason
	f.SHA256 = raw.SHA256
	return nil
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}

func firstNonZero(values ...int) int {
	for _, value := range values {
		if value != 0 {
			return value
		}
	}
	return 0
}

func firstNonEmptyStrings(values ...[]string) []string {
	for _, value := range values {
		if len(value) > 0 {
			return value
		}
	}
	return nil
}

func firstNonEmptyEvidenceAnchors(values ...[]onlyMacsArtifactEvidenceAnchor) []onlyMacsArtifactEvidenceAnchor {
	for _, value := range values {
		if len(value) > 0 {
			return value
		}
	}
	return nil
}

func firstNonEmptyContextPacks(values ...[]onlyMacsArtifactContextPack) []onlyMacsArtifactContextPack {
	for _, value := range values {
		if len(value) > 0 {
			return value
		}
	}
	return nil
}
