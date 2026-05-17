package httpapi

import (
	"sync"
	"time"
)

const (
	defaultRequestedAgents        = 1
	defaultWorkspaceConcurrency   = 4
	defaultThreadConcurrency      = 2
	defaultGlobalConcurrency      = 8
	defaultWorkspaceQueueBudget   = 3
	defaultThreadQueueBudget      = 2
	defaultWorkspacePremiumBudget = 2
	defaultThreadPremiumBudget    = 1
	maxSwarmInputBytes            = 500_000
	maxSwarmFanoutBytes           = 1_500_000
	defaultQueueETASeconds        = 45
	staleQueuedSessionAfter       = 10 * time.Minute
	premiumCooldownAfterRelease   = 90 * time.Second
	routeScopeSwarm               = "swarm"
	routeScopeTrustedOnly         = "trusted_only"
	routeScopeLocalOnly           = "local_only"
)

type swarmPlanRequest struct {
	Title            string                   `json:"title,omitempty"`
	Model            string                   `json:"model"`
	RouteScope       string                   `json:"route_scope,omitempty"`
	Strategy         string                   `json:"strategy,omitempty"`
	RouteProviderID  string                   `json:"route_provider_id,omitempty"`
	PreferRemote     bool                     `json:"prefer_remote,omitempty"`
	PreferRemoteSoft bool                     `json:"prefer_remote_soft,omitempty"`
	OnlyMacsArtifact *onlyMacsArtifactPayload `json:"onlymacs_artifact,omitempty"`
	RequestedAgents  int                      `json:"requested_agents,omitempty"`
	MaxAgents        int                      `json:"max_agents,omitempty"`
	AllowFallback    bool                     `json:"allow_fallback,omitempty"`
	Scheduling       string                   `json:"scheduling,omitempty"`
	WorkspaceID      string                   `json:"workspace_id,omitempty"`
	ThreadID         string                   `json:"thread_id,omitempty"`
	IdempotencyKey   string                   `json:"idempotency_key,omitempty"`
	Prompt           string                   `json:"prompt,omitempty"`
	Messages         []chatMessage            `json:"messages,omitempty"`
}

type swarmContextEstimate struct {
	InputBytes      int    `json:"input_bytes"`
	EstimatedTokens int    `json:"estimated_tokens"`
	FanoutBytes     int    `json:"fanout_bytes"`
	ExceedsBudget   bool   `json:"exceeds_budget"`
	LimitReason     string `json:"limit_reason,omitempty"`
}

type swarmPlanResponse struct {
	SwarmID              string               `json:"swarm_id,omitempty"`
	Title                string               `json:"title,omitempty"`
	RequestedModel       string               `json:"requested_model"`
	ResolvedModel        string               `json:"resolved_model"`
	RouteScope           string               `json:"route_scope,omitempty"`
	Strategy             string               `json:"strategy,omitempty"`
	SelectionReason      string               `json:"selection_reason,omitempty"`
	SelectionExplanation string               `json:"selection_explanation,omitempty"`
	PreferRemote         bool                 `json:"prefer_remote,omitempty"`
	PreferRemoteSoft     bool                 `json:"prefer_remote_soft,omitempty"`
	Available            bool                 `json:"available"`
	RequestedAgents      int                  `json:"requested_agents"`
	MaxAgents            int                  `json:"max_agents"`
	AdmittedAgents       int                  `json:"admitted_agents"`
	QueueRemainder       int                  `json:"queue_remainder"`
	QueuePosition        int                  `json:"queue_position,omitempty"`
	QueueReason          string               `json:"queue_reason,omitempty"`
	ETASeconds           int                  `json:"eta_seconds,omitempty"`
	Scheduling           string               `json:"scheduling"`
	WorkspaceID          string               `json:"workspace_id,omitempty"`
	ThreadID             string               `json:"thread_id,omitempty"`
	IdempotencyKey       string               `json:"idempotency_key,omitempty"`
	ExecutionBoundary    string               `json:"execution_boundary"`
	FallbackUsed         bool                 `json:"fallback_used"`
	Context              swarmContextEstimate `json:"context"`
	CapabilityMatrix     []swarmCapabilityRow `json:"capability_matrix,omitempty"`
	WorkerRoles          []swarmWorkerRole    `json:"worker_roles,omitempty"`
	Quorum               *swarmQuorumPlan     `json:"quorum,omitempty"`
	Providers            []preflightProvider  `json:"providers"`
	AvailableModels      []model              `json:"available_models"`
	Totals               struct {
		Providers  int `json:"providers"`
		SlotsFree  int `json:"slots_free"`
		SlotsTotal int `json:"slots_total"`
	} `json:"totals"`
	Warnings []string `json:"warnings,omitempty"`
}

