import Foundation
import SwiftUI

func activeRuntimeSwarmOption(
    swarms: [SwarmOption],
    activeSwarmID: String,
    activeSwarmName: String?,
    swarm: SwarmCapacitySummary,
    memberCount: Int
) -> SwarmOption? {
    let normalizedSwarmID = activeSwarmID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedSwarmID.isEmpty else { return nil }
    if let current = swarms.first(where: { $0.id == normalizedSwarmID }) {
        return current
    }
    let normalizedName = activeSwarmName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallbackName: String
    if let normalizedName, !normalizedName.isEmpty {
        fallbackName = normalizedName
    } else if normalizedSwarmID == "swarm-public" {
        fallbackName = "OnlyMacs Public"
    } else {
        fallbackName = normalizedSwarmID
    }
    return SwarmOption(
        id: normalizedSwarmID,
        name: fallbackName,
        visibility: normalizedSwarmID == "swarm-public" ? "public" : "private",
        memberCount: memberCount,
        slotsFree: swarm.slotsFree,
        slotsTotal: swarm.slotsTotal
    )
}

enum HowToUseRecipeSection: String, CaseIterable, Identifiable {
    case publicSwarm
    case privateSwarm
    case localFirst
    case parameters

    var id: String { rawValue }

    var title: String {
        switch self {
        case .publicSwarm:
            return "Public Swarm"
        case .privateSwarm:
            return "Private Swarm"
        case .localFirst:
            return "Local-First"
        case .parameters:
            return "Parameters"
        }
    }

    var detail: String {
        switch self {
        case .publicSwarm:
            return "Use Public when you only need to share a few safe slices from your repo. Ask normally with `/onlymacs ...`, approve the exact docs or file excerpts OnlyMacs asks for, and the rest of the repo stays private."
        case .privateSwarm:
            return "Use Private when you want real help on the repo itself. Naked `/onlymacs ...` is the normal path here, and OnlyMacs will ask for project access only when it actually needs files from your Macs."
        case .localFirst:
            return "`local-first` means keep it on This Mac today. Use it when secrets, auth, config, logs, or anything else sensitive should not leave your machine."
        case .parameters:
            return "These are the main explicit commands, routes, width controls, and flags you can add when you want to steer `/onlymacs` more directly. You do not need them for normal use."
        }
    }

    var tint: Color {
        switch self {
        case .publicSwarm:
            return Color(red: 0.41, green: 0.76, blue: 0.73)
        case .privateSwarm:
            return Color(red: 0.58, green: 0.69, blue: 0.96)
        case .localFirst:
            return Color(red: 0.96, green: 0.66, blue: 0.58)
        case .parameters:
            return Color(red: 0.82, green: 0.68, blue: 0.94)
        }
    }
}

enum MenuBarVisualState: Equatable {
    case loading
    case ready
    case usingRemote
    case sharing
    case both
    case degraded

    var iconName: String {
        switch self {
        case .loading:
            return "arrow.triangle.2.circlepath"
        case .ready:
            return "bolt.horizontal.circle.fill"
        case .usingRemote:
            return "arrow.up.circle.fill"
        case .sharing:
            return "arrow.down.circle.fill"
        case .both:
            return "arrow.left.arrow.right.circle.fill"
        case .degraded:
            return "exclamationmark.triangle.fill"
        }
    }

    var title: String {
        switch self {
        case .loading:
            return "Loading"
        case .ready:
            return "Ready"
        case .usingRemote:
            return "Using"
        case .sharing:
            return "Sharing"
        case .both:
            return "Using + Sharing"
        case .degraded:
            return "Needs Attention"
        }
    }

    var usesCircularBase: Bool {
        switch self {
        case .usingRemote, .sharing, .both:
            return true
        case .loading, .ready, .degraded:
            return false
        }
    }
}

enum LocalEligibilityCode: String, Equatable {
    case publishedAndHealthy = "published_and_healthy"
    case runtimeNotReady = "runtime_not_ready"
    case noActiveSwarm = "no_active_swarm"
    case modeDoesNotShare = "mode_does_not_share"
    case noLocalModels = "no_local_models"
    case notPublished = "not_published"
    case localSlotBusy = "local_slot_busy"
    case shareHealthDegraded = "share_health_degraded"
}

struct LocalEligibilitySummary: Equatable {
    let code: LocalEligibilityCode
    let title: String
    let shortLabel: String
    let detail: String
    let recoveryHint: String?

    var isEligible: Bool {
        code == .publishedAndHealthy
    }
}

enum ModelRuntimeDependencyBannerStyle: Equatable {
    case actionRequired
    case success

    var tint: Color {
        switch self {
        case .actionRequired:
            return .accentColor
        case .success:
            return .green
        }
    }

