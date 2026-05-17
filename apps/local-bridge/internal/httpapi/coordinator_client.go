package httpapi

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

type coordinatorClient struct {
	baseURL         string
	httpClient      *http.Client
	relayHTTPClient *http.Client
	credentials     *coordinatorCredentialStore
}

type coordinatorProvidersResponse struct {
	Providers []provider `json:"providers"`
}

type coordinatorProviderActivitiesResponse struct {
	Activities []providerActivity `json:"activities"`
}

type jobReportRequest struct {
	RunID                              string                  `json:"run_id,omitempty"`
	SessionID                          string                  `json:"session_id,omitempty"`
	SwarmID                            string                  `json:"swarm_id,omitempty"`
	SwarmName                          string                  `json:"swarm_name,omitempty"`
	SwarmVisibility                    string                  `json:"swarm_visibility,omitempty"`
	MemberID                           string                  `json:"member_id,omitempty"`
	MemberName                         string                  `json:"member_name,omitempty"`
	ProviderID                         string                  `json:"provider_id,omitempty"`
	ProviderName                       string                  `json:"provider_name,omitempty"`
	OwnerMemberName                    string                  `json:"owner_member_name,omitempty"`
	RouteScope                         string                  `json:"route_scope,omitempty"`
	ModelAlias                         string                  `json:"model_alias,omitempty"`
	Model                              string                  `json:"model,omitempty"`
	Status                             string                  `json:"status,omitempty"`
	Invocation                         string                  `json:"invocation,omitempty"`
	PromptPreview                      string                  `json:"prompt_preview,omitempty"`
	Summary                            string                  `json:"summary,omitempty"`
	ReportMarkdown                     string                  `json:"report_markdown,omitempty"`
	WorkerMembers                      []jobReportWorkerMember `json:"worker_members,omitempty"`
	Tickets                            []jobReportTicket       `json:"tickets,omitempty"`
	Metadata                           map[string]any          `json:"metadata,omitempty"`
	WhatWorked                         string                  `json:"what_worked,omitempty"`
	WhatBroke                          string                  `json:"what_broke,omitempty"`
	QualityNotes                       string                  `json:"quality_notes,omitempty"`
	ThroughputNotes                    string                  `json:"throughput_notes,omitempty"`
	UpstreamModelIssues                string                  `json:"upstream_model_issues,omitempty"`
	DownstreamValidationOrRepairIssues string                  `json:"downstream_validation_or_repair_issues,omitempty"`
	ResumeRestartIssues                string                  `json:"resume_restart_issues,omitempty"`
	SuggestedImprovements              string                  `json:"suggested_improvements,omitempty"`
	Source                             string                  `json:"source,omitempty"`
	Automatic                          bool                    `json:"automatic,omitempty"`
	Metrics                            map[string]any          `json:"metrics,omitempty"`
	EventsSummary                      map[string]any          `json:"events_summary,omitempty"`
	ClientBuild                        *clientBuild            `json:"client_build,omitempty"`
}

type jobReportWorkerMember struct {
	MemberID     string `json:"member_id,omitempty"`
	MemberName   string `json:"member_name,omitempty"`
	ProviderID   string `json:"provider_id,omitempty"`
	ProviderName string `json:"provider_name,omitempty"`
	Model        string `json:"model,omitempty"`
}

type jobReportTicket struct {
	ID                   string   `json:"id,omitempty"`
	StepID               string   `json:"step_id,omitempty"`
	Index                int      `json:"index,omitempty"`
	Title                string   `json:"title,omitempty"`
	Kind                 string   `json:"kind,omitempty"`
	Status               string   `json:"status,omitempty"`
	Filename             string   `json:"filename,omitempty"`
	TargetFiles          []string `json:"target_files,omitempty"`
	Validator            string   `json:"validator,omitempty"`
	Capability           string   `json:"capability,omitempty"`
	Dependencies         []string `json:"dependencies,omitempty"`
	LockGroup            string   `json:"lock_group,omitempty"`
	ContextReadMode      string   `json:"context_read_mode,omitempty"`
	ContextWriteMode     string   `json:"context_write_mode,omitempty"`
	StartItem            int      `json:"start_item,omitempty"`
	EndItem              int      `json:"end_item,omitempty"`
	Count                int      `json:"count,omitempty"`
	ProviderID           string   `json:"provider_id,omitempty"`
	ProviderName         string   `json:"provider_name,omitempty"`
	MemberName           string   `json:"member_name,omitempty"`
	Model                string   `json:"model,omitempty"`
	Attempt              int      `json:"attempt,omitempty"`
	LeaseID              string   `json:"lease_id,omitempty"`
	LeasedAt             string   `json:"leased_at,omitempty"`
	StartedAt            string   `json:"started_at,omitempty"`
	CompletedAt          string   `json:"completed_at,omitempty"`
	FailedAt             string   `json:"failed_at,omitempty"`
	UpdatedAt            string   `json:"updated_at,omitempty"`
	DurationSeconds      int      `json:"duration_seconds,omitempty"`
	WaitSeconds          int      `json:"wait_seconds,omitempty"`
	InputTokensEstimate  int      `json:"input_tokens_estimate,omitempty"`
	OutputBytes          int      `json:"output_bytes,omitempty"`
	OutputTokensEstimate int      `json:"output_tokens_estimate,omitempty"`
	Message              string   `json:"message,omitempty"`
}

type jobReportTicketSummary struct {
	Total                 int            `json:"total"`
	Completed             int            `json:"completed"`
	Active                int            `json:"active"`
	Queued                int            `json:"queued"`
	Failed                int            `json:"failed"`
	Repair                int            `json:"repair"`
	Retry                 int            `json:"retry"`
	Pending               int            `json:"pending"`
	Other                 int            `json:"other"`
	CompletedPercent      int            `json:"completed_percent"`
	TotalDurationSeconds  int            `json:"total_duration_seconds,omitempty"`
	TotalWaitSeconds      int            `json:"total_wait_seconds,omitempty"`
	InputTokensEstimate   int            `json:"input_tokens_estimate,omitempty"`
	OutputBytes           int            `json:"output_bytes,omitempty"`
	OutputTokensEstimate  int            `json:"output_tokens_estimate,omitempty"`
	OutputTokensPerSecond float64        `json:"output_tokens_per_second,omitempty"`
	StatusCounts          map[string]int `json:"status_counts,omitempty"`
	KindCounts            map[string]int `json:"kind_counts,omitempty"`
}

type jobReport struct {
	ID              string                  `json:"id"`
	RunID           string                  `json:"run_id,omitempty"`
	SessionID       string                  `json:"session_id,omitempty"`
	SwarmID         string                  `json:"swarm_id,omitempty"`
	SwarmName       string                  `json:"swarm_name,omitempty"`
	SwarmVisibility string                  `json:"swarm_visibility,omitempty"`
	MemberID        string                  `json:"member_id,omitempty"`
	MemberName      string                  `json:"member_name,omitempty"`
	WorkerMembers   []jobReportWorkerMember `json:"worker_members,omitempty"`
	Tickets         []jobReportTicket       `json:"tickets,omitempty"`
	TicketSummary   *jobReportTicketSummary `json:"ticket_summary,omitempty"`
	Status          string                  `json:"status,omitempty"`
	Source          string                  `json:"source,omitempty"`
	Automatic       bool                    `json:"automatic,omitempty"`
	ClientBuild     *clientBuild            `json:"client_build,omitempty"`
}

