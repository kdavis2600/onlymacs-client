package httpapi

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"unicode"
)

type requestPolicyDecision string

const (
	requestPolicyAllowCurrent         requestPolicyDecision = "allow_current_route"
	requestPolicyPublicExport         requestPolicyDecision = "public_export_required"
	requestPolicyPrivateExport        requestPolicyDecision = "private_export_required"
	requestPolicyLocalOnlyRecommended requestPolicyDecision = "local_only_recommended"
	requestPolicyBlockedPublic        requestPolicyDecision = "blocked_public"
	requestPolicyBlockedUnverified    requestPolicyDecision = "blocked_unverified"
)

type requestPolicyTaskKind string

const (
	requestTaskReview    requestPolicyTaskKind = "review"
	requestTaskDebug     requestPolicyTaskKind = "debug"
	requestTaskGenerate  requestPolicyTaskKind = "generate"
	requestTaskTransform requestPolicyTaskKind = "transform"
	requestTaskSummarize requestPolicyTaskKind = "summarize"
	requestTaskTranslate requestPolicyTaskKind = "translate"
	requestTaskPlan      requestPolicyTaskKind = "plan"
	requestTaskExplain   requestPolicyTaskKind = "explain"
	requestTaskGeneric   requestPolicyTaskKind = "generic"
)

type requestPolicySensitivity string

const (
	requestSensitivityLow    requestPolicySensitivity = "low"
	requestSensitivityMedium requestPolicySensitivity = "medium"
	requestSensitivityHigh   requestPolicySensitivity = "high"
)

type requestPolicyComplexity string

const (
	requestComplexitySimple requestPolicyComplexity = "simple"
	requestComplexityNormal requestPolicyComplexity = "normal"
	requestComplexityHeavy  requestPolicyComplexity = "heavy"
)

type requestPolicyDataAccess string

const (
	requestDataPromptOnly     requestPolicyDataAccess = "prompt_only"
	requestDataWorkspaceRead  requestPolicyDataAccess = "workspace_read"
	requestDataWorkspaceWrite requestPolicyDataAccess = "workspace_write"
)

type requestPolicyClassifyRequest struct {
	Prompt     string        `json:"prompt"`
	Messages   []chatMessage `json:"messages,omitempty"`
	RouteScope string        `json:"route_scope,omitempty"`
}

type requestPolicyClassification struct {
	TaskKind               requestPolicyTaskKind    `json:"task_kind"`
	DataAccess             requestPolicyDataAccess  `json:"data_access"`
	RequiresLocalFiles     bool                     `json:"requires_local_files"`
	WantsWriteAccess       bool                     `json:"wants_write_access"`
	PublicCapsuleFriendly  bool                     `json:"public_capsule_friendly"`
	LooksLikeCodeContext   bool                     `json:"looks_like_code_context"`
	LooksLikeDocsContext   bool                     `json:"looks_like_docs_context"`
	LooksLikeSchemaContext bool                     `json:"looks_like_schema_context"`
	Sensitivity            requestPolicySensitivity `json:"sensitivity"`
	Complexity             requestPolicyComplexity  `json:"complexity"`
	RecommendedRouteScope  string                   `json:"recommended_route_scope"`
	MatchedSignals         []string                 `json:"matched_signals,omitempty"`
}

type requestPolicyRouting struct {
	SuggestedCommand string `json:"suggested_command"`
	SuggestedPreset  string `json:"suggested_preset"`
	Explanation      string `json:"explanation,omitempty"`
}

type requestPolicyResponse struct {
	Classification        requestPolicyClassification `json:"classification"`
	Routing               requestPolicyRouting        `json:"routing"`
	FileAccessPlan        requestPolicyFileAccessPlan `json:"file_access_plan"`
	Decision              requestPolicyDecision       `json:"decision"`
	ActiveSwarmVisibility string                      `json:"active_swarm_visibility,omitempty"`
	ActiveSwarmName       string                      `json:"active_swarm_name,omitempty"`
	SwarmContextPolicy    *swarmContextPolicy         `json:"swarm_context_policy,omitempty"`
	Reasons               []string                    `json:"reasons,omitempty"`
}