    var backgroundColor: Color {
        switch self {
        case .actionRequired:
            return Color.accentColor.opacity(0.08)
        case .success:
            return Color.green.opacity(0.10)
        }
    }

    var badgeBackgroundColor: Color {
        switch self {
        case .actionRequired:
            return Color.accentColor.opacity(0.14)
        case .success:
            return Color.green.opacity(0.16)
        }
    }
}

struct ModelRuntimeDependencyPresentation: Equatable {
    let title: String
    let detail: String
    let labelTitle: String
    let systemImage: String
    let style: ModelRuntimeDependencyBannerStyle
    let isActionable: Bool
}

struct SwarmActivityStatusPresentation: Equatable {
    let label: String
    let detail: String
}

func deriveSessionTokensUsed(
    tokensSavedEstimate: Int,
    uploadedTokensEstimate: Int,
    baselineSavedTokens: Int?,
    baselineUploadedTokens: Int?
) -> Int {
    let savedBaseline = max(0, baselineSavedTokens ?? tokensSavedEstimate)
    let uploadedBaseline = max(0, baselineUploadedTokens ?? uploadedTokensEstimate)
    let savedDelta = max(0, tokensSavedEstimate - savedBaseline)
    let uploadedDelta = max(0, uploadedTokensEstimate - uploadedBaseline)
    return savedDelta + uploadedDelta
}

func deriveLifetimeTokensUsed(
    tokensSavedEstimate: Int,
    uploadedTokensEstimate: Int
) -> Int {
    max(0, tokensSavedEstimate) + max(0, uploadedTokensEstimate)
}

