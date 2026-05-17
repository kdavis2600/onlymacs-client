package httpapi

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type requestPolicyCorpusCase struct {
	prompt                string
	taskKind              requestPolicyTaskKind
	dataAccess            requestPolicyDataAccess
	sensitivity           requestPolicySensitivity
	complexity            requestPolicyComplexity
	recommendedRouteScope string
	publicDecision        requestPolicyDecision
	privateDecision       requestPolicyDecision
}

func TestRequestPolicyCorpus(t *testing.T) {
	cases := buildRequestPolicyCorpus()
	if len(cases) != 100 {
		t.Fatalf("expected 100 request policy cases, got %d", len(cases))
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.prompt, func(t *testing.T) {
			classification := classifyRequestPolicy(tc.prompt, nil)
			if classification.TaskKind != tc.taskKind {
				t.Fatalf("expected task kind %q, got %q", tc.taskKind, classification.TaskKind)
			}
			if classification.DataAccess != tc.dataAccess {
				t.Fatalf("expected data access %q, got %q", tc.dataAccess, classification.DataAccess)
			}
			if classification.Sensitivity != tc.sensitivity {
				t.Fatalf("expected sensitivity %q, got %q", tc.sensitivity, classification.Sensitivity)
			}
			if classification.Complexity != tc.complexity {
				t.Fatalf("expected complexity %q, got %q", tc.complexity, classification.Complexity)
			}
			if classification.RecommendedRouteScope != tc.recommendedRouteScope {
				t.Fatalf("expected recommended route %q, got %q", tc.recommendedRouteScope, classification.RecommendedRouteScope)
			}

			routing := suggestRequestRouting(tc.prompt, classification)
			publicResponse := resolveRequestPolicy(classification, routing, routeScopeSwarm, "public", "OnlyMacs Public")
			if publicResponse.Decision != tc.publicDecision {
				t.Fatalf("expected public decision %q, got %q", tc.publicDecision, publicResponse.Decision)
			}
			if classification.RequiresLocalFiles && len(publicResponse.FileAccessPlan.SuggestedContextPacks) == 0 {
				t.Fatalf("expected file-aware request to receive suggested context packs, got %+v", publicResponse.FileAccessPlan)
			}
			if !classification.RequiresLocalFiles && classification.Sensitivity != requestSensitivityHigh && publicResponse.FileAccessPlan.Mode != requestFileAccessNone {
				t.Fatalf("expected prompt-only request to skip file access planning, got %+v", publicResponse.FileAccessPlan)
			}
			if !classification.RequiresLocalFiles && classification.Sensitivity == requestSensitivityHigh && publicResponse.FileAccessPlan.Mode != requestFileAccessLocalOnly {
				t.Fatalf("expected sensitive prompt-only request to recommend local handling, got %+v", publicResponse.FileAccessPlan)
			}

			privateResponse := resolveRequestPolicy(classification, routing, routeScopeSwarm, "private", "Friends")
			if privateResponse.Decision != tc.privateDecision {
				t.Fatalf("expected private decision %q, got %q", tc.privateDecision, privateResponse.Decision)
			}

			localResponse := resolveRequestPolicy(classification, routing, routeScopeLocalOnly, "public", "OnlyMacs Public")
			if localResponse.Decision != requestPolicyAllowCurrent {
				t.Fatalf("expected local route to stay allowed, got %q", localResponse.Decision)
			}
		})
	}
}

func TestPromptOnlyOverrideSkipsFileApprovalForSelfContainedArchitecture(t *testing.T) {
	prompt := `PROMPT-ONLY REMOTE TEST. Do not ask for local repository access. Use only the facts inside this message.

Design a Step 2 architecture for a content pipeline. Return a manifest, json-like set map, validation notes, and handoff instructions.`

	classification := classifyRequestPolicy(prompt, nil)
	if classification.RequiresLocalFiles {
		t.Fatalf("expected explicit prompt-only request to skip local files, got %+v", classification)
	}
	if classification.DataAccess != requestDataPromptOnly {
		t.Fatalf("expected prompt-only data access, got %q", classification.DataAccess)
	}

	routing := suggestRequestRouting(prompt, classification)
	response := resolveRequestPolicy(classification, routing, routeScopeSwarm, "public", "OnlyMacs Public")
	if response.Decision != requestPolicyAllowCurrent {
		t.Fatalf("expected prompt-only public request to stay allowed, got %+v", response)
	}
	if response.FileAccessPlan.Mode != requestFileAccessNone {
		t.Fatalf("expected no file access plan, got %+v", response.FileAccessPlan)
	}
}