type jobReportResponse struct {
	Status string    `json:"status"`
	Report jobReport `json:"report"`
}

type coordinatorSwarmsResponse struct {
	Swarms []swarm `json:"swarms"`
}

type coordinatorSwarmMembersResponse struct {
	Swarm   swarm                `json:"swarm"`
	Members []swarmMemberSummary `json:"members"`
}

type createSwarmRequest struct {
	Name            string           `json:"name"`
	Visibility      string           `json:"visibility,omitempty"`
	Discoverability string           `json:"discoverability,omitempty"`
	OwnerMemberID   string           `json:"owner_member_id,omitempty"`
	OwnerMemberName string           `json:"owner_member_name,omitempty"`
	OwnerMode       string           `json:"owner_mode,omitempty"`
	JoinPassword    string           `json:"join_password,omitempty"`
	JoinPolicy      *swarmJoinPolicy `json:"join_policy,omitempty"`
	ClientBuild     *clientBuild     `json:"client_build,omitempty"`
}

type createSwarmResponse struct {
	Swarm       swarm                  `json:"swarm"`
	Member      *swarmMember           `json:"member,omitempty"`
	Credentials coordinatorCredentials `json:"credentials,omitempty"`
}

type swarmInvite struct {
	InviteToken string `json:"invite_token"`
	SwarmID     string `json:"swarm_id"`
	SwarmName   string `json:"swarm_name"`
	HostedPath  string `json:"hosted_path,omitempty"`
	InviteURL   string `json:"invite_url,omitempty"`
}

type createSwarmInviteResponse struct {
	Invite swarmInvite `json:"invite"`
}

type swarmMember struct {
	ID          string       `json:"id"`
	Name        string       `json:"name"`
	Mode        string       `json:"mode"`
	SwarmID     string       `json:"swarm_id"`
	Role        string       `json:"role,omitempty"`
	Trusted     bool         `json:"trusted,omitempty"`
	Paused      bool         `json:"paused,omitempty"`
	ClientBuild *clientBuild `json:"client_build,omitempty"`
}

type joinSwarmRequest struct {
	SwarmID      string       `json:"swarm_id,omitempty"`
	InviteToken  string       `json:"invite_token"`
	MemberID     string       `json:"member_id"`
	MemberName   string       `json:"member_name"`
	Mode         string       `json:"mode"`
	JoinPassword string       `json:"join_password,omitempty"`
	ClientBuild  *clientBuild `json:"client_build,omitempty"`
}

type joinSwarmResponse struct {
	Swarm       swarm                  `json:"swarm"`
	Member      swarmMember            `json:"member"`
	Credentials coordinatorCredentials `json:"credentials,omitempty"`
}

type upsertMemberRequest struct {
	SwarmID      string       `json:"swarm_id"`
	MemberID     string       `json:"member_id"`
	MemberName   string       `json:"member_name"`
	Mode         string       `json:"mode"`
	JoinPassword string       `json:"join_password,omitempty"`
	ClientBuild  *clientBuild `json:"client_build,omitempty"`
}

type upsertMemberResponse struct {
	Swarm       swarm                  `json:"swarm"`
	Member      swarmMember            `json:"member"`
	Credentials coordinatorCredentials `json:"credentials,omitempty"`
}

type coordinatorTokenResponse struct {
	Token      string `json:"token"`
	Scope      string `json:"scope"`
	SwarmID    string `json:"swarm_id,omitempty"`
	MemberID   string `json:"member_id,omitempty"`
	ProviderID string `json:"provider_id,omitempty"`
	DeviceID   string `json:"device_id,omitempty"`
	ExpiresAt  string `json:"expires_at,omitempty"`
}

type coordinatorCredentials struct {
	Requester *coordinatorTokenResponse `json:"requester,omitempty"`
	Provider  *coordinatorTokenResponse `json:"provider,omitempty"`
	Device    *coordinatorTokenResponse `json:"device,omitempty"`
}

type removeMemberRequest struct {
	SwarmID  string `json:"swarm_id"`
	MemberID string `json:"member_id"`
}

type removeMemberResponse struct {
	Status   string `json:"status"`
	SwarmID  string `json:"swarm_id"`
	MemberID string `json:"member_id"`
}

type swarm struct {
	ID              string              `json:"id"`
	Name            string              `json:"name"`
	Slug            string              `json:"slug,omitempty"`
	PublicPath      string              `json:"public_path,omitempty"`
	Visibility      string              `json:"visibility,omitempty"`
	Discoverability string              `json:"discoverability,omitempty"`
	JoinPolicy      *swarmJoinPolicy    `json:"join_policy,omitempty"`
	ContextPolicy   *swarmContextPolicy `json:"context_policy,omitempty"`
	MemberCount     int                 `json:"member_count"`
	ProviderCount   int                 `json:"provider_count"`
	SlotsFree       int                 `json:"slots_free"`
	SlotsTotal      int                 `json:"slots_total"`
}

type swarmJoinPolicy struct {
	Version            int      `json:"version"`
	Mode               string   `json:"mode"`
	Password           string   `json:"password,omitempty"`
	PasswordConfigured bool     `json:"password_configured,omitempty"`
	AllowedEmails      []string `json:"allowed_emails,omitempty"`
	AllowedDomains     []string `json:"allowed_domains,omitempty"`
	RequireApproval    bool     `json:"require_approval,omitempty"`
}

type swarmContextPolicy struct {
	Version                  int      `json:"version"`
	ContextReadMode          string   `json:"context_read_mode"`
	ContextWriteMode         string   `json:"context_write_mode"`
	AllowTestExecution       bool     `json:"allow_test_execution"`
	AllowDependencyInstall   bool     `json:"allow_dependency_install"`
	RequireFileLocks         bool     `json:"require_file_locks"`
	SecretGuardEnabled       bool     `json:"secret_guard_enabled"`
	MaxContextRequestRounds  int      `json:"max_context_request_rounds"`
	AllowedContextPacks      []string `json:"allowed_context_packs,omitempty"`
	DirectWriteRequiresAdmin bool     `json:"direct_write_requires_admin"`
}

type provider struct {
	ID                     string                `json:"id"`
	Name                   string                `json:"name"`
	SwarmID                string                `json:"swarm_id,omitempty"`
	OwnerMemberID          string                `json:"owner_member_id,omitempty"`
	OwnerMemberName        string                `json:"owner_member_name,omitempty"`
	Status                 string                `json:"status"`
	MaintenanceState       string                `json:"maintenance_state,omitempty"`
	Modes                  []string              `json:"modes"`
	Slots                  slots                 `json:"slots"`
	ActiveSessions         int                   `json:"active_sessions"`
	ActiveModel            string                `json:"active_model,omitempty"`
	ServedSessions         int                   `json:"served_sessions,omitempty"`
	FailedSessions         int                   `json:"failed_sessions,omitempty"`
	UploadedTokensEstimate int                   `json:"uploaded_tokens_estimate,omitempty"`
	RecentUploadedTokensPS float64               `json:"recent_uploaded_tokens_per_second,omitempty"`
	LastServedModel        string                `json:"last_served_model,omitempty"`
	Hardware               *hardwareProfile      `json:"hardware,omitempty"`
	ClientBuild            *clientBuild          `json:"client_build,omitempty"`
	RecommendedModels      []modelRecommendation `json:"recommended_models,omitempty"`
	Models                 []model               `json:"models"`
}