func deriveHowToUseRecipeItems() -> [HowToUseRecipeItem] {
    [
        HowToUseRecipeItem(
            title: "Review A Current README Section",
            detail: "Useful when you want public workers to analyze the exact docs you choose from your repo without opening the rest of the project.",
            command: #"/onlymacs "review the current README section and tell me what is unclear, redundant, or likely to confuse a new engineer""#,
            section: .publicSwarm,
            symbolName: "doc.text.magnifyingglass",
            tint: .teal
        ),
        HowToUseRecipeItem(
            title: "Compare Two Spec Excerpts",
            detail: "A good public-safe use case when you want drift or contradictions called out from two exact spec slices.",
            command: #"/onlymacs "compare these two spec excerpts and tell me where they drift, contradict each other, or leave decisions unresolved""#,
            section: .publicSwarm,
            symbolName: "square.stack.3d.up.fill",
            tint: .mint
        ),
        HowToUseRecipeItem(
            title: "Explain A Schema With Examples",
            detail: "Strong public-swarm fit for safe schemas and example files where you want explanation, weak spots, and missing examples.",
            command: #"/onlymacs "explain this schema and the two example JSON files in plain English, and call out the fragile fields or missing examples""#,
            section: .publicSwarm,
            symbolName: "tablecells.badge.ellipsis",
            tint: .orange
        ),
        HowToUseRecipeItem(
            title: "Generate Structured Output From Pipeline Inputs",
            detail: "One of the most practical public-safe content asks: let OnlyMacs request the intake, schema, glossary, and examples it needs, then draft new output from those slices.",
            command: #"/onlymacs "generate five more entries from the current intake, schema, glossary, and example JSON files""#,
            section: .publicSwarm,
            symbolName: "wand.and.stars.inverse",
            tint: .indigo
        ),
        HowToUseRecipeItem(
            title: "Rewrite A Current Docs Section",
            detail: "Useful when you want a better version of an existing Markdown or docs slice without exposing broader repo context.",
            command: #"/onlymacs "rewrite this current docs section for clarity, keep the meaning, and give me the best replacement text plus the key changes""#,
            section: .publicSwarm,
            symbolName: "text.quote",
            tint: .blue
        ),
        HowToUseRecipeItem(
            title: "Turn Workflow Docs Into A Checklist",
            detail: "A strong operator-style ask when you want a tighter checklist back from the exact workflow slices you choose.",
            command: #"/onlymacs "turn this workflow doc into a concise checklist and flag anything still too vague to execute safely""#,
            section: .publicSwarm,
            symbolName: "checklist",
            tint: .purple
        ),
        HowToUseRecipeItem(
            title: "Audit Prompt Templates",
            detail: "Great for prompt packs, instruction docs, and agent templates that are safe to share as excerpts but still need serious critique.",
            command: #"/onlymacs "audit these prompt templates, examples, and instruction docs for ambiguity, redundancy, or likely failure points""#,
            section: .publicSwarm,
            symbolName: "bolt.bubble.fill",
            tint: .green
        ),
        HowToUseRecipeItem(
            title: "Draft A New Output From Current Inputs",
            detail: "This is the broader context-aware public pattern: pick the safe source slices, then ask for a real deliverable back, not just commentary.",
            command: #"/onlymacs "use the current intake notes, schema, and examples to draft the next full output in the same format and tone""#,
            section: .publicSwarm,
            symbolName: "text.book.closed.fill",
            tint: .cyan
        ),
        HowToUseRecipeItem(
            title: "Review A Config Schema And Example",
            detail: "Public-safe schemas and example configs are a strong fit when you want confusion, risk, or missing guidance called out.",
            command: #"/onlymacs "review this config schema, example file, and validation notes, and tell me what fields are confusing, risky, or missing examples""#,
            section: .publicSwarm,
            symbolName: "square.grid.2x2.fill",
            tint: .yellow
        ),
        HowToUseRecipeItem(
            title: "Work On A Current Repo File Slice",
            detail: "This is the public-safe current-file example: let OnlyMacs ask for the exact Markdown, docs, schema, or example slice it needs. Use private or local for real code files.",
            command: #"/onlymacs "work on this current file slice, propose the best revision, and give me the replacement text I should paste back in""#,
            section: .publicSwarm,
            symbolName: "doc.plaintext.fill",
            tint: .pink
        ),
        HowToUseRecipeItem(
            title: "Map A New Repo",
            detail: "Best first ask after you open an unfamiliar project. In a private swarm you can usually say this plainly and let OnlyMacs infer the trusted route.",
            command: #"/onlymacs "summarize this repo, point out the main entrypoints, and tell me where to start""#,
            section: .privateSwarm,
            symbolName: "map.fill",
            tint: .blue
        ),
        HowToUseRecipeItem(
            title: "Review My Current Diff",
            detail: "One of the highest-value private-swarm asks when you want real code review grounded in the files you are actively changing.",
            command: #"/onlymacs "review my current diff for bugs, regressions, risky assumptions, and missing tests""#,
            section: .privateSwarm,
            symbolName: "checkmark.shield.fill",
            tint: .green
        ),
        HowToUseRecipeItem(
            title: "Find The Right Files To Touch",
            detail: "Useful when you know the outcome you want but not the safest entrypoint in the existing codebase.",
            command: #"/onlymacs "tell me which files I should touch first for this feature, why they matter, and what I should avoid changing""#,
            section: .privateSwarm,
            symbolName: "doc.text.magnifyingglass",
            tint: .orange
        ),
        HowToUseRecipeItem(
            title: "Find Doc-Code Drift",
            detail: "A strong repo-aware ask when you want OnlyMacs to compare implementation and documentation instead of reviewing either in isolation.",
            command: #"/onlymacs "tell me where the docs and the code drift in this project, and which mismatches are most likely to hurt us""#,
            section: .privateSwarm,
            symbolName: "arrow.triangle.branch",
            tint: .indigo
        ),
        HowToUseRecipeItem(
            title: "Explain The Current Architecture",
            detail: "Good for vibe-coding context loading when you want a map of the system before changing anything.",
            command: #"/onlymacs "explain the current architecture of this repo, the main flows, and what I should touch first if I want to improve it""#,
            section: .privateSwarm,
            symbolName: "building.columns.fill",
            tint: .teal
        ),
        HowToUseRecipeItem(
            title: "Draft Missing Tests",
            detail: "A practical repo-aware ask when you want OnlyMacs to use the real module and neighboring files instead of guessing from a snippet.",
            command: #"/onlymacs "look at this module in context and draft the missing tests that would catch the likeliest regressions""#,
            section: .privateSwarm,
            symbolName: "wand.and.stars.inverse",
            tint: .purple
        ),
        HowToUseRecipeItem(
            title: "Trace The Main Request Path",
            detail: "Helpful when you need a grounded explanation of what code runs first and where the likely failure points are.",
            command: #"/onlymacs "trace the main request path in this codebase and point out the likeliest failure modes""#,
            section: .privateSwarm,
            symbolName: "point.topleft.down.curvedto.point.bottomright.up.fill",
            tint: .pink
        ),
        HowToUseRecipeItem(
            title: "Propose The Safest Patch",
            detail: "Use this when you want private-swarm help on an existing bug but still want the result back as suggested patch text.",
            command: #"/onlymacs "review this target file in context and give me the safest patch for the bug, plus the risks of applying it""#,
            section: .privateSwarm,
            symbolName: "pencil.and.list.clipboard",
            tint: .blue
        ),
        HowToUseRecipeItem(
            title: "Split A Refactor Into Workstreams",
            detail: "This is the stronger multi-agent planning example: still a normal private-swarm ask, just with explicit width because you want decomposition first.",
            command: #"/onlymacs plan 3 "split this refactor into workstreams, tell me what each agent should own, and show the safest order to merge the work""#,
            section: .privateSwarm,
            symbolName: "person.3.sequence.fill",
            tint: .cyan
        ),
        HowToUseRecipeItem(
            title: "Keep It Explicit On Your Macs",
            detail: "Same kind of private repo-aware work, but with the route written out when you want zero ambiguity about trust scope.",
            command: #"/onlymacs go trusted-only "review this repo on my Macs only and tell me where the risk is highest""#,
            section: .privateSwarm,
            symbolName: "lock.open.trianglebadge.exclamationmark",
            tint: .blue
        ),
        HowToUseRecipeItem(
            title: "Review An Auth Flow",
            detail: "Use local-first when the code path includes secrets, personal data, or config that should not leave This Mac.",
            command: #"/onlymacs go local-first "review this private auth flow for secret leakage, unsafe assumptions, and risky defaults""#,
            section: .localFirst,
            symbolName: "lock.shield.fill",
            tint: .red
        ),
        HowToUseRecipeItem(
            title: "Inspect Config And Env Defaults",
            detail: "Great for local-only config work when the fastest safe answer is on the machine in front of you.",
            command: #"/onlymacs go local-first "inspect this config and env setup for unsafe defaults, missing guards, and anything that should not leave This Mac""#,
            section: .localFirst,
            symbolName: "gearshape.2.fill",
            tint: .orange
        ),
        HowToUseRecipeItem(
            title: "Brainstorm Locally",
            detail: "You can still use chat form when you want the local model but do not need a bigger swarm shape around it.",
            command: #"/onlymacs chat local-first "brainstorm the safest fix for this local-only bug without leaving This Mac""#,
            section: .localFirst,
            symbolName: "bubble.left.and.exclamationmark.bubble.right.fill",
            tint: .yellow
        ),
        HowToUseRecipeItem(
            title: "Plan A Sensitive Cleanup",
            detail: "Use a local-first plan when you want sequencing help but the code path should stay fully local.",
            command: #"/onlymacs plan local-first "plan the safest cleanup of this secret-handling module""#,
            section: .localFirst,
            symbolName: "list.number",
            tint: .pink
        ),
        HowToUseRecipeItem(
            title: "Read Local Logs",
            detail: "This is a strong local-first ask when the logs may contain tokens, secrets, or machine-specific state.",
            command: #"/onlymacs go local-first "read these local logs and tell me the likeliest root cause without using other Macs""#,
            section: .localFirst,
            symbolName: "doc.badge.magnifyingglass",
            tint: .blue
        ),
        HowToUseRecipeItem(
            title: "Audit Token Refresh",
            detail: "Use this for auth and cache paths where even a trusted export is more exposure than you want.",
            command: #"/onlymacs go local-first "review this token refresh path for unsafe caching, leakage, or retry assumptions""#,
            section: .localFirst,
            symbolName: "arrow.triangle.2.circlepath.circle.fill",
            tint: .green
        ),
        HowToUseRecipeItem(
            title: "Summarize Secret Rotation Options",
            detail: "A lighter local-only ask that still benefits from explicit route control when the topic is sensitive.",
            command: #"/onlymacs chat local-first "summarize the tradeoffs of these credential rotation options and tell me which one is safest to implement first""#,
            section: .localFirst,
            symbolName: "key.horizontal.fill",
            tint: .mint
        ),
        HowToUseRecipeItem(
            title: "Audit A Migration Before Running It",
            detail: "Use local-first for migrations, deploy plans, and destructive flows when the safe answer matters more than wider capacity.",
            command: #"/onlymacs go local-first "audit this SQL migration and tell me the risky assumptions before I run it""#,
            section: .localFirst,
            symbolName: "externaldrive.badge.exclamationmark",
            tint: .purple
        ),
        HowToUseRecipeItem(
            title: "Review Deployment Config",
            detail: "Another local-first case for secrets, infrastructure defaults, and rollback-sensitive settings.",
            command: #"/onlymacs go local-first "review this deployment config for secrets, unsafe defaults, and rollback risks""#,
            section: .localFirst,
            symbolName: "server.rack",
            tint: .indigo
        ),
        HowToUseRecipeItem(
            title: "Stage A Safe Auth Change",
            detail: "Use a local-first plan when you want help sequencing a sensitive change without widening the route.",
            command: #"/onlymacs plan local-first "tell me the safest order to change this auth and config flow without breaking sign-in""#,
            section: .localFirst,
            symbolName: "checkmark.seal.fill",
            tint: .red
        ),
    ]
}