func TestRequestPolicyHandlerUsesRuntimeSwarmVisibility(t *testing.T) {
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{
				Swarms: []swarm{
					{ID: "swarm-public", Name: "OnlyMacs Public", Visibility: "public"},
					{ID: "swarm-private", Name: "Friends", Visibility: "private"},
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
	})

	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-public",
	})

	body := marshalJSON(t, requestPolicyClassifyRequest{
		Prompt:     "review the pipeline docs in this project",
		RouteScope: routeScopeSwarm,
	})
	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/request-policy/classify", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}

	var response requestPolicyResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &response); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if response.Decision != requestPolicyPublicExport {
		t.Fatalf("expected public export decision, got %+v", response)
	}
	if response.FileAccessPlan.Mode != requestFileAccessCapsuleSnapshot {
		t.Fatalf("expected public capsule file access mode, got %+v", response.FileAccessPlan)
	}
	if response.FileAccessPlan.TrustTier != requestTrustPublicUntrusted {
		t.Fatalf("expected public trust tier, got %+v", response.FileAccessPlan)
	}

	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-private",
	})

	req = httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/request-policy/classify", bytes.NewReader(body))
	rec = httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &response); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if response.Decision != requestPolicyPrivateExport {
		t.Fatalf("expected private export decision, got %+v", response)
	}
	if response.FileAccessPlan.Mode == requestFileAccessNone {
		t.Fatalf("expected file access plan for private export, got %+v", response.FileAccessPlan)
	}
	if response.FileAccessPlan.ApprovalRequired != true {
		t.Fatalf("expected private export to require approval, got %+v", response.FileAccessPlan)
	}
}

func TestRequestPolicyUsesSwarmContextPolicy(t *testing.T) {
	privatePolicy := &swarmContextPolicy{
		Version:                 bridgeSwarmContextPolicyVersion,
		ContextReadMode:         bridgeContextReadGitBacked,
		ContextWriteMode:        bridgeContextWriteDirect,
		AllowTestExecution:      true,
		AllowDependencyInstall:  true,
		RequireFileLocks:        true,
		SecretGuardEnabled:      true,
		MaxContextRequestRounds: 4,
	}
	coordinator := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/admin/v1/swarms":
			writeJSON(w, http.StatusOK, coordinatorSwarmsResponse{
				Swarms: []swarm{
					{ID: "swarm-private", Name: "Coding Friends", Visibility: "private", ContextPolicy: privatePolicy},
				},
			})
		default:
			t.Fatalf("unexpected coordinator path %s", r.URL.Path)
		}
	}))
	defer coordinator.Close()

	mux := NewMuxWithConfig(Config{
		CoordinatorURL: coordinator.URL,
		HTTPClient:     coordinator.Client(),
	})
	updateRuntime(t, mux, runtimeConfig{
		Mode:          "both",
		ActiveSwarmID: "swarm-private",
	})

	body := marshalJSON(t, requestPolicyClassifyRequest{
		Prompt:     "fix the failing TypeScript tests in this repo and return a patch",
		RouteScope: routeScopeSwarm,
	})
	req := httptest.NewRequest(http.MethodPost, "http://127.0.0.1:4318/admin/v1/request-policy/classify", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected status %d, got %d: %s", http.StatusOK, rec.Code, rec.Body.String())
	}
	var response requestPolicyResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &response); err != nil {
		t.Fatalf("unmarshal response: %v", err)
	}
	if response.SwarmContextPolicy == nil || response.SwarmContextPolicy.ContextReadMode != bridgeContextReadGitBacked {
		t.Fatalf("expected response to include git-backed swarm policy, got %+v", response.SwarmContextPolicy)
	}
	if response.FileAccessPlan.Mode != requestFileAccessGitBackedCheckout {
		t.Fatalf("expected git-backed checkout mode, got %+v", response.FileAccessPlan)
	}
	if !response.FileAccessPlan.AllowSourceMutation || !response.FileAccessPlan.AllowStagedMutation {
		t.Fatalf("expected direct write policy to allow source/staged mutation, got %+v", response.FileAccessPlan)
	}
	if !response.FileAccessPlan.AllowTestExecution || !response.FileAccessPlan.AllowDependencyInstall {
		t.Fatalf("expected direct private policy to carry tests/install permissions, got %+v", response.FileAccessPlan)
	}
}