type swarmMemberCapabilitySummary struct {
	ProviderID             string                `json:"provider_id"`
	ProviderName           string                `json:"provider_name"`
	Status                 string                `json:"status"`
	MaintenanceState       string                `json:"maintenance_state,omitempty"`
	ActiveSessions         int                   `json:"active_sessions"`
	ActiveModel            string                `json:"active_model,omitempty"`
	Slots                  slots                 `json:"slots"`
	ModelCount             int                   `json:"model_count"`
	BestModel              string                `json:"best_model,omitempty"`
	RecentUploadedTokensPS float64               `json:"recent_uploaded_tokens_per_second,omitempty"`
	Hardware               *hardwareProfile      `json:"hardware,omitempty"`
	ClientBuild            *clientBuild          `json:"client_build,omitempty"`
	RecommendedModels      []modelRecommendation `json:"recommended_models,omitempty"`
	Models                 []model               `json:"models,omitempty"`
}

type swarmMemberSummary struct {
	MemberID               string                         `json:"member_id"`
	MemberName             string                         `json:"member_name"`
	Mode                   string                         `json:"mode"`
	SwarmID                string                         `json:"swarm_id"`
	Role                   string                         `json:"role,omitempty"`
	Trusted                bool                           `json:"trusted,omitempty"`
	Paused                 bool                           `json:"paused,omitempty"`
	Status                 string                         `json:"status"`
	MaintenanceState       string                         `json:"maintenance_state,omitempty"`
	LastSeenAt             string                         `json:"last_seen_at,omitempty"`
	ProviderCount          int                            `json:"provider_total"`
	ActiveJobsServing      int                            `json:"active_jobs_serving"`
	ActiveJobsConsuming    int                            `json:"active_jobs_consuming"`
	ActiveModel            string                         `json:"active_model,omitempty"`
	RecentUploadedTokensPS float64                        `json:"recent_uploaded_tokens_per_second,omitempty"`
	TotalModelsAvailable   int                            `json:"total_models_available"`
	BestModel              string                         `json:"best_model,omitempty"`
	Hardware               *hardwareProfile               `json:"hardware,omitempty"`
	ClientBuild            *clientBuild                   `json:"client_build,omitempty"`
	RecommendedModels      []modelRecommendation          `json:"recommended_models,omitempty"`
	Capabilities           []swarmMemberCapabilitySummary `json:"capabilities,omitempty"`
}

type hardwareProfile struct {
	CPUBrand string `json:"cpu_brand,omitempty"`
	MemoryGB int    `json:"memory_gb,omitempty"`
}

type clientBuild struct {
	Product        string `json:"product,omitempty"`
	Version        string `json:"version,omitempty"`
	BuildNumber    string `json:"build_number,omitempty"`
	BuildTimestamp string `json:"build_timestamp,omitempty"`
	Channel        string `json:"channel,omitempty"`
}

type providerActivity struct {
	ID                      string `json:"id"`
	JobID                   string `json:"job_id,omitempty"`
	SessionID               string `json:"session_id,omitempty"`
	SwarmID                 string `json:"swarm_id,omitempty"`
	SwarmName               string `json:"swarm_name,omitempty"`
	ProviderID              string `json:"provider_id"`
	ProviderName            string `json:"provider_name,omitempty"`
	OwnerMemberID           string `json:"owner_member_id,omitempty"`
	OwnerMemberName         string `json:"owner_member_name,omitempty"`
	RequesterMemberID       string `json:"requester_member_id,omitempty"`
	RequesterMemberName     string `json:"requester_member_name,omitempty"`
	ResolvedModel           string `json:"resolved_model,omitempty"`
	Stream                  bool   `json:"stream,omitempty"`
	Status                  string `json:"status"`
	StatusCode              int    `json:"status_code,omitempty"`
	UploadedBytes           int    `json:"uploaded_bytes,omitempty"`
	UploadedTokensEstimate  int    `json:"uploaded_tokens_estimate,omitempty"`
	OutputBytes             int    `json:"output_bytes,omitempty"`
	GeneratedOutputBytes    int    `json:"generated_output_bytes,omitempty"`
	GeneratedReasoningBytes int    `json:"generated_reasoning_bytes,omitempty"`
	GeneratedTokensEstimate int    `json:"generated_tokens_estimate,omitempty"`
	OutputPreview           string `json:"output_preview,omitempty"`
	FinalBodyBase64         string `json:"final_body_base64,omitempty"`
	Partial                 bool   `json:"partial,omitempty"`
	LastProgressAt          string `json:"last_progress_at,omitempty"`
	StartedAt               string `json:"started_at,omitempty"`
	UpdatedAt               string `json:"updated_at,omitempty"`
	CompletedAt             string `json:"completed_at,omitempty"`
	Error                   string `json:"error,omitempty"`
}

type registerProviderRequest struct {
	Provider provider `json:"provider"`
}

type registerProviderResponse struct {
	Status      string                 `json:"status"`
	Provider    provider               `json:"provider"`
	Credentials coordinatorCredentials `json:"credentials,omitempty"`
}

type unregisterProviderRequest struct {
	ProviderID string `json:"provider_id"`
}

type unregisterProviderResponse struct {
	Status     string `json:"status"`
	ProviderID string `json:"provider_id"`
}

type model struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	SlotsFree  int    `json:"slots_free"`
	SlotsTotal int    `json:"slots_total"`
}

type modelRecommendation struct {
	ID        string   `json:"id"`
	Name      string   `json:"name,omitempty"`
	Tier      string   `json:"tier,omitempty"`
	Reason    string   `json:"reason,omitempty"`
	MinRAMGB  int      `json:"min_ram_gb,omitempty"`
	TaskKinds []string `json:"task_kinds,omitempty"`
}

type slots struct {
	Free  int `json:"free"`
	Total int `json:"total"`
}

type preflightRequest struct {
	Model               string   `json:"model"`
	SwarmID             string   `json:"swarm_id,omitempty"`
	MaxProviders        int      `json:"max_providers,omitempty"`
	RequesterMemberID   string   `json:"requester_member_id,omitempty"`
	RequesterMemberName string   `json:"requester_member_name,omitempty"`
	RouteScope          string   `json:"route_scope,omitempty"`
	RouteProviderID     string   `json:"route_provider_id,omitempty"`
	PreferRemote        bool     `json:"prefer_remote,omitempty"`
	PreferRemoteSoft    bool     `json:"prefer_remote_soft,omitempty"`
	AvoidProviderIDs    []string `json:"avoid_provider_ids,omitempty"`
	ExcludeProviderIDs  []string `json:"exclude_provider_ids,omitempty"`
}

type preflightResponse struct {
	RequestedModel              string              `json:"requested_model"`
	ResolvedModel               string              `json:"resolved_model"`
	RouteScope                  string              `json:"route_scope,omitempty"`
	SelectionReason             string              `json:"selection_reason,omitempty"`
	SelectionExplanation        string              `json:"selection_explanation,omitempty"`
	Available                   bool                `json:"available"`
	RequesterActiveReservations int                 `json:"requester_active_reservations,omitempty"`
	RequesterReservationCap     int                 `json:"requester_reservation_cap,omitempty"`
	RequesterReservationBlocked bool                `json:"requester_reservation_blocked,omitempty"`
	Providers                   []preflightProvider `json:"providers"`
	AvailableModels             []model             `json:"available_models"`
	Totals                      struct {
		Providers  int `json:"providers"`
		SlotsFree  int `json:"slots_free"`
		SlotsTotal int `json:"slots_total"`
	} `json:"totals"`
}