func deriveHowToUseStrategyItems() -> [HowToUseStrategyItem] {
        [
            HowToUseStrategyItem(
                title: #"/onlymacs "review this README section""#,
                detail: "Just say what you want done with `/onlymacs ...`. OnlyMacs is supposed to infer the route and ask for approval only when it really needs repo files.",
                routeLabel: "Any Route",
                symbolName: "text.bubble.fill",
                tint: .teal
            ),
            HowToUseStrategyItem(
                title: #"/onlymacs "review this config and ask for any files you need""#,
                detail: "You do not have to narrate file approval in the prompt. Ask naturally, then use the approval window to decide exactly what the worker can see.",
                routeLabel: "Public + Private",
                symbolName: "checkmark.shield.fill",
                tint: .blue
            ),
            HowToUseStrategyItem(
                title: #"/onlymacs "compare these public-safe spec excerpts""#,
                detail: "Public is best when a few docs, schemas, examples, or current file slices are enough. It is not the right place for full repo browsing or normal code review.",
                routeLabel: "Public",
                symbolName: "globe",
                tint: .mint
            ),
            HowToUseStrategyItem(
                title: #"/onlymacs go trusted-only "review my current diff""#,
                detail: "If you want help tracing code paths, reviewing a diff, finding the right files, or planning a patch across the repo, private is the normal power path.",
                routeLabel: "Private",
                symbolName: "lock.fill",
                tint: .indigo
            ),
            HowToUseStrategyItem(
                title: #"/onlymacs go local-first "review this auth flow""#,
                detail: "If the work touches auth, secrets, config, logs, or anything else you do not want exported, switch to `local-first` and keep it on This Mac.",
                routeLabel: "Local-First",
                symbolName: "desktopcomputer",
                tint: .red
            ),
            HowToUseStrategyItem(
                title: #"/onlymacs "draft the safest patch plan""#,
                detail: "OnlyMacs works better when you ask for the end result you want, like a review, a replacement section, a patch plan, or a generated file, instead of micromanaging how to get there.",
                routeLabel: "Any Route",
                symbolName: "target",
                tint: .orange
            ),
            HowToUseStrategyItem(
                title: #"/onlymacs "generate entries from this intake and schema""#,
                detail: "For content generation, mention the source materials you want used, like intake, schema, examples, glossary, or pipeline docs. That helps OnlyMacs suggest and preselect the right files.",
                routeLabel: "Public + Private",
                symbolName: "shippingbox.fill",
                tint: .purple
            ),
            HowToUseStrategyItem(
                title: #"/onlymacs "find the issues before rewriting""#,
                detail: "When the task is risky, do it in two passes: first ask OnlyMacs to find issues, then ask for the safest patch or replacement text once you agree with the direction.",
                routeLabel: "Private",
                symbolName: "arrow.triangle.branch",
                tint: .green
            ),
            HowToUseStrategyItem(
                title: #"/onlymacs plan 4 "split this audit into tracks""#,
                detail: "Use wider or multi-agent runs for audits, decomposable refactors, or batch generation. If the task is one tight logic path, a plain naked `/onlymacs ...` ask is usually better.",
                routeLabel: "Private",
                symbolName: "person.3.sequence.fill",
                tint: .cyan
            ),
            HowToUseStrategyItem(
                title: #"/onlymacs go precise "review this risky module""#,
                detail: "Most of the time the default form is enough. Add `trusted-only`, `local-first`, `plan`, or width only when you want to remove ambiguity or steer a special case.",
                routeLabel: "Any Route",
            symbolName: "slider.horizontal.3",
            tint: .yellow
        )
    ]
}