func TestPublicSwarmPolicyCannotEnableDirectFileAccess(t *testing.T) {
	maliciousPublicPolicy := &swarmContextPolicy{
		Version:                 bridgeSwarmContextPolicyVersion,
		ContextReadMode:         bridgeContextReadFullProject,
		ContextWriteMode:        bridgeContextWriteDirect,
		AllowTestExecution:      true,
		AllowDependencyInstall:  true,
		MaxContextRequestRounds: 5,
	}
	classification := classifyRequestPolicy("review the markdown docs and examples in this project", nil)
	routing := suggestRequestRouting("review the markdown docs and examples in this project", classification)
	response := resolveRequestPolicy(classification, routing, routeScopeSwarm, "public", "OnlyMacs Public", maliciousPublicPolicy)
	if response.FileAccessPlan.ContextReadMode != bridgeContextReadManualApproval || response.FileAccessPlan.ContextWriteMode != bridgeContextWriteInbox {
		t.Fatalf("expected public policy to be normalized safe, got %+v", response.FileAccessPlan)
	}
	if response.FileAccessPlan.AllowSourceMutation || response.FileAccessPlan.AllowTestExecution || response.FileAccessPlan.AllowDependencyInstall {
		t.Fatalf("expected public policy to block direct execution/write, got %+v", response.FileAccessPlan)
	}
}

func TestRequestPolicyRoutingSuggestions(t *testing.T) {
	cases := []struct {
		name              string
		prompt            string
		wantCommand       string
		wantPreset        string
		wantExplanationIn string
	}{
		{
			name:              "prompt_only_brainstorm",
			prompt:            "brainstorm three launch taglines for OnlyMacs",
			wantCommand:       "chat",
			wantPreset:        "balanced",
			wantExplanationIn: "prompt-only",
		},
		{
			name:              "trusted_repo_review",
			prompt:            "review the pipeline docs in this project",
			wantCommand:       "chat",
			wantPreset:        "trusted-only",
			wantExplanationIn: "repo or file context",
		},
		{
			name:              "sensitive_files_local",
			prompt:            "review the .env and config files in this project",
			wantCommand:       "chat",
			wantPreset:        "local-first",
			wantExplanationIn: "sensitive",
		},
		{
			name:              "trusted_plan",
			prompt:            "make a plan for refactoring this repo and cleaning up the tests",
			wantCommand:       "plan",
			wantPreset:        "trusted-only",
			wantExplanationIn: "trusted plan",
		},
		{
			name:              "wide_plan",
			prompt:            "split this refactor into parallel workstreams",
			wantCommand:       "plan",
			wantPreset:        "wide",
			wantExplanationIn: "wider swarm",
		},
		{
			name:              "explicit_plan_beats_parallel_launch_language",
			prompt:            "make a plan to split this launch campaign into parallel workstreams for growth, docs, and support",
			wantCommand:       "plan",
			wantPreset:        "wide",
			wantExplanationIn: "plan first",
		},
		{
			name:              "wide_go",
			prompt:            "start parallel workstreams to refactor this repo",
			wantCommand:       "go",
			wantPreset:        "wide",
			wantExplanationIn: "launch a wider swarm",
		},
		{
			name:              "prompt_plan",
			prompt:            "estimate how many agents this migration needs before you start",
			wantCommand:       "plan",
			wantPreset:        "balanced",
			wantExplanationIn: "start with a plan",
		},
		{
			name:              "trusted_content_generation",
			prompt:            "generate 10 new json files using the content pipeline in this project",
			wantCommand:       "chat",
			wantPreset:        "trusted-only",
			wantExplanationIn: "ask for approval",
		},
		{
			name:              "prompt_strategy",
			prompt:            "what are the tradeoffs of a freemium pricing model",
			wantCommand:       "chat",
			wantPreset:        "balanced",
			wantExplanationIn: "prompt-only",
		},
		{
			name:              "sensitive_repo_debug",
			prompt:            "debug the leaked api keys in this repo and tell me what to do",
			wantCommand:       "chat",
			wantPreset:        "local-first",
			wantExplanationIn: "sensitive",
		},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			classification := classifyRequestPolicy(tc.prompt, nil)
			routing := suggestRequestRouting(tc.prompt, classification)
			if routing.SuggestedCommand != tc.wantCommand {
				t.Fatalf("expected command %q, got %q", tc.wantCommand, routing.SuggestedCommand)
			}
			if routing.SuggestedPreset != tc.wantPreset {
				t.Fatalf("expected preset %q, got %q", tc.wantPreset, routing.SuggestedPreset)
			}
			if !strings.Contains(strings.ToLower(routing.Explanation), strings.ToLower(tc.wantExplanationIn)) {
				t.Fatalf("expected explanation to contain %q, got %q", tc.wantExplanationIn, routing.Explanation)
			}
		})
	}
}