type preflightProvider struct {
	ID                     string                `json:"id"`
	Name                   string                `json:"name"`
	OwnerMemberID          string                `json:"owner_member_id,omitempty"`
	OwnerMemberName        string                `json:"owner_member_name,omitempty"`
	Status                 string                `json:"status"`
	MaintenanceState       string                `json:"maintenance_state,omitempty"`
	ActiveSessions         int                   `json:"active_sessions"`
	ActiveModel            string                `json:"active_model,omitempty"`
	RecentUploadedTokensPS float64               `json:"recent_uploaded_tokens_per_second,omitempty"`
	MatchingModels         []model               `json:"matching_models"`
	Slots                  slots                 `json:"slots"`
	Hardware               *hardwareProfile      `json:"hardware,omitempty"`
	ClientBuild            *clientBuild          `json:"client_build,omitempty"`
	RecommendedModels      []modelRecommendation `json:"recommended_models,omitempty"`
}

type reserveSessionRequest struct {
	Model               string   `json:"model"`
	SwarmID             string   `json:"swarm_id,omitempty"`
	PreferredProviderID string   `json:"preferred_provider_id,omitempty"`
	AvoidProviderIDs    []string `json:"avoid_provider_ids,omitempty"`
	ExcludeProviderIDs  []string `json:"exclude_provider_ids,omitempty"`
	RequesterMemberID   string   `json:"requester_member_id,omitempty"`
	RequesterMemberName string   `json:"requester_member_name,omitempty"`
	RouteScope          string   `json:"route_scope,omitempty"`
	RouteProviderID     string   `json:"route_provider_id,omitempty"`
}

type reserveSessionResponse struct {
	SessionID     string            `json:"session_id"`
	Status        string            `json:"status"`
	ResolvedModel string            `json:"resolved_model"`
	Provider      preflightProvider `json:"provider"`
}

type releaseSessionRequest struct {
	SessionID           string `json:"session_id"`
	SwarmID             string `json:"swarm_id,omitempty"`
	RequesterMemberID   string `json:"requester_member_id,omitempty"`
	RequesterMemberName string `json:"requester_member_name,omitempty"`
}

type releaseSessionResponse struct {
	SessionID string `json:"session_id"`
	Status    string `json:"status"`
}

type coordinatorCommunityBoostSummary struct {
	Level        int      `json:"level"`
	Label        string   `json:"label"`
	MetricLabel  string   `json:"metric_label,omitempty"`
	PrimaryTrait string   `json:"primary_trait,omitempty"`
	Traits       []string `json:"traits,omitempty"`
	Detail       string   `json:"detail,omitempty"`
}

type memberSummaryResponse struct {
	MemberID               string                           `json:"member_id"`
	MemberName             string                           `json:"member_name"`
	SwarmID                string                           `json:"swarm_id"`
	SwarmMemberCount       int                              `json:"swarm_member_count,omitempty"`
	SwarmProviderCount     int                              `json:"swarm_provider_count,omitempty"`
	ProviderCount          int                              `json:"provider_count"`
	ActiveReservations     int                              `json:"active_reservations"`
	ReservationCap         int                              `json:"reservation_cap"`
	ServedSessions         int                              `json:"served_sessions"`
	UploadedTokensEstimate int                              `json:"uploaded_tokens_estimate"`
	BestPublishedModel     string                           `json:"best_published_model,omitempty"`
	CommunityBoost         coordinatorCommunityBoostSummary `json:"community_boost"`
}

type relayExecuteRequest struct {
	SessionID     string          `json:"session_id"`
	ProviderID    string          `json:"provider_id"`
	ResolvedModel string          `json:"resolved_model"`
	Stream        bool            `json:"stream,omitempty"`
	Request       json.RawMessage `json:"request"`
}

type relayExecuteResponse struct {
	JobID       string `json:"job_id"`
	StatusCode  int    `json:"status_code"`
	ContentType string `json:"content_type"`
	BodyBase64  string `json:"body_base64"`
}

type providerRelayPollRequest struct {
	ProviderID string `json:"provider_id"`
}

type providerRelayPollResponse struct {
	JobID         string          `json:"job_id"`
	SessionID     string          `json:"session_id"`
	ResolvedModel string          `json:"resolved_model"`
	Stream        bool            `json:"stream,omitempty"`
	Request       json.RawMessage `json:"request"`
	LeaseToken    string          `json:"lease_token,omitempty"`
}

type providerRelayChunkRequest struct {
	JobID       string `json:"job_id"`
	ProviderID  string `json:"provider_id,omitempty"`
	LeaseToken  string `json:"lease_token,omitempty"`
	StatusCode  int    `json:"status_code"`
	ContentType string `json:"content_type"`
	BodyBase64  string `json:"body_base64"`
}

type providerRelayChunkResponse struct {
	Status string `json:"status"`
	JobID  string `json:"job_id"`
}

type providerRelayCompleteRequest struct {
	JobID       string `json:"job_id"`
	ProviderID  string `json:"provider_id,omitempty"`
	LeaseToken  string `json:"lease_token,omitempty"`
	StatusCode  int    `json:"status_code"`
	ContentType string `json:"content_type"`
	BodyBase64  string `json:"body_base64"`
}

type providerRelayCompleteResponse struct {
	Status string `json:"status"`
	JobID  string `json:"job_id"`
}

type rotateCoordinatorCredentialResponse struct {
	Credential coordinatorTokenResponse `json:"credential"`
}

type Config struct {
	CoordinatorURL            string
	HTTPClient                *http.Client
	RelayHTTPClient           *http.Client
	CannedChat                bool
	OllamaURL                 string
	InferenceHTTPClient       *http.Client
	EnableProviderRelayWorker bool
	DisableSwarmExecution     bool
	ClientBuild               *clientBuild
	RuntimeStatePath          string
}

func defaultConfig() Config {
	return Config{
		CoordinatorURL: "http://127.0.0.1:4319",
		HTTPClient: &http.Client{
			Timeout: 3 * time.Second,
		},
		RelayHTTPClient:           &http.Client{},
		OllamaURL:                 "http://127.0.0.1:11434",
		InferenceHTTPClient:       &http.Client{},
		EnableProviderRelayWorker: true,
	}
}

func newCoordinatorClient(cfg Config) *coordinatorClient {
	httpClient := cfg.HTTPClient
	if httpClient == nil {
		httpClient = defaultConfig().HTTPClient
	}
	relayHTTPClient := cfg.RelayHTTPClient
	if relayHTTPClient == nil {
		relayHTTPClient = defaultConfig().RelayHTTPClient
	}

	return &coordinatorClient{
		baseURL:         strings.TrimRight(cfg.CoordinatorURL, "/"),
		httpClient:      httpClient,
		relayHTTPClient: relayHTTPClient,
		credentials:     newCoordinatorCredentialStore(cfg.RuntimeStatePath),
	}
}

func (c *coordinatorClient) providers(swarmID string) (coordinatorProvidersResponse, error) {
	return c.providersWithContext(context.Background(), swarmID)
}