type swarmCapabilityRow struct {
	ProviderID              string  `json:"provider_id"`
	ProviderName            string  `json:"provider_name,omitempty"`
	OwnerMemberID           string  `json:"owner_member_id,omitempty"`
	OwnerMemberName         string  `json:"owner_member_name,omitempty"`
	CPU                     string  `json:"cpu,omitempty"`
	MemoryGB                int     `json:"memory_gb,omitempty"`
	BestModel               string  `json:"best_model,omitempty"`
	TotalModels             int     `json:"total_models"`
	SlotsFree               int     `json:"slots_free"`
	SlotsTotal              int     `json:"slots_total"`
	ActiveSessions          int     `json:"active_sessions"`
	CurrentLoad             int     `json:"current_load"`
	RecentTokensPerSecond   float64 `json:"recent_tokens_per_second,omitempty"`
	CapabilityTier          string  `json:"capability_tier,omitempty"`
	RouteTrust              string  `json:"route_trust,omitempty"`
	FileAccessApprovalState string  `json:"file_access_approval_state,omitempty"`
	AssignmentPolicy        string  `json:"assignment_policy,omitempty"`
	IdleReason              string  `json:"idle_reason,omitempty"`
	SuggestedRole           string  `json:"suggested_role,omitempty"`
	MaintenanceState        string  `json:"maintenance_state,omitempty"`
}

type swarmWorkerRole struct {
	ProviderID      string `json:"provider_id,omitempty"`
	OwnerMemberName string `json:"owner_member_name,omitempty"`
	Role            string `json:"role"`
	Model           string `json:"model,omitempty"`
	Rationale       string `json:"rationale,omitempty"`
}

type swarmQuorumPlan struct {
	Mode               string `json:"mode"`
	MinimumReviewers   int    `json:"minimum_reviewers"`
	PreferredReviewers int    `json:"preferred_reviewers"`
	Description        string `json:"description,omitempty"`
}

type swarmSessionReservation struct {
	ReservationID string `json:"reservation_id"`
	ProviderID    string `json:"provider_id"`
	ProviderName  string `json:"provider_name"`
	ModelID       string `json:"model_id"`
	Status        string `json:"status"`
}

type swarmCheckpoint struct {
	Status        string    `json:"status"`
	Partial       bool      `json:"partial"`
	OutputBytes   int       `json:"output_bytes"`
	OutputPreview string    `json:"output_preview,omitempty"`
	LastError     string    `json:"last_error,omitempty"`
	UpdatedAt     time.Time `json:"updated_at"`
}