func TestRequestPolicyFileAccessPlanShapesRouteAdvice(t *testing.T) {
	classification := classifyRequestPolicy("review the pipeline docs in this project and propose fixes", nil)
	routing := suggestRequestRouting("review the pipeline docs in this project and propose fixes", classification)

	publicResponse := resolveRequestPolicy(classification, routing, routeScopeSwarm, "public", "OnlyMacs Public")
	if publicResponse.FileAccessPlan.Mode != requestFileAccessCapsuleSnapshot {
		t.Fatalf("expected public route to use a capsule snapshot, got %+v", publicResponse.FileAccessPlan)
	}
	if publicResponse.FileAccessPlan.SuggestedExportLevelPublic != "excerpt_capsule" {
		t.Fatalf("expected public export level hint, got %+v", publicResponse.FileAccessPlan)
	}
	if !strings.Contains(strings.ToLower(publicResponse.FileAccessPlan.UserFacingWarning), "public workers") {
		t.Fatalf("expected public warning to explain public worker limits, got %+v", publicResponse.FileAccessPlan)
	}

	privateResponse := resolveRequestPolicy(classification, routing, routeScopeSwarm, "private", "Friends")
	if privateResponse.FileAccessPlan.Mode != requestFileAccessPrivateProjectLease {
		t.Fatalf("expected private defaults to allow project-lease context for heavy trusted work, got %+v", privateResponse.FileAccessPlan)
	}
	if privateResponse.FileAccessPlan.MaxContextRequestRounds < 1 {
		t.Fatalf("expected trusted review to permit context request rounds, got %+v", privateResponse.FileAccessPlan)
	}
	if len(privateResponse.FileAccessPlan.SuggestedFiles) == 0 {
		t.Fatalf("expected private review to suggest files, got %+v", privateResponse.FileAccessPlan)
	}
}