func deriveHowToUseParameterItems() -> [HowToUseParameterItem] {
    [
        HowToUseParameterItem(
            title: "Default /onlymacs Form",
            syntax: #"/onlymacs "review this project and tell me where the risk is highest""#,
            kindLabel: "Default",
            tint: .teal,
            detail: "This is the normal way to use OnlyMacs. Prompt-only work tries another Mac first, large work auto-upgrades into a planned run, and file-bound or sensitive work is stopped, kept local, or routed through approval."
        ),
        HowToUseParameterItem(
            title: "go / start",
            syntax: #"/onlymacs go "review this refactor""#,
            kindLabel: "Launch",
            tint: .blue,
            detail: "Use `go` when you want OnlyMacs to launch the work now. `start` is the direct lower-level form, but `go` is the friendlier command we want most people to use. Pair it with a route alias only when you want to be explicit."
        ),
        HowToUseParameterItem(
            title: "plan",
            syntax: #"/onlymacs plan trusted-only 3 "split this migration into workstreams""#,
            kindLabel: "Plan",
            tint: .indigo,
            detail: "Use `plan` when you want decomposition, admitted-agent thinking, or route sanity before launching anything. This is especially useful for parallelizable work, risky refactors, and vibe-coding tasks where you want a strong game plan first."
        ),
        HowToUseParameterItem(
            title: "chat",
            syntax: #"/onlymacs "brainstorm the safest fix""#,
            kindLabel: "Chat",
            tint: .mint,
            detail: "Use the naked form for normal direct asks. Explicit `chat` is mainly for clarity when you also want to force a route like `local-first` or `trusted-only`."
        ),
        HowToUseParameterItem(
            title: "watch / status / queue",
            syntax: #"/onlymacs watch current"#,
            kindLabel: "Inspect",
            tint: .orange,
            detail: "Use `watch` to keep following a live or queued run, `status` to inspect a run snapshot, and `queue` to see why something is waiting. These are the main explicit read-only controls once work is already in motion."
        ),
        HowToUseParameterItem(
            title: "pause / resume / stop / cancel",
            syntax: #"/onlymacs pause current"#,
            kindLabel: "Control",
            tint: .pink,
            detail: "These are the explicit session controls when you need to intervene after launch. `pause` and `resume` are for live or queued work you may want to continue, while `stop` and `cancel` are the harder exits when you want it gone."
        ),
        HowToUseParameterItem(
            title: "trusted-only",
            syntax: #"/onlymacs go trusted-only "review this repo on my Macs only""#,
            kindLabel: "Route",
            tint: .blue,
            detail: "Use this when you want to force the work onto your private swarm and avoid broader swarm behavior. In a private swarm, naked `/onlymacs ...` often infers this for file-aware work already, but writing it out removes ambiguity."
        ),
        HowToUseParameterItem(
            title: "local-first",
            syntax: #"/onlymacs go local-first "review this auth flow without leaving This Mac""#,
            kindLabel: "Route",
            tint: .red,
            detail: "Use this when the work should stay on This Mac. Today it behaves as a keep-it-local route, not a 'try local then widen later' route. It is the clearest explicit choice for secrets, auth, config, logs, and other sensitive material."
        ),
        HowToUseParameterItem(
            title: "wide + agent count",
            syntax: #"/onlymacs go wide 6 "split this audit into parallel tracks""#,
            kindLabel: "Width",
            tint: .green,
            detail: "Use `wide` when the task is decomposable and you want a broader multi-agent swarm. The number after `go`, `plan`, or `start` is the requested agent count, not a guarantee; OnlyMacs may admit fewer based on slots, model overlap, and trust scope."
        ),
        HowToUseParameterItem(
            title: "quick / offload-max / precise / --yes",
            syntax: #"/onlymacs --yes go offload-max "triage this repo for quick cleanup wins""#,
            kindLabel: "Bias + flag",
            tint: .purple,
            detail: "`quick` biases toward speed, `offload-max` squeezes cheaper or closer capacity before scarcer fallbacks, and `precise` is for when you care more about model quality or consistency. `--yes` skips the extra confirmation step when OnlyMacs clamps or reshapes a launch, so it is best reserved for unattended or fully intentional runs."
        ),
    ]
}