type swarmSessionSummary struct {
	ID                   string                    `json:"id"`
	SwarmID              string                    `json:"swarm_id,omitempty"`
	Title                string                    `json:"title,omitempty"`
	Status               string                    `json:"status"`
	RequestedModel       string                    `json:"requested_model"`
	ResolvedModel        string                    `json:"resolved_model"`
	RouteScope           string                    `json:"route_scope,omitempty"`
	Strategy             string                    `json:"strategy,omitempty"`
	SelectionReason      string                    `json:"selection_reason,omitempty"`
	SelectionExplanation string                    `json:"selection_explanation,omitempty"`
	RouteSummary         string                    `json:"route_summary,omitempty"`
	PreferRemote         bool                      `json:"prefer_remote,omitempty"`
	PreferRemoteSoft     bool                      `json:"prefer_remote_soft,omitempty"`
	RequestedAgents      int                       `json:"requested_agents"`
	MaxAgents            int                       `json:"max_agents"`
	AdmittedAgents       int                       `json:"admitted_agents"`
	QueueRemainder       int                       `json:"queue_remainder"`
	QueuePosition        int                       `json:"queue_position,omitempty"`
	QueueReason          string                    `json:"queue_reason,omitempty"`
	ETASeconds           int                       `json:"eta_seconds,omitempty"`
	Scheduling           string                    `json:"scheduling"`
	WorkspaceID          string                    `json:"workspace_id,omitempty"`
	ThreadID             string                    `json:"thread_id,omitempty"`
	IdempotencyKey       string                    `json:"idempotency_key,omitempty"`
	ExecutionBoundary    string                    `json:"execution_boundary"`
	Context              swarmContextEstimate      `json:"context"`
	CapabilityMatrix     []swarmCapabilityRow      `json:"capability_matrix,omitempty"`
	WorkerRoles          []swarmWorkerRole         `json:"worker_roles,omitempty"`
	Quorum               *swarmQuorumPlan          `json:"quorum,omitempty"`
	OnlyMacsArtifact     *onlyMacsArtifactPayload  `json:"-"`
	Warnings             []string                  `json:"warnings,omitempty"`
	PreferredProviders   []string                  `json:"preferred_providers,omitempty"`
	Reservations         []swarmSessionReservation `json:"reservations,omitempty"`
	Checkpoint           *swarmCheckpoint          `json:"checkpoint,omitempty"`
	SavedTokensEstimate  int                       `json:"saved_tokens_estimate,omitempty"`
	Prompt               string                    `json:"-"`
	Messages             []chatMessage             `json:"-"`
	CreatedAt            time.Time                 `json:"created_at"`
	UpdatedAt            time.Time                 `json:"updated_at"`
}

type swarmSessionActionRequest struct {
	SessionID string `json:"session_id"`
}

type swarmSessionsResponse struct {
	Sessions []swarmSessionSummary `json:"sessions"`
}

type swarmQueueResponse struct {
	QueuedSessionCount int                   `json:"queued_session_count"`
	ActiveSessionCount int                   `json:"active_session_count"`
	QueueSummary       swarmQueueSummary     `json:"queue_summary"`
	Sessions           []swarmSessionSummary `json:"sessions"`
}

type swarmStartResponse struct {
	Session   swarmSessionSummary `json:"session"`
	Duplicate bool                `json:"duplicate"`
}

type swarmQueueSummary struct {
	QueuedSessionCount     int    `json:"queued_session_count"`
	PremiumContentionCount int    `json:"premium_contention_count"`
	PremiumBudgetCount     int    `json:"premium_budget_count"`
	PremiumCooldownCount   int    `json:"premium_cooldown_count"`
	CapacityWaitCount      int    `json:"capacity_wait_count"`
	WidthLimitedCount      int    `json:"width_limited_count"`
	RequesterBudgetCount   int    `json:"requester_budget_count"`
	MemberCapCount         int    `json:"member_cap_count"`
	StaleQueuedCount       int    `json:"stale_queued_count"`
	NextETASeconds         int    `json:"next_eta_seconds,omitempty"`
	MaxETASeconds          int    `json:"max_eta_seconds,omitempty"`
	PrimaryReason          string `json:"primary_reason,omitempty"`
	PrimaryDetail          string `json:"primary_detail,omitempty"`
	SuggestedAction        string `json:"suggested_action,omitempty"`
}

type swarmStore struct {
	mu          sync.RWMutex
	sessions    map[string]swarmSessionSummary
	idempotency map[string]string
	nextID      int
}

func newSwarmStore() *swarmStore {
	return &swarmStore{
		sessions:    make(map[string]swarmSessionSummary),
		idempotency: make(map[string]string),
	}
}