func buildRequestPolicyCorpus() []requestPolicyCorpusCase {
	var cases []requestPolicyCorpusCase
	addCases := func(prompts []string, expectation requestPolicyCorpusCase) {
		for _, prompt := range prompts {
			entry := expectation
			entry.prompt = prompt
			cases = append(cases, entry)
		}
	}
	overrideCase := func(prompt string, expectation requestPolicyCorpusCase) {
		for i := range cases {
			if cases[i].prompt == prompt {
				expectation.prompt = prompt
				cases[i] = expectation
				return
			}
		}
		panic("missing request policy corpus prompt: " + prompt)
	}

	addCases([]string{
		"brainstorm three launch taglines for OnlyMacs",
		"give me five names for a new coding app",
		"what positioning would make this product feel premium",
		"help me write a short landing page hero",
		"come up with a better name for my feature flag",
		"how should i explain this startup idea to investors",
		"give me three product strategy options for this month",
		"help me decide whether to launch this on Product Hunt",
		"draft a short outline for a founder update email",
		"what are the tradeoffs of a freemium pricing model",
	}, requestPolicyCorpusCase{
		taskKind:              requestTaskPlan,
		dataAccess:            requestDataPromptOnly,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeSwarm,
		publicDecision:        requestPolicyAllowCurrent,
		privateDecision:       requestPolicyAllowCurrent,
	})

	addCases([]string{
		"summarize this feature idea in one paragraph",
		"classify these user requests into billing or support",
		"categorize these bug reports by severity",
		"rename these roadmap items so they sound simpler",
		"tag these customer messages by theme",
		"sort these feature requests into launch now or later",
		"summarize the meeting notes i pasted above",
		"give me a short summary of this product brief",
		"classify these questions into technical or nontechnical",
		"turn these notes into a bullet summary",
	}, requestPolicyCorpusCase{
		taskKind:              requestTaskSummarize,
		dataAccess:            requestDataPromptOnly,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexitySimple,
		recommendedRouteScope: routeScopeSwarm,
		publicDecision:        requestPolicyAllowCurrent,
		privateDecision:       requestPolicyAllowCurrent,
	})

	addCases([]string{
		"translate this product description into Vietnamese",
		"localize this onboarding copy into French",
		"translate these support instructions into Spanish",
		"rewrite this paragraph so it reads naturally in German",
		"translate this short email into Japanese",
		"localize these button labels into Portuguese",
		"translate this FAQ answer into Korean",
		"rewrite this sentence for UK English",
		"translate this launch note into Indonesian",
		"localize these push notification examples into Thai",
	}, requestPolicyCorpusCase{
		taskKind:              requestTaskTranslate,
		dataAccess:            requestDataPromptOnly,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexitySimple,
		recommendedRouteScope: routeScopeSwarm,
		publicDecision:        requestPolicyAllowCurrent,
		privateDecision:       requestPolicyAllowCurrent,
	})

	addCases([]string{
		"help me think through a password rotation incident",
		"should i share this api key migration plan with a swarm",
		"talk me through a secret management approach",
		"how should i respond to a customer data breach notice",
		"help me plan a payroll data cleanup",
		"what is the safest way to handle passport verification data",
		"how should i approach a patient privacy incident",
		"draft a response to a legal request about customer records",
		"what do i do about a leaked private key",
		"help me rewrite this note about internal credentials",
	}, requestPolicyCorpusCase{
		taskKind:              requestTaskPlan,
		dataAccess:            requestDataPromptOnly,
		sensitivity:           requestSensitivityHigh,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeLocalOnly,
		publicDecision:        requestPolicyLocalOnlyRecommended,
		privateDecision:       requestPolicyLocalOnlyRecommended,
	})

	addCases([]string{
		"review this repo for concurrency issues",
		"review the pipeline docs in this project",
		"audit this project folder for unclear documentation",
		"inspect the readme files in this workspace and tell me what is missing",
		"check this codebase for architecture drift",
		"review the docs in this repo and tell me what is inconsistent",
		"audit the files in this project for onboarding gaps",
		"review this repository and explain the weak spots",
		"inspect the source tree in this project and summarize the risks",
		"check the markdown docs in this workspace for contradictions",
	}, requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyBlockedPublic,
		privateDecision:       requestPolicyPrivateExport,
	})

	addCases([]string{
		"explain the schema files in this repo and how they relate",
		"review the pipeline docs and schema examples in this project",
		"check the readme and glossary files in this workspace",
		"compare the docs and example json files in this repo",
		"validate the markdown guide and yaml config files in this project",
		"inspect the package.json and tsconfig in this workspace",
		"review the content pipeline docs and examples folder in this repo",
		"check the spreadsheet exports and csv files in this project",
		"review the slides and notes files in this workspace",
		"tell me where the docs and examples disagree in this repo",
	}, requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyBlockedPublic,
		privateDecision:       requestPolicyPrivateExport,
	})

	addCases([]string{
		"rearrange this json file to match the schema",
		"update these yaml files so the config names are consistent",
		"rewrite the markdown docs in this project so they match the examples",
		"edit package.json in this repo to add the missing script",
		"rename the exported csv columns in this workspace",
		"fix the schema files in this project so the field names line up",
		"update the readme files in this repository with the correct commands",
		"rewrite these content json files using the glossary in this project",
		"modify the slides and notes files in this folder so they match",
		"change the example json files in this repo to use the new shape",
	}, requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyBlockedPublic,
		privateDecision:       requestPolicyPrivateExport,
	})

	addCases([]string{
		"fix this bug in the repo and update the tests",
		"refactor this project to remove the duplicate helpers",
		"patch the files in this workspace so the build passes",
		"edit this codebase to stop the race condition",
		"rewrite the failing test files in this repo",
		"update the source tree in this project to use the new api",
		"modify the files in this repository to clean up the auth flow",
		"fix the broken import paths in this workspace",
		"refactor the package files in this project and simplify the build",
		"apply a patch to this repo so the tests stop failing",
	}, requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyBlockedPublic,
		privateDecision:       requestPolicyPrivateExport,
	})

	addCases([]string{
		"generate 10 new json files using the content pipeline in this project",
		"create five more lessons from the examples in this repo",
		"write new output files that match the schema in this workspace",
		"generate a new glossary json from the docs in this project",
		"create more content files using the pipeline docs and examples in this repo",
		"write a fresh batch of output json files from this project folder",
		"generate a localized content pack from the docs in this workspace",
		"create new lesson files using the schema and examples in this repo",
		"write new structured outputs from the content pipeline docs in this project",
		"generate more example files from the glossary and schema in this workspace",
	}, requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyBlockedPublic,
		privateDecision:       requestPolicyPrivateExport,
	})

	addCases([]string{
		"review the .env and config files in this project",
		"check this repo for leaked api keys and secrets",
		"inspect the password reset files in this workspace",
		"rewrite the credential docs in this project",
		"review the private key handling files in this repo",
		"generate a report from the customer list files in this workspace",
		"compare the payroll csv files in this project",
		"inspect the bank statement exports in this repo",
		"review the passport verification docs in this workspace",
		"check the patient data files in this project for issues",
	}, requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityHigh,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeLocalOnly,
		publicDecision:        requestPolicyLocalOnlyRecommended,
		privateDecision:       requestPolicyLocalOnlyRecommended,
	})

	overrideCase("help me write a short landing page hero", requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataPromptOnly,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeSwarm,
		publicDecision:        requestPolicyAllowCurrent,
		privateDecision:       requestPolicyAllowCurrent,
	})
	overrideCase("draft a short outline for a founder update email", requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataPromptOnly,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeSwarm,
		publicDecision:        requestPolicyAllowCurrent,
		privateDecision:       requestPolicyAllowCurrent,
	})
	overrideCase("draft a response to a legal request about customer records", requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataPromptOnly,
		sensitivity:           requestSensitivityHigh,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeLocalOnly,
		publicDecision:        requestPolicyLocalOnlyRecommended,
		privateDecision:       requestPolicyLocalOnlyRecommended,
	})
	overrideCase("help me rewrite this note about internal credentials", requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataPromptOnly,
		sensitivity:           requestSensitivityHigh,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeLocalOnly,
		publicDecision:        requestPolicyLocalOnlyRecommended,
		privateDecision:       requestPolicyLocalOnlyRecommended,
	})
	overrideCase("review the pipeline docs and schema examples in this project", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("review the content pipeline docs and examples folder in this repo", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("edit package.json in this repo to add the missing script", requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyBlockedPublic,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("rewrite the credential docs in this project", requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityHigh,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeLocalOnly,
		publicDecision:        requestPolicyLocalOnlyRecommended,
		privateDecision:       requestPolicyLocalOnlyRecommended,
	})
	overrideCase("review the pipeline docs in this project", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("audit this project folder for unclear documentation", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("inspect the readme files in this workspace and tell me what is missing", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("review the docs in this repo and tell me what is inconsistent", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("check the markdown docs in this workspace for contradictions", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("explain the schema files in this repo and how they relate", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("check the readme and glossary files in this workspace", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("compare the docs and example json files in this repo", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("validate the markdown guide and yaml config files in this project", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("check the spreadsheet exports and csv files in this project", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("review the slides and notes files in this workspace", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("tell me where the docs and examples disagree in this repo", requestPolicyCorpusCase{
		taskKind:              requestTaskReview,
		dataAccess:            requestDataWorkspaceRead,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("rearrange this json file to match the schema", requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("update these yaml files so the config names are consistent", requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("rewrite the markdown docs in this project so they match the examples", requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("rename the exported csv columns in this workspace", requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("fix the schema files in this project so the field names line up", requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("update the readme files in this repository with the correct commands", requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("rewrite these content json files using the glossary in this project", requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("modify the slides and notes files in this folder so they match", requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("change the example json files in this repo to use the new shape", requestPolicyCorpusCase{
		taskKind:              requestTaskTransform,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityNormal,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("generate 10 new json files using the content pipeline in this project", requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("create five more lessons from the examples in this repo", requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("write new output files that match the schema in this workspace", requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("generate a new glossary json from the docs in this project", requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("create more content files using the pipeline docs and examples in this repo", requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("write a fresh batch of output json files from this project folder", requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("generate a localized content pack from the docs in this workspace", requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("create new lesson files using the schema and examples in this repo", requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("write new structured outputs from the content pipeline docs in this project", requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})
	overrideCase("generate more example files from the glossary and schema in this workspace", requestPolicyCorpusCase{
		taskKind:              requestTaskGenerate,
		dataAccess:            requestDataWorkspaceWrite,
		sensitivity:           requestSensitivityLow,
		complexity:            requestComplexityHeavy,
		recommendedRouteScope: routeScopeTrustedOnly,
		publicDecision:        requestPolicyPublicExport,
		privateDecision:       requestPolicyPrivateExport,
	})

	return cases
}