func deriveSwarmActivityStatusPresentation(
    activeRequesterSessions: Int,
    localShareActiveSessions: Int,
    remoteTokensPerSecond: Double,
    localTokensPerSecond: Double
) -> SwarmActivityStatusPresentation {
    let remoteJobs = max(0, activeRequesterSessions)
    let localJobs = max(0, localShareActiveSessions)
    let remoteLabel = remoteJobs == 1 ? "request" : "requests"
    let localLabel = localJobs == 1 ? "job" : "jobs"
    let remoteRate = formatRecentTokenRate(remoteTokensPerSecond)
    let localRate = formatRecentTokenRate(localTokensPerSecond)

    switch (remoteJobs > 0, localJobs > 0) {
    case (true, true):
        let label: String
        if let remoteRate, let localRate {
            label = "Working (Remote / Local, \(remoteRate) / \(localRate))"
        } else {
            label = "Working (Remote / Local)"
        }
        let remoteDetail = remoteRate.map { "\(remoteJobs) \(remoteLabel) at \($0)" } ?? "\(remoteJobs) \(remoteLabel)"
        let localDetail = localRate.map { "\(localJobs) remote \(localLabel) at \($0)" } ?? "\(localJobs) remote \(localLabel)"
        return SwarmActivityStatusPresentation(
            label: label,
            detail: "Status: \(label). This Mac is using swarm help for \(remoteDetail) while also serving \(localDetail)."
        )
    case (true, false):
        let label = remoteRate.map { "Working (Remote, \($0))" } ?? "Working (Remote)"
        let detail = remoteRate.map { "\(remoteJobs) active \(remoteLabel) at \($0)" } ?? "\(remoteJobs) active \(remoteLabel)"
        return SwarmActivityStatusPresentation(
            label: label,
            detail: "Status: \(label). This Mac is using swarm help for \(detail)."
        )
    case (false, true):
        let label = localRate.map { "Working (Local, \($0))" } ?? "Working (Local)"
        let detail = localRate.map { "\(localJobs) remote \(localLabel) at \($0)" } ?? "\(localJobs) remote \(localLabel)"
        return SwarmActivityStatusPresentation(
            label: label,
            detail: "Status: \(label). This Mac is serving \(detail) right now."
        )
    default:
        return SwarmActivityStatusPresentation(
            label: "Idle",
            detail: "Status: Idle. Connected and ready for the next request."
        )
    }
}