func (s *service) requestPolicyClassifyHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, invalidRequest("METHOD_NOT_ALLOWED", "request policy classification requires POST"))
		return
	}

	var req requestPolicyClassifyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, invalidRequest("INVALID_JSON", err.Error()))
		return
	}

	classification := classifyRequestPolicy(strings.TrimSpace(req.Prompt), req.Messages)
	routing := suggestRequestRouting(strings.TrimSpace(req.Prompt), classification)
	routeScope := normalizeRouteScope(req.RouteScope)
	if routeScope == "" {
		routeScope = routeScopeSwarm
	}
	activeSwarmVisibility, activeSwarmName, activeSwarmPolicy := s.activeSwarmContext()
	response := resolveRequestPolicy(classification, routing, routeScope, activeSwarmVisibility, activeSwarmName, activeSwarmPolicy)
	writeJSON(w, http.StatusOK, response)
}

func (s *service) activeSwarmContext() (string, string, *swarmContextPolicy) {
	runtime := s.runtime.Get()
	if strings.TrimSpace(runtime.ActiveSwarmID) == "" {
		return "unknown", "", nil
	}

	swarmsResp, err := s.swarmsForRuntimeWithContext(context.Background(), runtime)
	if err != nil {
		return "unknown", runtime.ActiveSwarmID, nil
	}

	for _, current := range swarmsResp.Swarms {
		if current.ID == runtime.ActiveSwarmID {
			visibility := strings.TrimSpace(strings.ToLower(current.Visibility))
			if visibility == "" {
				visibility = "unknown"
			}
			return visibility, current.Name, normalizedBridgeSwarmContextPolicy(current.ContextPolicy, visibility)
		}
	}

	if runtime.ActiveSwarmID == "swarm-public" {
		return "public", "OnlyMacs Public", normalizedBridgeSwarmContextPolicy(nil, "public")
	}
	return "unknown", runtime.ActiveSwarmID, nil
}