func (c *coordinatorClient) providersWithContext(ctx context.Context, swarmID string) (coordinatorProvidersResponse, error) {
	var resp coordinatorProvidersResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	endpoint := c.baseURL + "/admin/v1/providers"
	if strings.TrimSpace(swarmID) != "" {
		endpoint += "?swarm_id=" + url.QueryEscape(swarmID)
	}

	memberID, _ := localMemberIdentity()
	token := c.requesterToken(swarmID, memberID)
	if token == "" && strings.TrimSpace(swarmID) == "" {
		token = c.firstRequesterToken()
	}
	if token == "" {
		providerID, _ := localProviderIdentity()
		token = c.providerToken(providerID)
	}
	if err := c.getJSONWithToken(ctx, endpoint, token, &resp); err != nil {
		return resp, err
	}
	return resp, nil
}

func (c *coordinatorClient) providerActivities(providerID string, ownerMemberID string, swarmID string, limit int) (coordinatorProviderActivitiesResponse, error) {
	return c.providerActivitiesForSession(providerID, ownerMemberID, swarmID, "", limit)
}

func (c *coordinatorClient) providerActivitiesForSession(providerID string, ownerMemberID string, swarmID string, sessionID string, limit int) (coordinatorProviderActivitiesResponse, error) {
	var resp coordinatorProviderActivitiesResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	query := url.Values{}
	if strings.TrimSpace(providerID) != "" {
		query.Set("provider_id", strings.TrimSpace(providerID))
	}
	if strings.TrimSpace(ownerMemberID) != "" {
		query.Set("owner_member_id", strings.TrimSpace(ownerMemberID))
	}
	if strings.TrimSpace(swarmID) != "" {
		query.Set("swarm_id", strings.TrimSpace(swarmID))
	}
	if strings.TrimSpace(sessionID) != "" {
		query.Set("session_id", strings.TrimSpace(sessionID))
	}
	if limit > 0 {
		query.Set("limit", fmt.Sprintf("%d", limit))
	}

	endpoint := c.baseURL + "/admin/v1/providers/activity"
	if encoded := query.Encode(); encoded != "" {
		endpoint += "?" + encoded
	}

	token := c.requesterToken(swarmID, ownerMemberID)
	if token == "" && strings.TrimSpace(providerID) != "" {
		token = c.providerToken(providerID)
	}
	httpReq, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return resp, err
	}
	addCoordinatorBearer(httpReq, token)
	httpResp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return resp, err
	}
	defer httpResp.Body.Close()

	if httpResp.StatusCode != http.StatusOK {
		return resp, newCoordinatorHTTPError(httpResp)
	}

	if err := json.NewDecoder(httpResp.Body).Decode(&resp); err != nil {
		return resp, err
	}

	return resp, nil
}

func (c *coordinatorClient) swarms() (coordinatorSwarmsResponse, error) {
	return c.swarmsWithContext(context.Background())
}

func (c *coordinatorClient) swarmsWithContext(ctx context.Context) (coordinatorSwarmsResponse, error) {
	var resp coordinatorSwarmsResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	token := c.firstRequesterToken()
	if err := c.getJSONWithToken(ctx, c.baseURL+"/admin/v1/swarms", token, &resp); err != nil {
		if token != "" && isUnauthorizedCoordinatorError(err) {
			return resp, c.getJSONWithToken(ctx, c.baseURL+"/admin/v1/swarms", "", &resp)
		}
		return resp, err
	}
	return resp, nil
}

func (c *coordinatorClient) submitJobReport(ctx context.Context, req jobReportRequest) (jobReportResponse, error) {
	var resp jobReportResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	body, err := json.Marshal(req)
	if err != nil {
		return resp, err
	}
	if err := c.postJSON(ctx, c.baseURL+"/v1/job-reports", body, http.StatusCreated, &resp); err != nil {
		return resp, err
	}
	return resp, nil
}

func (c *coordinatorClient) memberSummary(swarmID string, memberID string) (memberSummaryResponse, error) {
	return c.memberSummaryWithContext(context.Background(), swarmID, memberID)
}

func (c *coordinatorClient) memberSummaryWithContext(ctx context.Context, swarmID string, memberID string) (memberSummaryResponse, error) {
	var resp memberSummaryResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	endpoint := c.baseURL + "/admin/v1/members/summary?swarm_id=" + url.QueryEscape(strings.TrimSpace(swarmID)) + "&member_id=" + url.QueryEscape(strings.TrimSpace(memberID))
	if err := c.getJSONWithToken(ctx, endpoint, c.requesterToken(swarmID, memberID), &resp); err != nil {
		return resp, err
	}
	return resp, nil
}

func (c *coordinatorClient) getJSON(ctx context.Context, endpoint string, target any) error {
	return c.getJSONWithToken(ctx, endpoint, "", target)
}

func (c *coordinatorClient) getJSONWithToken(ctx context.Context, endpoint string, token string, target any) error {
	if ctx == nil {
		ctx = context.Background()
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return err
	}
	addCoordinatorBearer(httpReq, token)
	httpResp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return err
	}
	defer httpResp.Body.Close()

	if httpResp.StatusCode != http.StatusOK {
		return newCoordinatorHTTPError(httpResp)
	}

	return json.NewDecoder(httpResp.Body).Decode(target)
}

func (c *coordinatorClient) postJSON(ctx context.Context, endpoint string, body []byte, expectedStatus int, target any) error {
	return c.postJSONWithToken(ctx, endpoint, body, expectedStatus, "", target)
}

func (c *coordinatorClient) postJSONWithToken(ctx context.Context, endpoint string, body []byte, expectedStatus int, token string, target any) error {
	if ctx == nil {
		ctx = context.Background()
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	addCoordinatorBearer(httpReq, token)
	httpResp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return err
	}
	defer httpResp.Body.Close()

	if httpResp.StatusCode != expectedStatus {
		return newCoordinatorHTTPError(httpResp)
	}

	return json.NewDecoder(httpResp.Body).Decode(target)
}

func addCoordinatorBearer(req *http.Request, token string) {
	token = strings.TrimSpace(token)
	if req == nil || token == "" {
		return
	}
	req.Header.Set("Authorization", "Bearer "+token)
}

func (c *coordinatorClient) requesterToken(swarmID string, memberID string) string {
	if c == nil || c.credentials == nil {
		return ""
	}
	return c.credentials.requesterToken(swarmID, memberID)
}

func (c *coordinatorClient) requesterTokenFor(swarmID string, memberID string) string {
	if token := c.requesterToken(swarmID, memberID); token != "" {
		return token
	}
	return c.firstRequesterToken()
}

func (c *coordinatorClient) firstRequesterToken() string {
	if c == nil || c.credentials == nil {
		return ""
	}
	return c.credentials.firstRequesterToken()
}

func (c *coordinatorClient) providerToken(providerID string) string {
	if c == nil || c.credentials == nil {
		return ""
	}
	return c.credentials.providerToken(providerID)
}

func (c *coordinatorClient) forgetRequesterToken(swarmID string, memberID string) {
	if c == nil || c.credentials == nil {
		return
	}
	c.credentials.forgetRequesterToken(swarmID, memberID)
}

func (c *coordinatorClient) forgetProviderToken(providerID string) {
	if c == nil || c.credentials == nil {
		return
	}
	c.credentials.forgetProviderToken(providerID)
}