private func formatRecentTokenRate(_ tokensPerSecond: Double) -> String? {
    guard tokensPerSecond.isFinite else { return nil }
    let normalized = max(0, tokensPerSecond)
    guard normalized >= 0.1 else { return nil }
    if normalized >= 1_000 {
        let compact = normalized / 1_000
        let value = String(format: compact >= 10 ? "%.0f" : "%.1f", compact)
            .replacingOccurrences(of: ".0", with: "")
        return "\(value)K tokens/s"
    }
    if normalized >= 10 {
        return "\(Int(normalized.rounded())) tokens/s"
    }
    let value = String(format: "%.1f", normalized).replacingOccurrences(of: ".0", with: "")
    return "\(value) tokens/s"
}

func deriveMenuBarVisualState(
    bridgeStatus: String,
    runtimeStatus: String,
    activeRequesterSessions: Int,
    localSharePublished: Bool,
    localShareSlotsFree: Int,
    localShareSlotsTotal: Int,
    hasConfirmedStatus: Bool = true,
    isLoading: Bool = false,
    isRuntimeBusy: Bool = false,
    startupGraceActive: Bool = false
) -> MenuBarVisualState {
    let normalizedBridge = bridgeStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedRuntime = runtimeStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalizedRuntime == "error" {
        return .degraded
    }
    if shouldPresentStartupLoading(
        normalizedBridge: normalizedBridge,
        normalizedRuntime: normalizedRuntime,
        hasConfirmedStatus: hasConfirmedStatus,
        isLoading: isLoading,
        isRuntimeBusy: isRuntimeBusy,
        startupGraceActive: startupGraceActive
    ) {
        return .loading
    }
    if normalizedBridge == "degraded" || normalizedBridge == "error" {
        return .degraded
    }

    let usingRemote = activeRequesterSessions > 0
    let sharingNow = localSharePublished && localShareSlotsTotal > 0 && localShareSlotsFree < localShareSlotsTotal

    switch (usingRemote, sharingNow) {
    case (true, true):
        return .both
    case (true, false):
        return .usingRemote
    case (false, true):
        return .sharing
    default:
        return .ready
    }
}

func deriveSwarmConnectionState(
    bridgeStatus: String,
    runtimeStatus: String,
    hasActiveSwarm: Bool,
    hasConfirmedStatus: Bool,
    isLoading: Bool,
    isRuntimeBusy: Bool,
    startupGraceActive: Bool
) -> SwarmConnectionState {
    let normalizedBridge = bridgeStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedRuntime = runtimeStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalizedRuntime == "error" {
        return .attention
    }
    if shouldPresentStartupLoading(
        normalizedBridge: normalizedBridge,
        normalizedRuntime: normalizedRuntime,
        hasConfirmedStatus: hasConfirmedStatus,
        isLoading: isLoading,
        isRuntimeBusy: isRuntimeBusy,
        startupGraceActive: startupGraceActive
    ) {
        return .loading
    }
    if normalizedBridge == "degraded" || normalizedBridge == "error" {
        return .attention
    }
    if normalizedRuntime == "ready", hasActiveSwarm {
        return .connected
    }
    if normalizedRuntime == "ready" {
        return .disconnected
    }
    return .loading
}

private func shouldPresentStartupLoading(
    normalizedBridge: String,
    normalizedRuntime: String,
    hasConfirmedStatus: Bool,
    isLoading: Bool,
    isRuntimeBusy: Bool,
    startupGraceActive: Bool
) -> Bool {
    if normalizedBridge == "bootstrapping" || normalizedRuntime == "bootstrapping" {
        return true
    }
    if isRuntimeBusy {
        return true
    }
    if !hasConfirmedStatus && (isLoading || startupGraceActive) {
        return true
    }
    return false
}