func classifyRequestPolicy(prompt string, messages []chatMessage) requestPolicyClassification {
	joined := strings.ToLower(strings.TrimSpace(strings.Join(append([]string{prompt}, messageContents(messages)...), "\n")))
	signals := []string{}
	addSignal := func(signal string) {
		for _, existing := range signals {
			if existing == signal {
				return
			}
		}
		signals = append(signals, signal)
	}

	reviewMarkers := []string{"review", "audit", "inspect", "check", "validate", "compare", "tell me where", "tell me what is unclear", "tell me what is broken", "unclear", "inconsistent", "missing", "weak spots", "contradictions", "drift", "risks", "onboarding gaps"}
	debugMarkers := []string{"debug", "broken", "failing", "error", "stack trace", "bug", "race condition", "concurrency"}
	summarizeMarkers := []string{"summarize", "summary", "classify", "categorize", "categorize these", "tag these", "sort these", "sort this", "bullet summary"}
	translateMarkers := []string{"translate", "localize", "into french", "into spanish", "into vietnamese", "into portuguese", "into japanese", "into korean", "into indonesian", "into thai", "into german", "for uk english", "reads naturally in"}
	planMarkers := []string{"brainstorm", "positioning", "strategy", "tradeoff", "tradeoffs", "decide whether", "help me decide", "help me plan", "how should i", "what should i", "what do i do", "should i", "help me think through", "talk me through", "approach", "safest way", "pricing model", "product hunt", "investors", "startup idea", "options", "migration plan", "name for", "names for", "tagline", "taglines"}
	explainMarkers := []string{"explain", "walk me through", "teach me", "how does", "what is", "tell me"}
	generateMarkers := []string{"generate", "create", "draft", "come up with", "help me write", "write new", "write a fresh", "write more"}
	editMarkers := []string{"edit", "rewrite", "update", "modify", "fix", "refactor", "refactoring", "patch", "rearrange", "rename", "move", "delete", "save", "apply", "change", "add"}
	workspaceMarkers := []string{"repo", "repository", "project", "workspace", "codebase", "source tree", "project folder", "directory", "folder", "branch", "commit", "diff", "patch", "checkout", "monorepo"}
	artifactMarkers := []string{"file", "files", "docs", "documentation", "readme", "schema", "json", "yaml", "yml", "markdown", ".md", ".json", ".yaml", ".yml", "package.json", "tsconfig", "pipeline", "examples", "glossary", "csv", "spreadsheet", "excel", "slides", "sql", "html", "css", "tsx", "jsx", "component", "components", "landing page", "website"}
	codeMarkers := []string{"source tree", "source code", "code review", "review my code", "src", ".swift", ".ts", ".tsx", ".js", ".jsx", ".go", ".py", ".css", ".html", "typescript", "javascript", "react", "next.js", "vite", "tailwind", "canvas", "webgl", "three.js", "threejs", "babylon", "pixi", "package.json", "tsconfig", "auth", "api", "build", "tests", "import paths", "race condition", "concurrency", "frontend", "backend", "landing page", "website"}
	docsMarkers := []string{"docs", "documentation", "readme", "guide", "glossary", "markdown", ".md", "master docs", "pipeline docs", "handbook", "notes"}
	schemaMarkers := []string{"schema", "example", "examples", "sample", "json", "yaml", "yml", "csv", "glossary"}
	highSensitivityMarkers := []string{"password", "secret", "secrets", "api key", "api keys", "apikey", "token", "private key", "ssh key", "credential", "credentials", ".env", "access key", "passport", "ssn", "social security", "medical", "patient", "payroll", "tax return", "bank statement", "customer list", "customer data", "customer records", "pii", "personal data"}
	mediumSensitivityMarkers := []string{"login", "security", "breach", "incident", "production data", "internal credentials", "internal records"}
	promptOnlyMarkers := []string{
		"prompt-only",
		"prompt only",
		"use only the facts inside this message",
		"use only the facts in this message",
		"do not ask for local repository access",
		"do not ask for local repo access",
		"do not ask for local files",
		"do not use local files",
		"self-contained prompt",
	}

	reviewScore := containsCount(joined, reviewMarkers)
	debugScore := containsCount(joined, debugMarkers)
	summarizeScore := containsCount(joined, summarizeMarkers)
	translateScore := containsCount(joined, translateMarkers)
	planScore := containsCount(joined, planMarkers)
	explainScore := containsCount(joined, explainMarkers)
	generateScore := containsCount(joined, generateMarkers)
	editScore := containsCount(joined, editMarkers)
	workspaceScore := containsCount(joined, workspaceMarkers)
	artifactScore := containsCount(joined, artifactMarkers)
	codeScore := containsCount(joined, codeMarkers)
	docsScore := containsCount(joined, docsMarkers)
	schemaScore := containsCount(joined, schemaMarkers)

	if workspaceScore > 0 {
		addSignal("workspace-context")
	}
	if artifactScore > 0 {
		addSignal("file-or-doc-artifact")
	}
	if codeScore > 0 {
		addSignal("code-context")
	}
	if docsScore > 0 {
		addSignal("docs-context")
	}
	if schemaScore > 0 {
		addSignal("schema-context")
	}
	if reviewScore > 0 || summarizeScore > 0 || explainScore > 0 {
		addSignal("read-operation")
	}
	if editScore > 0 || generateScore > 0 {
		addSignal("write-operation")
	}

	requiresLocalFiles := false
	switch {
	case workspaceScore > 0 && (artifactScore > 0 || reviewScore > 0 || editScore > 0 || generateScore > 0 || debugScore > 0 || planScore > 0):
		requiresLocalFiles = true
	case artifactScore >= 2 && (reviewScore > 0 || editScore > 0 || generateScore > 0 || debugScore > 0 || explainScore > 0):
		requiresLocalFiles = true
	case strings.Contains(joined, "this project") && artifactScore > 0:
		requiresLocalFiles = true
	case strings.Contains(joined, "this repo") && artifactScore > 0:
		requiresLocalFiles = true
	case strings.Contains(joined, "pipeline docs"):
		requiresLocalFiles = true
	}
	if containsAny(joined, promptOnlyMarkers) {
		requiresLocalFiles = false
		addSignal("explicit-prompt-only")
	}

	explicitWriteAccess := editScore > 0
	generatedArtifactIntent := generateScore > 0 && containsAny(joined, []string{"new ", "more ", "fresh ", "output", "json", "lesson", "lessons", "content pack", "glossary", "website", "landing page", "component", "page", "app", "canvas", "webgl", "three.js", "threejs"})
	wantsWriteAccess := requiresLocalFiles && (explicitWriteAccess || generatedArtifactIntent)
	dataAccess := requestDataPromptOnly
	if wantsWriteAccess {
		dataAccess = requestDataWorkspaceWrite
	} else if requiresLocalFiles {
		dataAccess = requestDataWorkspaceRead
	}

	taskKind := requestTaskGeneric
	promptOnlyOrganizeIntent := !requiresLocalFiles && (strings.HasPrefix(joined, "categorize ") || strings.HasPrefix(joined, "classify ") || strings.HasPrefix(joined, "tag ") || strings.HasPrefix(joined, "sort ") || strings.HasPrefix(joined, "rename these ") || (strings.Contains(joined, "bug reports") && (strings.Contains(joined, "categorize") || strings.Contains(joined, "classify"))))
	switch {
	case promptOnlyOrganizeIntent:
		taskKind = requestTaskSummarize
	case requiresLocalFiles && wantsWriteAccess && generateScore > 0 && generateScore >= editScore:
		taskKind = requestTaskGenerate
	case requiresLocalFiles && wantsWriteAccess:
		taskKind = requestTaskTransform
	case requiresLocalFiles && debugScore > 0 && reviewScore == 0 && explainScore == 0:
		taskKind = requestTaskDebug
	case requiresLocalFiles:
		taskKind = requestTaskReview
	case translateScore > 0:
		taskKind = requestTaskTranslate
	case summarizeScore > 0:
		taskKind = requestTaskSummarize
	case planScore > 0:
		taskKind = requestTaskPlan
	case generateScore > 0:
		taskKind = requestTaskGenerate
	case editScore > 0:
		taskKind = requestTaskTransform
	case explainScore > 0:
		taskKind = requestTaskExplain
	case debugScore > 0:
		taskKind = requestTaskDebug
	}

	sensitivity := requestSensitivityLow
	if containsAny(joined, highSensitivityMarkers) {
		sensitivity = requestSensitivityHigh
		addSignal("high-sensitivity")
	} else if containsAny(joined, mediumSensitivityMarkers) {
		sensitivity = requestSensitivityMedium
		addSignal("medium-sensitivity")
	}

	complexity := requestComplexityNormal
	switch {
	case !requiresLocalFiles && (taskKind == requestTaskSummarize || taskKind == requestTaskTranslate):
		complexity = requestComplexitySimple
		addSignal("simple-request")
	case !requiresLocalFiles && taskKind == requestTaskGeneric && containsAny(joined, []string{"onlymacs", "swarm", "queue", "session", "models are visible"}):
		complexity = requestComplexitySimple
		addSignal("simple-request")
	case wantsWriteAccess && containsAny(joined, []string{"content pipeline", "pipeline docs", "new json", "fresh batch", "five more", "tests", "source tree", "race condition", "import paths", "content pack", "output files", "glossary json", "lesson files", "example files", "refactor", "duplicate helpers", "build passes", "failing test", "website", "landing page", "canvas", "webgl", "three.js", "threejs", "frontend", "react", "vite", "tailwind"}):
		complexity = requestComplexityHeavy
		addSignal("heavy-request")
	case requiresLocalFiles && containsAny(joined, []string{"content pipeline", "pipeline docs", "architecture", "source tree", "concurrency", "race condition", "contradictions", "drift", "weak spots", "import paths", "tests", "auth flow", "unclear", "tell me what is missing", "inconsistent", "onboarding gaps", "website", "landing page", "canvas", "webgl", "three.js", "threejs", "frontend", "react", "vite", "tailwind"}):
		complexity = requestComplexityHeavy
		addSignal("heavy-request")
	}

	recommendedRouteScope := routeScopeSwarm
	switch {
	case sensitivity == requestSensitivityHigh:
		recommendedRouteScope = routeScopeLocalOnly
	case requiresLocalFiles:
		recommendedRouteScope = routeScopeTrustedOnly
	}

	looksLikeCodeContext := codeScore > 0
	looksLikeDocsContext := docsScore > 0
	looksLikeSchemaContext := schemaScore > 0
	publicCapsuleFriendly := requiresLocalFiles &&
		sensitivity != requestSensitivityHigh &&
		!looksLikeCodeContext &&
		(looksLikeDocsContext || looksLikeSchemaContext || taskKind == requestTaskSummarize || taskKind == requestTaskExplain)

	return requestPolicyClassification{
		TaskKind:               taskKind,
		DataAccess:             dataAccess,
		RequiresLocalFiles:     requiresLocalFiles,
		WantsWriteAccess:       wantsWriteAccess,
		PublicCapsuleFriendly:  publicCapsuleFriendly,
		LooksLikeCodeContext:   looksLikeCodeContext,
		LooksLikeDocsContext:   looksLikeDocsContext,
		LooksLikeSchemaContext: looksLikeSchemaContext,
		Sensitivity:            sensitivity,
		Complexity:             complexity,
		RecommendedRouteScope:  recommendedRouteScope,
		MatchedSignals:         signals,
	}
}