func (c *coordinatorClient) firstProviderToken() string {
	if c == nil || c.credentials == nil {
		return ""
	}
	return c.credentials.firstProviderToken()
}

func (c *coordinatorClient) rememberCredentials(credentials coordinatorCredentials) {
	if c == nil || c.credentials == nil {
		return
	}
	c.credentials.remember(credentials)
}

func (c *coordinatorClient) proxyJSON(ctx context.Context, method string, requestURI string, body []byte) (int, []byte, string, error) {
	if ctx == nil {
		ctx = context.Background()
	}
	if c.baseURL == "" {
		return 0, nil, "", fmt.Errorf("coordinator URL is not configured")
	}
	endpoint, normalizedRequestURI, err := c.proxyEndpoint(requestURI)
	if err != nil {
		return 0, nil, "", fmt.Errorf("unsupported coordinator proxy path")
	}
	httpReq, err := http.NewRequestWithContext(ctx, method, endpoint, bytes.NewReader(body)) // #nosec G704 -- endpoint is built by proxyEndpoint from configured baseURL plus allowlisted job-board path.
	if err != nil {
		return 0, nil, "", err
	}
	if len(body) > 0 {
		httpReq.Header.Set("Content-Type", "application/json")
	}
	addCoordinatorBearer(httpReq, c.proxyToken(method, normalizedRequestURI, body))
	httpResp, err := c.httpClient.Do(httpReq) // #nosec G704 -- request URL is constrained by proxyEndpoint above.
	if err != nil {
		return 0, nil, "", err
	}
	defer httpResp.Body.Close()
	respBody, err := io.ReadAll(httpResp.Body)
	if err != nil {
		return httpResp.StatusCode, nil, httpResp.Header.Get("Content-Type"), err
	}
	return httpResp.StatusCode, respBody, httpResp.Header.Get("Content-Type"), nil
}

func (c *coordinatorClient) proxyEndpoint(requestURI string) (string, string, error) {
	parsedRequest, err := url.ParseRequestURI(strings.TrimSpace(requestURI))
	if err != nil {
		return "", "", err
	}
	if parsedRequest.Scheme != "" || parsedRequest.Host != "" {
		return "", "", fmt.Errorf("absolute proxy URL is not allowed")
	}
	if parsedRequest.Path != "/admin/v1/jobs" && !strings.HasPrefix(parsedRequest.Path, "/admin/v1/jobs/") {
		return "", "", fmt.Errorf("unsupported coordinator proxy path")
	}
	base, err := url.Parse(c.baseURL)
	if err != nil || base.Scheme == "" || base.Host == "" {
		return "", "", fmt.Errorf("coordinator URL is invalid")
	}
	base.Path = parsedRequest.Path
	base.RawQuery = parsedRequest.RawQuery
	base.Fragment = ""
	normalized := parsedRequest.Path
	if parsedRequest.RawQuery != "" {
		normalized += "?" + parsedRequest.RawQuery
	}
	return base.String(), normalized, nil
}

func (c *coordinatorClient) proxyToken(method string, requestURI string, body []byte) string {
	path := strings.TrimSpace(requestURI)
	query := url.Values{}
	if parsed, err := url.ParseRequestURI(requestURI); err == nil {
		path = parsed.Path
		query = parsed.Query()
	}
	payload := map[string]any{}
	if len(body) > 0 && json.Valid(body) {
		_ = json.Unmarshal(body, &payload)
	}

	if method == http.MethodPost && strings.Contains(path, "/tickets/") &&
		(strings.HasSuffix(path, "/tickets/claim") || !strings.HasSuffix(path, "/tickets")) {
		providerID := stringValue(payload["provider_id"])
		if providerID == "" {
			providerID, _ = localProviderIdentity()
		}
		if token := c.providerToken(providerID); token != "" {
			return token
		}
		if token := c.firstProviderToken(); token != "" {
			return token
		}
	}

	swarmID := strings.TrimSpace(query.Get("swarm_id"))
	if swarmID == "" {
		swarmID = stringValue(payload["swarm_id"])
	}
	memberID := stringValue(payload["requester_member_id"])
	if memberID == "" {
		memberID = stringValue(payload["member_id"])
	}
	if memberID == "" {
		memberID, _ = localMemberIdentity()
	}
	if token := c.requesterToken(swarmID, memberID); token != "" {
		return token
	}
	return c.firstRequesterToken()
}

func (c *coordinatorClient) swarmMembers(swarmID string) (coordinatorSwarmMembersResponse, error) {
	var resp coordinatorSwarmMembersResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	endpoint := c.baseURL + "/admin/v1/swarms/members?swarm_id=" + url.QueryEscape(strings.TrimSpace(swarmID))
	memberID, _ := localMemberIdentity()
	httpReq, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return resp, err
	}
	addCoordinatorBearer(httpReq, c.requesterToken(swarmID, memberID))
	httpResp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return resp, err
	}
	defer httpResp.Body.Close()

	if httpResp.StatusCode != http.StatusOK {
		return resp, newCoordinatorHTTPError(httpResp)
	}

	if err := json.NewDecoder(httpResp.Body).Decode(&resp); err != nil {
		return resp, err
	}

	return resp, nil
}

func (c *coordinatorClient) createSwarm(req createSwarmRequest) (createSwarmResponse, error) {
	var resp createSwarmResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	body, err := json.Marshal(req)
	if err != nil {
		return resp, err
	}

	token := c.requesterToken("", req.OwnerMemberID)
	if token == "" {
		token = c.firstRequesterToken()
	}
	if err := c.postJSONWithToken(context.Background(), c.baseURL+"/admin/v1/swarms", body, http.StatusCreated, token, &resp); err != nil {
		return resp, err
	}
	c.rememberCredentials(resp.Credentials)

	return resp, nil
}

func (c *coordinatorClient) createInvite(swarmID string) (createSwarmInviteResponse, error) {
	var resp createSwarmInviteResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	memberID, _ := localMemberIdentity()
	httpReq, err := http.NewRequest(http.MethodPost, c.baseURL+"/admin/v1/swarms/"+url.PathEscape(swarmID)+"/invites", http.NoBody)
	if err != nil {
		return resp, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	addCoordinatorBearer(httpReq, c.requesterToken(swarmID, memberID))
	httpResp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return resp, err
	}
	defer httpResp.Body.Close()

	if httpResp.StatusCode != http.StatusCreated {
		return resp, newCoordinatorHTTPError(httpResp)
	}

	if err := json.NewDecoder(httpResp.Body).Decode(&resp); err != nil {
		return resp, err
	}

	return resp, nil
}

func (c *coordinatorClient) joinSwarm(req joinSwarmRequest) (joinSwarmResponse, error) {
	var resp joinSwarmResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	body, err := json.Marshal(req)
	if err != nil {
		return resp, err
	}

	httpResp, err := c.httpClient.Post(c.baseURL+"/admin/v1/swarms/join", "application/json", bytes.NewReader(body))
	if err != nil {
		return resp, err
	}
	defer httpResp.Body.Close()

	if httpResp.StatusCode != http.StatusOK {
		return resp, newCoordinatorHTTPError(httpResp)
	}

	if err := json.NewDecoder(httpResp.Body).Decode(&resp); err != nil {
		return resp, err
	}
	c.rememberCredentials(resp.Credentials)

	return resp, nil
}