func deriveLocalEligibilitySummary(
    modeAllowsShare: Bool,
    activeSwarmID: String,
    runtimeStatus: String,
    bridgeStatus: String,
    localSharePublished: Bool,
    localShareSlotsFree: Int,
    localShareSlotsTotal: Int,
    discoveredModelCount: Int,
    failedSessions: Int
) -> LocalEligibilitySummary {
    let normalizedRuntime = runtimeStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let normalizedBridge = bridgeStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    if normalizedRuntime != "ready" || normalizedBridge == "degraded" || normalizedBridge == "error" {
        return LocalEligibilitySummary(
            code: .runtimeNotReady,
            title: "Runtime not ready",
            shortLabel: "Not ready",
            detail: "This Mac cannot take requester work until the local OnlyMacs runtime is healthy again.",
            recoveryHint: "Restart the runtime or fix the bridge error first."
        )
    }

    if activeSwarmID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return LocalEligibilitySummary(
            code: .noActiveSwarm,
            title: "No active swarm",
            shortLabel: "No swarm",
            detail: "This Mac cannot become eligible until OnlyMacs has an active swarm to publish into.",
            recoveryHint: "Create or join a swarm, then run Make OnlyMacs Ready again."
        )
    }

    if !modeAllowsShare {
        return LocalEligibilitySummary(
            code: .modeDoesNotShare,
            title: "Sharing disabled",
            shortLabel: "Sharing off",
            detail: "The current app mode is not exposing This Mac as swarm capacity, so requester work will stay off this machine.",
            recoveryHint: "Switch to Share This Mac or Both if you want This Mac to be eligible."
        )
    }

    if discoveredModelCount == 0 {
        return LocalEligibilitySummary(
            code: .noLocalModels,
            title: "No local models",
            shortLabel: "No models",
            detail: "This Mac has no local models installed yet, so it cannot satisfy local-only or local-biased routing.",
            recoveryHint: "Install or publish at least one local model first."
        )
    }

    if !localSharePublished {
        return LocalEligibilitySummary(
            code: .notPublished,
            title: "Not published",
            shortLabel: "Needs publish",
            detail: "This Mac has local models, but it is not currently visible to the active swarm as schedulable capacity.",
            recoveryHint: "Run Make OnlyMacs Ready or reconnect this Mac to refresh local slot visibility."
        )
    }

    if failedSessions >= 3 {
        return LocalEligibilitySummary(
            code: .shareHealthDegraded,
            title: "Share health degraded",
            shortLabel: "Health degraded",
            detail: "Recent relay failures mean healthier Macs may be preferred until This Mac stabilizes again.",
            recoveryHint: "Open logs or export a redacted support bundle before re-publishing."
        )
    }

    if localShareSlotsTotal > 0 && localShareSlotsFree <= 0 {
        return LocalEligibilitySummary(
            code: .localSlotBusy,
            title: "Local slot busy",
            shortLabel: "Slot busy",
            detail: "This Mac is published and healthy, but its local slot is currently occupied by other work.",
            recoveryHint: "Let the current local work finish or widen the route temporarily."
        )
    }

    return LocalEligibilitySummary(
        code: .publishedAndHealthy,
        title: "Published and healthy",
        shortLabel: "Eligible",
        detail: "This Mac is connected to the active swarm, has local models, and currently has a free local slot.",
        recoveryHint: nil
    )
}

func deriveModelRuntimeDependencyPresentation(
    ollamaStatus: OllamaDependencyStatus,
    ollamaDetail: String
) -> ModelRuntimeDependencyPresentation? {
    switch ollamaStatus {
    case .missing:
        return ModelRuntimeDependencyPresentation(
            title: "Install Ollama",
            detail: ollamaDetail.isEmpty
                ? "OnlyMacs needs Ollama before this Mac can download or host local models."
                : ollamaDetail,
            labelTitle: "Install Ollama",
            systemImage: "arrow.down.circle.fill",
            style: .actionRequired,
            isActionable: true
        )
    case .installedButUnavailable:
        return ModelRuntimeDependencyPresentation(
            title: "Launch Ollama",
            detail: ollamaDetail.isEmpty
                ? "OnlyMacs found Ollama, but the local runtime is not answering yet."
                : ollamaDetail,
            labelTitle: "Launch Ollama",
            systemImage: "play.circle.fill",
            style: .actionRequired,
            isActionable: true
        )
    case .ready:
        return ModelRuntimeDependencyPresentation(
            title: "Ollama Installed",
            detail: ollamaDetail.isEmpty
                ? "Ollama is installed and answering. OnlyMacs can download and host local models on this Mac."
                : ollamaDetail,
            labelTitle: "Installed",
            systemImage: "checkmark.circle.fill",
            style: .success,
            isActionable: false
        )
    case .external:
        return nil
    }
}