func suggestRequestRouting(prompt string, classification requestPolicyClassification) requestPolicyRouting {
	joined := strings.ToLower(strings.TrimSpace(prompt))
	planMarkers := []string{"make a plan", "plan this", "plan the", "before you start", "estimate", "how many agents", "scope this", "what's the plan", "what is the plan"}
	parallelMarkers := []string{"parallel", "parallelize", "fan out", "workstreams", "multiple agents", "multi-agent", "split this refactor", "split this work"}
	launchMarkers := []string{"start ", "run ", "launch ", "spin up", "kick off", "dispatch"}

	routing := requestPolicyRouting{
		SuggestedCommand: "chat",
		SuggestedPreset:  "balanced",
		Explanation:      "This looks like a prompt-only request, so OnlyMacs will use the standard chat path.",
	}

	switch {
	case classification.Sensitivity == requestSensitivityHigh:
		routing.SuggestedPreset = "local-first"
		routing.Explanation = "This looks sensitive, so OnlyMacs recommends keeping it on This Mac."
	case classification.RequiresLocalFiles:
		routing.SuggestedPreset = "trusted-only"
		routing.Explanation = "This looks like it needs repo or file context, so OnlyMacs will keep it on a trusted route and ask for approval before exporting files."
	}

	if containsAny(joined, parallelMarkers) {
		routing.SuggestedPreset = "wide"
		if containsAny(joined, planMarkers) {
			routing.SuggestedCommand = "plan"
			routing.Explanation = "This looks like multi-agent work, and you asked for a plan first, so OnlyMacs will plan a wider swarm."
		} else if containsAny(joined, launchMarkers) {
			routing.SuggestedCommand = "go"
			routing.Explanation = "This looks like multi-agent work and you asked to run it, so OnlyMacs will launch a wider swarm."
		} else {
			routing.SuggestedCommand = "plan"
			routing.Explanation = "This looks like multi-agent work, so OnlyMacs will plan a wider swarm first."
		}
		return routing
	}

	if containsAny(joined, planMarkers) {
		routing.SuggestedCommand = "plan"
		if classification.Sensitivity == requestSensitivityHigh {
			routing.Explanation = "This looks sensitive, so OnlyMacs will keep it on This Mac and start with a plan."
		} else if classification.RequiresLocalFiles {
			routing.Explanation = "This looks like planning work with repo or file context, so OnlyMacs will start with a trusted plan."
		} else {
			routing.Explanation = "This sounds like planning or estimation work, so OnlyMacs will start with a plan."
		}
	}

	return routing
}