func (c *coordinatorClient) upsertMember(req upsertMemberRequest) (upsertMemberResponse, error) {
	return c.upsertMemberWithContext(context.Background(), req)
}

func (c *coordinatorClient) upsertMemberWithContext(ctx context.Context, req upsertMemberRequest) (upsertMemberResponse, error) {
	var resp upsertMemberResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	body, err := json.Marshal(req)
	if err != nil {
		return resp, err
	}

	token := c.requesterToken(req.SwarmID, req.MemberID)
	if err := c.postJSONWithToken(ctx, c.baseURL+"/admin/v1/swarms/members/upsert", body, http.StatusOK, token, &resp); err != nil {
		if token != "" && isUnauthorizedCoordinatorError(err) {
			c.forgetRequesterToken(req.SwarmID, req.MemberID)
			if retryErr := c.postJSONWithToken(ctx, c.baseURL+"/admin/v1/swarms/members/upsert", body, http.StatusOK, "", &resp); retryErr == nil {
				c.rememberCredentials(resp.Credentials)
				return resp, nil
			}
		}
		return resp, err
	}
	c.rememberCredentials(resp.Credentials)
	return resp, nil
}

func (c *coordinatorClient) removeMember(req removeMemberRequest) (removeMemberResponse, error) {
	return c.removeMemberWithContext(context.Background(), req)
}

func (c *coordinatorClient) removeMemberWithContext(ctx context.Context, req removeMemberRequest) (removeMemberResponse, error) {
	var resp removeMemberResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	body, err := json.Marshal(req)
	if err != nil {
		return resp, err
	}

	memberID, _ := localMemberIdentity()
	if err := c.postJSONWithToken(ctx, c.baseURL+"/admin/v1/swarms/members/remove", body, http.StatusOK, c.requesterToken(req.SwarmID, memberID), &resp); err != nil {
		return resp, err
	}
	return resp, nil
}

func (c *coordinatorClient) rotateRequesterCredential(ctx context.Context, swarmID string, memberID string) (coordinatorTokenResponse, error) {
	return c.rotateCredential(ctx, c.requesterToken(swarmID, memberID))
}

func (c *coordinatorClient) rotateProviderCredential(ctx context.Context, providerID string) (coordinatorTokenResponse, error) {
	return c.rotateCredential(ctx, c.providerToken(providerID))
}

func (c *coordinatorClient) rotateCredential(ctx context.Context, token string) (coordinatorTokenResponse, error) {
	var resp rotateCoordinatorCredentialResponse
	if c.baseURL == "" {
		return coordinatorTokenResponse{}, fmt.Errorf("coordinator URL is not configured")
	}
	if strings.TrimSpace(token) == "" {
		return coordinatorTokenResponse{}, fmt.Errorf("coordinator credential is not available")
	}
	if err := c.postJSONWithToken(ctx, c.baseURL+"/admin/v1/credentials/rotate", nil, http.StatusOK, token, &resp); err != nil {
		return coordinatorTokenResponse{}, err
	}
	if c.credentials != nil {
		c.credentials.rememberToken(resp.Credential)
	}
	return resp.Credential, nil
}

func (c *coordinatorClient) preflight(req preflightRequest) (preflightResponse, error) {
	var resp preflightResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	body, err := json.Marshal(req)
	if err != nil {
		return resp, err
	}

	httpReq, err := http.NewRequest(http.MethodPost, c.baseURL+"/admin/v1/preflight", bytes.NewReader(body))
	if err != nil {
		return resp, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	addCoordinatorBearer(httpReq, c.requesterToken(req.SwarmID, req.RequesterMemberID))
	httpResp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return resp, err
	}
	defer httpResp.Body.Close()

	if httpResp.StatusCode != http.StatusOK {
		return resp, newCoordinatorHTTPError(httpResp)
	}

	if err := json.NewDecoder(httpResp.Body).Decode(&resp); err != nil {
		return resp, err
	}

	return resp, nil
}

func (c *coordinatorClient) registerProvider(req registerProviderRequest) (registerProviderResponse, error) {
	return c.registerProviderWithContext(context.Background(), req)
}

func (c *coordinatorClient) registerProviderWithContext(ctx context.Context, req registerProviderRequest) (registerProviderResponse, error) {
	var resp registerProviderResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	body, err := json.Marshal(req)
	if err != nil {
		return resp, err
	}

	endpoint := c.baseURL + "/admin/v1/providers/register"
	providerToken := c.providerToken(req.Provider.ID)
	if providerToken != "" {
		if err := c.postJSONWithToken(ctx, endpoint, body, http.StatusCreated, providerToken, &resp); err != nil {
			if !isUnauthorizedCoordinatorError(err) {
				return resp, err
			}
			c.forgetProviderToken(req.Provider.ID)
			providerToken = ""
		} else {
			c.rememberCredentials(resp.Credentials)
			return resp, nil
		}
	}

	ownerToken := c.requesterToken(req.Provider.SwarmID, req.Provider.OwnerMemberID)
	if ownerToken != "" {
		if err := c.postJSONWithToken(ctx, endpoint, body, http.StatusCreated, ownerToken, &resp); err != nil {
			if isUnauthorizedCoordinatorError(err) {
				c.forgetRequesterToken(req.Provider.SwarmID, req.Provider.OwnerMemberID)
			} else {
				return resp, err
			}
		} else {
			c.rememberCredentials(resp.Credentials)
			return resp, nil
		}
	}

	if err := c.postJSONWithToken(ctx, endpoint, body, http.StatusCreated, "", &resp); err != nil {
		return resp, err
	}
	c.rememberCredentials(resp.Credentials)
	return resp, nil
}

func (c *coordinatorClient) unregisterProvider(providerID string) (unregisterProviderResponse, error) {
	return c.unregisterProviderWithContext(context.Background(), providerID)
}

func (c *coordinatorClient) unregisterProviderWithContext(ctx context.Context, providerID string) (unregisterProviderResponse, error) {
	var resp unregisterProviderResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	body, err := json.Marshal(unregisterProviderRequest{ProviderID: providerID})
	if err != nil {
		return resp, err
	}

	if err := c.postJSONWithToken(ctx, c.baseURL+"/admin/v1/providers/unregister", body, http.StatusOK, c.providerToken(providerID), &resp); err != nil {
		return resp, err
	}
	return resp, nil
}

func (c *coordinatorClient) reserve(req reserveSessionRequest) (reserveSessionResponse, error) {
	var resp reserveSessionResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	body, err := json.Marshal(req)
	if err != nil {
		return resp, err
	}

	httpReq, err := http.NewRequest(http.MethodPost, c.baseURL+"/admin/v1/sessions/reserve", bytes.NewReader(body))
	if err != nil {
		return resp, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	addCoordinatorBearer(httpReq, c.requesterToken(req.SwarmID, req.RequesterMemberID))
	httpResp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return resp, err
	}
	defer httpResp.Body.Close()

	if httpResp.StatusCode != http.StatusCreated {
		return resp, newCoordinatorHTTPError(httpResp)
	}

	if err := json.NewDecoder(httpResp.Body).Decode(&resp); err != nil {
		return resp, err
	}

	return resp, nil
}