func resolveRequestPolicy(classification requestPolicyClassification, routing requestPolicyRouting, routeScope string, activeSwarmVisibility string, activeSwarmName string, policies ...*swarmContextPolicy) requestPolicyResponse {
	routeScope = normalizeRouteScope(routeScope)
	activeSwarmVisibility = strings.ToLower(strings.TrimSpace(activeSwarmVisibility))
	activeSwarmPolicy := normalizedBridgeSwarmContextPolicy(firstSwarmContextPolicy(policies), activeSwarmVisibility)
	reasons := []string{}

	if routeScope == routeScopeLocalOnly {
		reasons = append(reasons, "This request is already staying on This Mac.")
		fileAccessPlan := buildRequestPolicyFileAccessPlan(classification, requestPolicyAllowCurrent, routeScope, activeSwarmVisibility, activeSwarmPolicy)
		return requestPolicyResponse{
			Classification:        classification,
			Routing:               routing,
			FileAccessPlan:        fileAccessPlan,
			Decision:              requestPolicyAllowCurrent,
			ActiveSwarmVisibility: activeSwarmVisibility,
			ActiveSwarmName:       activeSwarmName,
			SwarmContextPolicy:    activeSwarmPolicy,
			Reasons:               reasons,
		}
	}

	if classification.Sensitivity == requestSensitivityHigh {
		reasons = append(reasons, "This request looks sensitive enough that OnlyMacs recommends keeping it on This Mac.")
		fileAccessPlan := buildRequestPolicyFileAccessPlan(classification, requestPolicyLocalOnlyRecommended, routeScope, activeSwarmVisibility, activeSwarmPolicy)
		return requestPolicyResponse{
			Classification:        classification,
			Routing:               routing,
			FileAccessPlan:        fileAccessPlan,
			Decision:              requestPolicyLocalOnlyRecommended,
			ActiveSwarmVisibility: activeSwarmVisibility,
			ActiveSwarmName:       activeSwarmName,
			SwarmContextPolicy:    activeSwarmPolicy,
			Reasons:               reasons,
		}
	}

	if !classification.RequiresLocalFiles {
		reasons = append(reasons, "This request does not need local files or repo access.")
		fileAccessPlan := buildRequestPolicyFileAccessPlan(classification, requestPolicyAllowCurrent, routeScope, activeSwarmVisibility, activeSwarmPolicy)
		return requestPolicyResponse{
			Classification:        classification,
			Routing:               routing,
			FileAccessPlan:        fileAccessPlan,
			Decision:              requestPolicyAllowCurrent,
			ActiveSwarmVisibility: activeSwarmVisibility,
			ActiveSwarmName:       activeSwarmName,
			SwarmContextPolicy:    activeSwarmPolicy,
			Reasons:               reasons,
		}
	}

	switch activeSwarmVisibility {
	case "public":
		if classification.PublicCapsuleFriendly {
			reasons = append(reasons, "This request can use an approved public context capsule with excerpts only and no repo browsing.")
			fileAccessPlan := buildRequestPolicyFileAccessPlan(classification, requestPolicyPublicExport, routeScope, activeSwarmVisibility, activeSwarmPolicy)
			return requestPolicyResponse{
				Classification:        classification,
				Routing:               routing,
				FileAccessPlan:        fileAccessPlan,
				Decision:              requestPolicyPublicExport,
				ActiveSwarmVisibility: activeSwarmVisibility,
				ActiveSwarmName:       activeSwarmName,
				SwarmContextPolicy:    activeSwarmPolicy,
				Reasons:               reasons,
			}
		}
		reasons = append(reasons, "Open swarms are prompt-only and cannot access local files or repo context.")
		fileAccessPlan := buildRequestPolicyFileAccessPlan(classification, requestPolicyBlockedPublic, routeScope, activeSwarmVisibility, activeSwarmPolicy)
		return requestPolicyResponse{
			Classification:        classification,
			Routing:               routing,
			FileAccessPlan:        fileAccessPlan,
			Decision:              requestPolicyBlockedPublic,
			ActiveSwarmVisibility: activeSwarmVisibility,
			ActiveSwarmName:       activeSwarmName,
			SwarmContextPolicy:    activeSwarmPolicy,
			Reasons:               reasons,
		}
	case "private":
		reasons = append(reasons, "This request needs a context export before your private swarm can work on it.")
		if classification.WantsWriteAccess {
			reasons = append(reasons, "OnlyMacs will use the swarm's configured write policy for returned artifacts and patches.")
		}
		fileAccessPlan := buildRequestPolicyFileAccessPlan(classification, requestPolicyPrivateExport, routeScope, activeSwarmVisibility, activeSwarmPolicy)
		return requestPolicyResponse{
			Classification:        classification,
			Routing:               routing,
			FileAccessPlan:        fileAccessPlan,
			Decision:              requestPolicyPrivateExport,
			ActiveSwarmVisibility: activeSwarmVisibility,
			ActiveSwarmName:       activeSwarmName,
			SwarmContextPolicy:    activeSwarmPolicy,
			Reasons:               reasons,
		}
	default:
		reasons = append(reasons, "OnlyMacs could not verify that the current swarm is private, so it will not export local files.")
		fileAccessPlan := buildRequestPolicyFileAccessPlan(classification, requestPolicyBlockedUnverified, routeScope, activeSwarmVisibility, activeSwarmPolicy)
		return requestPolicyResponse{
			Classification:        classification,
			Routing:               routing,
			FileAccessPlan:        fileAccessPlan,
			Decision:              requestPolicyBlockedUnverified,
			ActiveSwarmVisibility: activeSwarmVisibility,
			ActiveSwarmName:       activeSwarmName,
			SwarmContextPolicy:    activeSwarmPolicy,
			Reasons:               reasons,
		}
	}
}

func firstSwarmContextPolicy(policies []*swarmContextPolicy) *swarmContextPolicy {
	for _, policy := range policies {
		if policy != nil {
			return policy
		}
	}
	return nil
}

func requestPolicyLooksSensitive(prompt string, messages []chatMessage) bool {
	return classifyRequestPolicy(prompt, messages).Sensitivity == requestSensitivityHigh
}

func requestPolicyLooksTrivial(prompt string, messages []chatMessage) bool {
	return classifyRequestPolicy(prompt, messages).Complexity == requestComplexitySimple
}

func containsCount(haystack string, needles []string) int {
	count := 0
	for _, needle := range needles {
		if containsSignal(haystack, needle) {
			count++
		}
	}
	return count
}

func containsAny(haystack string, needles []string) bool {
	return containsCount(haystack, needles) > 0
}

func messageContents(messages []chatMessage) []string {
	if len(messages) == 0 {
		return nil
	}
	contents := make([]string, 0, len(messages))
	for _, message := range messages {
		contents = append(contents, message.Content)
	}
	return contents
}

func containsSignal(haystack string, needle string) bool {
	normalizedHaystack := normalizeSignalText(haystack)
	normalizedNeedle := normalizeSignalText(needle)
	if normalizedNeedle == "" {
		return false
	}
	return strings.Contains(normalizedHaystack, normalizedNeedle)
}

func normalizeSignalText(input string) string {
	fields := strings.FieldsFunc(strings.ToLower(input), func(r rune) bool {
		return !(unicode.IsLetter(r) || unicode.IsDigit(r))
	})
	if len(fields) == 0 {
		return ""
	}
	return " " + strings.Join(fields, " ") + " "
}