func (c *coordinatorClient) release(req releaseSessionRequest) (releaseSessionResponse, error) {
	var resp releaseSessionResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	body, err := json.Marshal(req)
	if err != nil {
		return resp, err
	}

	httpReq, err := http.NewRequest(http.MethodPost, c.baseURL+"/admin/v1/sessions/release", bytes.NewReader(body))
	if err != nil {
		return resp, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	addCoordinatorBearer(httpReq, c.requesterTokenFor(req.SwarmID, req.RequesterMemberID))
	httpResp, err := c.httpClient.Do(httpReq)
	if err != nil {
		return resp, err
	}
	defer httpResp.Body.Close()

	if httpResp.StatusCode != http.StatusOK {
		return resp, newCoordinatorHTTPError(httpResp)
	}

	if err := json.NewDecoder(httpResp.Body).Decode(&resp); err != nil {
		return resp, err
	}

	return resp, nil
}

func (c *coordinatorClient) executeRelay(ctx context.Context, sessionID string, providerID string, resolvedModel string, swarmID string, requesterMemberID string, req chatCompletionsRequest) (relayExecuteResponse, error) {
	var resp relayExecuteResponse
	if c.baseURL == "" {
		return resp, fmt.Errorf("coordinator URL is not configured")
	}

	requestBody, err := json.Marshal(req)
	if err != nil {
		return resp, err
	}
	body, err := json.Marshal(relayExecuteRequest{
		SessionID:     sessionID,
		ProviderID:    providerID,
		ResolvedModel: resolvedModel,
		Stream:        req.Stream,
		Request:       requestBody,
	})
	if err != nil {
		return resp, err
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/admin/v1/relay/execute", bytes.NewReader(body))
	if err != nil {
		return resp, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	addCoordinatorBearer(httpReq, c.requesterTokenFor(swarmID, requesterMemberID))

	httpResp, err := c.relayHTTPClient.Do(httpReq)
	if err != nil {
		return resp, err
	}
	defer httpResp.Body.Close()

	if httpResp.StatusCode != http.StatusOK {
		return resp, newCoordinatorHTTPError(httpResp)
	}

	if err := json.NewDecoder(httpResp.Body).Decode(&resp); err != nil {
		return resp, err
	}

	return resp, nil
}

func (c *coordinatorClient) proxyRelayStream(ctx context.Context, w http.ResponseWriter, sessionID string, providerID string, resolvedModel string, swarmID string, requesterMemberID string, req chatCompletionsRequest) error {
	if c.baseURL == "" {
		return fmt.Errorf("coordinator URL is not configured")
	}

	requestBody, err := json.Marshal(req)
	if err != nil {
		return err
	}
	body, err := json.Marshal(relayExecuteRequest{
		SessionID:     sessionID,
		ProviderID:    providerID,
		ResolvedModel: resolvedModel,
		Stream:        req.Stream,
		Request:       requestBody,
	})
	if err != nil {
		return err
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/admin/v1/relay/execute", bytes.NewReader(body))
	if err != nil {
		return err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	addCoordinatorBearer(httpReq, c.requesterTokenFor(swarmID, requesterMemberID))

	httpResp, err := c.relayHTTPClient.Do(httpReq)
	if err != nil {
		return err
	}
	defer httpResp.Body.Close()

	copyResponseHeader(w.Header(), httpResp.Header, "Content-Type", "Cache-Control", "Connection")
	w.WriteHeader(httpResp.StatusCode)

	flusher, _ := w.(http.Flusher)
	buffer := make([]byte, 32*1024)
	for {
		n, readErr := httpResp.Body.Read(buffer)
		if n > 0 {
			if _, writeErr := w.Write(buffer[:n]); writeErr != nil {
				return nil
			}
			if flusher != nil {
				flusher.Flush()
			}
		}

		if readErr == nil {
			continue
		}
		if readErr == io.EOF {
			return nil
		}
		return nil
	}
}

func (c *coordinatorClient) pushRelayChunk(ctx context.Context, req providerRelayChunkRequest) error {
	if c.baseURL == "" {
		return fmt.Errorf("coordinator URL is not configured")
	}
	if strings.TrimSpace(req.ProviderID) == "" {
		req.ProviderID, _ = localProviderIdentity()
	}
	body, err := json.Marshal(req)
	if err != nil {
		return err
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/admin/v1/providers/relay/chunk", bytes.NewReader(body))
	if err != nil {
		return err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	addCoordinatorBearer(httpReq, c.providerToken(req.ProviderID))
	httpResp, err := c.relayHTTPClient.Do(httpReq)
	if err != nil {
		return err
	}
	defer httpResp.Body.Close()
	if httpResp.StatusCode != http.StatusAccepted {
		return newCoordinatorHTTPError(httpResp)
	}
	return nil
}

func (c *coordinatorClient) pollRelay(ctx context.Context, providerID string) (providerRelayPollResponse, bool, error) {
	var resp providerRelayPollResponse
	if c.baseURL == "" {
		return resp, false, fmt.Errorf("coordinator URL is not configured")
	}

	body, err := json.Marshal(providerRelayPollRequest{ProviderID: providerID})
	if err != nil {
		return resp, false, err
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/admin/v1/providers/relay/poll", bytes.NewReader(body))
	if err != nil {
		return resp, false, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	addCoordinatorBearer(httpReq, c.providerToken(providerID))

	httpResp, err := c.relayHTTPClient.Do(httpReq)
	if err != nil {
		return resp, false, err
	}
	defer httpResp.Body.Close()

	if httpResp.StatusCode == http.StatusNoContent {
		return resp, false, nil
	}
	if httpResp.StatusCode != http.StatusOK {
		return resp, false, newCoordinatorHTTPError(httpResp)
	}
	if err := json.NewDecoder(httpResp.Body).Decode(&resp); err != nil {
		return resp, false, err
	}
	return resp, true, nil
}

func (c *coordinatorClient) completeRelay(ctx context.Context, req providerRelayCompleteRequest) error {
	if c.baseURL == "" {
		return fmt.Errorf("coordinator URL is not configured")
	}
	if strings.TrimSpace(req.ProviderID) == "" {
		req.ProviderID, _ = localProviderIdentity()
	}
	body, err := json.Marshal(req)
	if err != nil {
		return err
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, c.baseURL+"/admin/v1/providers/relay/complete", bytes.NewReader(body))
	if err != nil {
		return err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	addCoordinatorBearer(httpReq, c.providerToken(req.ProviderID))
	httpResp, err := c.relayHTTPClient.Do(httpReq)
	if err != nil {
		return err
	}
	defer httpResp.Body.Close()
	if httpResp.StatusCode != http.StatusAccepted {
		return newCoordinatorHTTPError(httpResp)
	}
	return nil
}

func decodeRelayBody(payload string) ([]byte, error) {
	if strings.TrimSpace(payload) == "" {
		return nil, nil
	}
	return base64.StdEncoding.DecodeString(payload)
}

type coordinatorHTTPError struct {
	StatusCode int
	Message    string
}

func (e coordinatorHTTPError) Error() string {
	return fmt.Sprintf("coordinator returned %d: %s", e.StatusCode, e.Message)
}

func newCoordinatorHTTPError(resp *http.Response) error {
	body, _ := io.ReadAll(resp.Body)
	message := strings.TrimSpace(string(body))
	if message == "" {
		message = resp.Status
	}
	return coordinatorHTTPError{
		StatusCode: resp.StatusCode,
		Message:    message,
	}
}
