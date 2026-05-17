import Foundation
import Testing
@testable import OnlyMacsApp

@Suite(.serialized)
struct OnlyMacsFileAccessTests {
    @Test
    func buildArtifactsCreatesContextAndManifestForSelectedFiles() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        let stateURL = tempRoot.appendingPathComponent("state", isDirectory: true)

        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)

        let pipelineURL = workspaceURL.appendingPathComponent("content-pipeline.md", isDirectory: false)
        let sampleJSONURL = workspaceURL.appendingPathComponent("examples/sample.json", isDirectory: false)
        try FileManager.default.createDirectory(at: sampleJSONURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "pipeline steps go here".write(to: pipelineURL, atomically: true, encoding: .utf8)
        try "{\"term\":\"xin chao\"}".write(to: sampleJSONURL, atomically: true, encoding: .utf8)

        let previousStateDir = ProcessInfo.processInfo.environment["ONLYMACS_STATE_DIR"]
        setenv("ONLYMACS_STATE_DIR", stateURL.path, 1)
        defer {
            if let previousStateDir {
                setenv("ONLYMACS_STATE_DIR", previousStateDir, 1)
            } else {
                unsetenv("ONLYMACS_STATE_DIR")
            }
        }

        let request = OnlyMacsFileAccessRequest(
            id: "request-123",
            createdAt: Date(),
            workspaceID: workspaceURL.path,
            workspaceRoot: workspaceURL.path,
            threadID: "thread-1",
            prompt: "Generate more JSON files with my content pipeline.",
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        let artifacts = try OnlyMacsFileExportBuilder.buildArtifacts(
            for: request,
            selectedPaths: [pipelineURL.path, sampleJSONURL.path]
        )

        let contextText = try String(contentsOf: artifacts.contextURL, encoding: .utf8)
        #expect(contextText.contains("content-pipeline.md"))
        #expect(contextText.contains("sample.json"))
        #expect(contextText.contains("Request intent: grounded_generation"))
        #expect(artifacts.manifest.files.count == 2)
        #expect(FileManager.default.fileExists(atPath: artifacts.manifestURL.path))
        #expect(FileManager.default.fileExists(atPath: artifacts.bundleURL.path))
        #expect(!artifacts.bundleSHA256.isEmpty)
    }

    @Test
    func manifestUsesBridgeCompatibleSnakeCaseKeys() throws {
        let manifest = OnlyMacsFileExportManifest(
            schema: "context_capsule.v2",
            capsuleID: "capsule-123",
            id: "manifest-123",
            requestID: "request-123",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_700_000_900),
            workspaceRoot: "/tmp/workspace",
            workspaceRootLabel: "workspace",
            workspaceFingerprint: "abc12345",
            routeScope: "trusted_only",
            trustTier: .privateTrusted,
            absolutePathsIncluded: true,
            swarmName: "Friends",
            toolName: "Codex",
            promptSummary: "Review the pipeline docs.",
            requestIntent: "grounded_review",
            exportMode: .trustedReviewFull,
            outputContract: "categorized_findings",
            requiredSections: ["Findings", "Open Questions", "Referenced Files"],
            groundingRules: ["Base every material claim only on the approved files in this bundle."],
            contextRequestRules: ["Write 'None.' under Context Requests when the current bundle is sufficient."],
            permissions: OnlyMacsCapsulePermissions(
                allowContextRequests: true,
                maxContextRequestRounds: 2,
                allowSourceMutation: false,
                allowStagedMutation: false,
                allowOutputArtifacts: true
            ),
            budgets: OnlyMacsCapsuleBudgets(
                maxFileBytes: 180_000,
                maxTotalBytes: 480_000,
                maxScanBytes: 200_000,
                requiresFullFiles: true,
                allowTrimming: false
            ),
            lease: nil,
            workspace: nil,
            contextPacks: [
                OnlyMacsCapsuleContextPack(
                    id: "docs-review",
                    description: "Readable docs, READMEs, guides, and prompts for doc-grounded review tasks.",
                    scope: "public_safe",
                    source: "built_in",
                    matchedFiles: ["docs/README.md"]
                )
            ],
            files: [
                OnlyMacsFileExportManifestFile(
                    path: "/tmp/workspace/docs/README.md",
                    relativePath: "docs/README.md",
                    category: "Docs",
                    selectionReason: "Project overview and usage notes",
                    isRecommended: true,
                    reviewPriority: 94,
                    evidenceHints: ["Overview", "Usage notes"],
                    evidenceAnchors: [
                        OnlyMacsFileEvidenceAnchor(kind: "heading", lineStart: 4, lineEnd: 4, text: "Overview"),
                        OnlyMacsFileEvidenceAnchor(kind: "snippet", lineStart: 12, lineEnd: 12, text: "Usage notes")
                    ],
                    originalBytes: 1200,
                    exportedBytes: 1200,
                    status: .ready,
                    reason: nil,
                    sha256: "abc123"
                )
            ],
            blocked: [
                OnlyMacsCapsuleBlockedFile(
                    relativePath: ".env",
                    status: .blocked,
                    reason: "This looks like a secret or credential file."
                )
            ],
            warnings: [],
            approval: OnlyMacsCapsuleApprovalMetadata(
                approvalRequired: true,
                requestedAt: Date(timeIntervalSince1970: 1_700_000_000),
                approvedAt: Date(timeIntervalSince1970: 1_700_000_030),
                selectedCount: 2,
                exportableCount: 1
            ),
            totalSelectedBytes: 1200,
            totalExportBytes: 1200
        )

        let data = try OnlyMacsFileAccessStore.encodeJSON(manifest)
        let object = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let files = object["files"] as? [[String: Any]] ?? []

        #expect(object["schema"] as? String == "context_capsule.v2")
        #expect(object["capsule_id"] as? String == "capsule-123")
        #expect(object["created_at"] as? String != nil)
        #expect(object["expires_at"] as? String != nil)
        #expect(object["workspace_root"] as? String == "/tmp/workspace")
        #expect(object["workspace_root_label"] as? String == "workspace")
        #expect(object["workspace_fingerprint"] as? String == "abc12345")
        #expect(object["trust_tier"] as? String == "private_trusted")
        #expect(object["absolute_paths_included"] as? Bool == true)
        #expect(object["tool_name"] as? String == "Codex")
        #expect(object["prompt_summary"] as? String == "Review the pipeline docs.")
        #expect(object["request_intent"] as? String == "grounded_review")
        #expect(object["output_contract"] as? String == "categorized_findings")
        #expect((object["required_sections"] as? [String])?.contains("Referenced Files") == true)
        #expect(((object["permissions"] as? [String: Any])?["allow_context_requests"] as? Bool) == true)
        #expect(((object["budgets"] as? [String: Any])?["requires_full_files"] as? Bool) == true)
        #expect(((object["context_packs"] as? [[String: Any]])?.first?["id"] as? String) == "docs-review")
        #expect(((object["blocked"] as? [[String: Any]])?.first?["relative_path"] as? String) == ".env")
        #expect(((object["approval"] as? [String: Any])?["approval_required"] as? Bool) == true)
        #expect(object["total_selected_bytes"] as? Int == 1200)
        #expect(files.first?["relative_path"] as? String == "docs/README.md")
        #expect(files.first?["category"] as? String == "Docs")
        #expect(files.first?["selection_reason"] as? String == "Project overview and usage notes")
        #expect(files.first?["is_recommended"] as? Bool == true)
        #expect(files.first?["review_priority"] as? Int == 94)
        #expect((files.first?["evidence_hints"] as? [String])?.contains("Overview") == true)
        #expect(((files.first?["evidence_anchors"] as? [[String: Any]])?.first?["line_start"] as? Int) == 4)
        #expect(files.first?["exported_bytes"] as? Int == 1200)
    }

    @Test
    func reviewArtifactsUseGroundedReviewContract() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        let stateURL = tempRoot.appendingPathComponent("state", isDirectory: true)

        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)

        let masterDocURL = workspaceURL.appendingPathComponent("docs/1 - MASTER LANGUAGE INTAKE.md", isDirectory: false)
        try FileManager.default.createDirectory(at: masterDocURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try String(repeating: "Pipeline contract.\n", count: 200).write(to: masterDocURL, atomically: true, encoding: .utf8)

        let previousStateDir = ProcessInfo.processInfo.environment["ONLYMACS_STATE_DIR"]
        setenv("ONLYMACS_STATE_DIR", stateURL.path, 1)
        defer {
            if let previousStateDir {
                setenv("ONLYMACS_STATE_DIR", previousStateDir, 1)
            } else {
                unsetenv("ONLYMACS_STATE_DIR")
            }
        }

        let request = OnlyMacsFileAccessRequest(
            id: "request-review-123",
            createdAt: Date(),
            workspaceID: workspaceURL.path,
            workspaceRoot: workspaceURL.path,
            threadID: "thread-review-1",
            prompt: "Review the pipeline docs in this project and tell me what is unclear or likely to break.",
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        let artifacts = try OnlyMacsFileExportBuilder.buildArtifacts(
            for: request,
            selectedPaths: [masterDocURL.path]
        )

        let contextText = try String(contentsOf: artifacts.contextURL, encoding: .utf8)
        #expect(artifacts.manifest.requestIntent == "grounded_review")
        #expect(artifacts.manifest.outputContract == "categorized_findings")
        #expect(artifacts.manifest.requiredSections == ["Findings", "Open Questions", "Context Requests", "Referenced Files"])
        #expect(contextText.contains("Grounding rules"))
        #expect(contextText.contains("Return sections in this order: Findings, Open Questions, Context Requests, Referenced Files"))
        #expect(contextText.contains("Evidence hints:"))
        #expect(contextText.contains("Evidence anchors:"))
        #expect(artifacts.manifest.files.first?.category == "Master Docs")
        #expect(artifacts.manifest.files.first?.selectionReason == "Core pipeline contract")
        #expect(artifacts.manifest.files.first?.isRecommended == true)
        #expect((artifacts.manifest.files.first?.reviewPriority ?? 0) > 0)
        #expect((artifacts.manifest.files.first?.evidenceHints.isEmpty ?? true) == false)
        #expect((artifacts.manifest.files.first?.evidenceAnchors.isEmpty ?? true) == false)
        #expect((artifacts.manifest.files.first?.evidenceAnchors.first?.lineStart ?? 0) > 0)
    }

    @Test
    func codeReviewArtifactsUseGroundedCodeReviewContract() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        let stateURL = tempRoot.appendingPathComponent("state", isDirectory: true)

        try FileManager.default.createDirectory(at: workspaceURL.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)

        let sourceURL = workspaceURL.appendingPathComponent("src/App.tsx")
        try "export function App() { return null }\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let previousStateDir = ProcessInfo.processInfo.environment["ONLYMACS_STATE_DIR"]
        setenv("ONLYMACS_STATE_DIR", stateURL.path, 1)
        defer {
            if let previousStateDir {
                setenv("ONLYMACS_STATE_DIR", previousStateDir, 1)
            } else {
                unsetenv("ONLYMACS_STATE_DIR")
            }
        }

        let request = OnlyMacsFileAccessRequest(
            id: "request-code-review-contract",
            createdAt: Date(),
            workspaceID: workspaceURL.path,
            workspaceRoot: workspaceURL.path,
            threadID: "thread-code-review-contract",
            prompt: "Review this repo for code issues and missing tests.",
            taskKind: .review,
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        let artifacts = try OnlyMacsFileExportBuilder.buildArtifacts(
            for: request,
            selectedPaths: [sourceURL.path]
        )

        let contextText = try String(contentsOf: artifacts.contextURL, encoding: .utf8)
        #expect(artifacts.manifest.requestIntent == "grounded_code_review")
        #expect(artifacts.manifest.outputContract == "code_review_findings")
        #expect(artifacts.manifest.requiredSections == ["Findings", "Missing Tests", "Context Requests", "Referenced Files"])
        #expect(contextText.contains("Output contract: code_review_findings"))
    }

    @Test
    func docsReviewInRepoStaysGroundedReviewInsteadOfCodeReview() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        let stateURL = tempRoot.appendingPathComponent("state", isDirectory: true)

        try FileManager.default.createDirectory(at: workspaceURL.appendingPathComponent("docs", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)

        let readmeURL = workspaceURL.appendingPathComponent("README.md")
        let docsURL = workspaceURL.appendingPathComponent("docs/pipeline.md")
        try "# Overview\n".write(to: readmeURL, atomically: true, encoding: .utf8)
        try "1. Start from the glossary.\n".write(to: docsURL, atomically: true, encoding: .utf8)

        let previousStateDir = ProcessInfo.processInfo.environment["ONLYMACS_STATE_DIR"]
        setenv("ONLYMACS_STATE_DIR", stateURL.path, 1)
        defer {
            if let previousStateDir {
                setenv("ONLYMACS_STATE_DIR", previousStateDir, 1)
            } else {
                unsetenv("ONLYMACS_STATE_DIR")
            }
        }

        let request = OnlyMacsFileAccessRequest(
            id: "request-docs-review-contract",
            createdAt: Date(),
            workspaceID: workspaceURL.path,
            workspaceRoot: workspaceURL.path,
            threadID: "thread-docs-review-contract",
            prompt: "Review the readme, docs, and examples in this repo and tell me what a new contributor would misunderstand.",
            taskKind: .review,
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        let artifacts = try OnlyMacsFileExportBuilder.buildArtifacts(
            for: request,
            selectedPaths: [readmeURL.path, docsURL.path]
        )

        let contextText = try String(contentsOf: artifacts.contextURL, encoding: .utf8)
        #expect(artifacts.manifest.requestIntent == "grounded_review")
        #expect(artifacts.manifest.outputContract == "categorized_findings")
        #expect(artifacts.manifest.requiredSections == ["Findings", "Open Questions", "Context Requests", "Referenced Files"])
        #expect(contextText.contains("Return sections in this order: Findings, Open Questions, Context Requests, Referenced Files"))
    }

    @Test
    func generationArtifactsUseGroundedGenerationContract() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        let stateURL = tempRoot.appendingPathComponent("state", isDirectory: true)

        try FileManager.default.createDirectory(at: workspaceURL.appendingPathComponent("examples", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)

        let schemaURL = workspaceURL.appendingPathComponent("schema.json")
        let exampleURL = workspaceURL.appendingPathComponent("examples/lesson.json")
        try #"{"type":"object","properties":{"term":{"type":"string"}}}"#.write(to: schemaURL, atomically: true, encoding: .utf8)
        try #"{"term":"xin chao"}"#.write(to: exampleURL, atomically: true, encoding: .utf8)

        let previousStateDir = ProcessInfo.processInfo.environment["ONLYMACS_STATE_DIR"]
        setenv("ONLYMACS_STATE_DIR", stateURL.path, 1)
        defer {
            if let previousStateDir {
                setenv("ONLYMACS_STATE_DIR", previousStateDir, 1)
            } else {
                unsetenv("ONLYMACS_STATE_DIR")
            }
        }

        let request = OnlyMacsFileAccessRequest(
            id: "request-generate-contract",
            createdAt: Date(),
            workspaceID: workspaceURL.path,
            workspaceRoot: workspaceURL.path,
            threadID: "thread-generate-contract",
            prompt: "Generate 5 new json files that match this schema and examples.",
            taskKind: .generate,
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        let artifacts = try OnlyMacsFileExportBuilder.buildArtifacts(
            for: request,
            selectedPaths: [schemaURL.path, exampleURL.path]
        )

        #expect(artifacts.manifest.requestIntent == "grounded_generation")
        #expect(artifacts.manifest.outputContract == "proposed_outputs")
        #expect(artifacts.manifest.requiredSections == ["Proposed Output", "Open Questions", "Context Requests", "Referenced Files"])
    }

    @Test
    func transformArtifactsUseGroundedTransformContract() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        let stateURL = tempRoot.appendingPathComponent("state", isDirectory: true)

        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)

        let configURL = workspaceURL.appendingPathComponent("package.json")
        try #"{"name":"demo","scripts":{}}"#.write(to: configURL, atomically: true, encoding: .utf8)

        let previousStateDir = ProcessInfo.processInfo.environment["ONLYMACS_STATE_DIR"]
        setenv("ONLYMACS_STATE_DIR", stateURL.path, 1)
        defer {
            if let previousStateDir {
                setenv("ONLYMACS_STATE_DIR", previousStateDir, 1)
            } else {
                unsetenv("ONLYMACS_STATE_DIR")
            }
        }

        let request = OnlyMacsFileAccessRequest(
            id: "request-transform-contract",
            createdAt: Date(),
            workspaceID: workspaceURL.path,
            workspaceRoot: workspaceURL.path,
            threadID: "thread-transform-contract",
            prompt: "Edit package.json in this repo to add the missing build script.",
            taskKind: .transform,
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        let artifacts = try OnlyMacsFileExportBuilder.buildArtifacts(
            for: request,
            selectedPaths: [configURL.path]
        )

        #expect(artifacts.manifest.requestIntent == "grounded_transform")
        #expect(artifacts.manifest.outputContract == "proposed_changes")
        #expect(artifacts.manifest.requiredSections == ["Proposed Changes", "Open Questions", "Context Requests", "Referenced Files"])
    }

    @Test
    func codeReviewSuggestionsPreferSourceAndConfigFiles() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)

        let readmeURL = workspaceURL.appendingPathComponent("README.md")
        let packageURL = workspaceURL.appendingPathComponent("package.json")
        let sourceURL = workspaceURL.appendingPathComponent("src/App.tsx")
        let notesURL = workspaceURL.appendingPathComponent("notes.txt")
        try "# Project".write(to: readmeURL, atomically: true, encoding: .utf8)
        try #"{"name":"demo"}"#.write(to: packageURL, atomically: true, encoding: .utf8)
        try "export const App = () => null;".write(to: sourceURL, atomically: true, encoding: .utf8)
        try "misc notes".write(to: notesURL, atomically: true, encoding: .utf8)

        let request = OnlyMacsFileAccessRequest(
            id: "request-code-review-123",
            createdAt: Date(),
            workspaceID: workspaceURL.path,
            workspaceRoot: workspaceURL.path,
            threadID: "thread-code-review-1",
            prompt: "Do a code review on my project and call out the biggest issues.",
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        let suggestions = OnlyMacsFileAccessStore.suggestFiles(for: request)
        let relativePaths = suggestions.map(\.relativePath)

        #expect(relativePaths.contains("README.md"))
        #expect(relativePaths.contains("package.json"))
        #expect(relativePaths.contains("src/App.tsx"))
        #expect(!relativePaths.contains("notes.txt"))
        #expect(suggestions.first(where: { $0.relativePath == "src/App.tsx" })?.category == "Source")
    }

    @Test
    func codeReviewSuggestionsBiasTowardPromptNamedFiles() throws {
        let request = OnlyMacsFileAccessRequest(
            id: "request-auth-review",
            createdAt: Date(),
            workspaceID: "/tmp/source",
            workspaceRoot: "/tmp/source",
            threadID: "thread-auth-review",
            prompt: "review the auth code in this repo and call out the biggest risks",
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        let suggestions = [
            OnlyMacsFileSuggestion(
                path: "/tmp/source/src/api.ts",
                relativePath: "src/api.ts",
                bytes: 200,
                reason: "Primary application source",
                category: "Source",
                priority: 280,
                isRecommended: true
            ),
            OnlyMacsFileSuggestion(
                path: "/tmp/source/src/auth.ts",
                relativePath: "src/auth.ts",
                bytes: 200,
                reason: "Authentication and token handling",
                category: "Source",
                priority: 322,
                isRecommended: true
            ),
            OnlyMacsFileSuggestion(
                path: "/tmp/source/package.json",
                relativePath: "package.json",
                bytes: 200,
                reason: "App package and dependency definition",
                category: "Config",
                priority: 304,
                isRecommended: true
            )
        ]

        let preselected = OnlyMacsFileAccessStore.preselectedPaths(for: request, suggestions: suggestions)
        #expect(preselected.first == "/tmp/source/src/auth.ts")
        #expect(preselected.contains("/tmp/source/package.json"))
    }

    @Test
    func contentPipelinePreselectionBalancesDocsExamplesAndSchema() throws {
        let request = OnlyMacsFileAccessRequest(
            id: "request-content-balance",
            createdAt: Date(),
            workspaceID: "/tmp/content",
            workspaceRoot: "/tmp/content",
            threadID: "thread-content-balance",
            prompt: "review the docs and example json files in this repo and tell me where they disagree",
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        let suggestions = [
            OnlyMacsFileSuggestion(
                path: "/tmp/content/docs/pipeline.md",
                relativePath: "docs/pipeline.md",
                bytes: 5_000,
                reason: "Readable pipeline instructions",
                category: "Docs",
                priority: 296,
                isRecommended: true
            ),
            OnlyMacsFileSuggestion(
                path: "/tmp/content/docs/glossary.md",
                relativePath: "docs/glossary.md",
                bytes: 2_000,
                reason: "Shared terminology and definitions",
                category: "Glossary",
                priority: 290,
                isRecommended: true
            ),
            OnlyMacsFileSuggestion(
                path: "/tmp/content/schema/lesson.schema.json",
                relativePath: "schema/lesson.schema.json",
                bytes: 4_000,
                reason: "Schema or structure rules",
                category: "Schema",
                priority: 248,
                isRecommended: true
            ),
            OnlyMacsFileSuggestion(
                path: "/tmp/content/examples/lesson.example.json",
                relativePath: "examples/lesson.example.json",
                bytes: 3_000,
                reason: "Example content or expected output shape",
                category: "Examples",
                priority: 274,
                isRecommended: true
            ),
            OnlyMacsFileSuggestion(
                path: "/tmp/content/README.md",
                relativePath: "README.md",
                bytes: 1_000,
                reason: "Top-level pipeline overview",
                category: "Overview",
                priority: 304,
                isRecommended: true
            )
        ]

        let preselected = Set(OnlyMacsFileAccessStore.preselectedPaths(for: request, suggestions: suggestions))

        #expect(preselected.contains("/tmp/content/docs/pipeline.md"))
        #expect(preselected.contains("/tmp/content/docs/glossary.md"))
        #expect(preselected.contains("/tmp/content/schema/lesson.schema.json"))
        #expect(preselected.contains("/tmp/content/examples/lesson.example.json"))
        #expect(preselected.contains("/tmp/content/README.md"))
    }

    @Test
    func previewBlocksEnvFilesAndCredentialContent() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let envURL = workspaceURL.appendingPathComponent(".env", isDirectory: false)
        let notesURL = workspaceURL.appendingPathComponent("notes.md", isDirectory: false)
        try "OPENAI_API_KEY=sk-secret-key-value-1234567890".write(to: envURL, atomically: true, encoding: .utf8)
        try "safe markdown".write(to: notesURL, atomically: true, encoding: .utf8)

        let request = OnlyMacsFileAccessRequest(
            id: "request-456",
            createdAt: Date(),
            workspaceID: workspaceURL.path,
            workspaceRoot: workspaceURL.path,
            threadID: "thread-2",
            prompt: "Review these files in my private swarm.",
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        let preview = OnlyMacsFileExportBuilder.buildPreview(
            for: request,
            selectedPaths: [envURL.path, notesURL.path]
        )

        #expect(preview.exportableCount == 1)
        #expect(preview.blockedCount == 1)
        #expect(preview.entries.contains(where: { $0.path == envURL.path && $0.status == .blocked }))
        #expect(preview.warnings.contains(where: { $0.contains(".env") }))
    }

    @Test
    func auditHistoryAppendsRecords() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stateURL = tempRoot.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)

        let previousStateDir = ProcessInfo.processInfo.environment["ONLYMACS_STATE_DIR"]
        setenv("ONLYMACS_STATE_DIR", stateURL.path, 1)
        defer {
            if let previousStateDir {
                setenv("ONLYMACS_STATE_DIR", previousStateDir, 1)
            } else {
                unsetenv("ONLYMACS_STATE_DIR")
            }
        }

        try OnlyMacsFileAccessStore.appendAuditRecord(
            OnlyMacsFileAccessAuditRecord(
                id: "audit-1",
                decidedAt: Date(),
                status: .approved,
                workspaceRoot: "/tmp/workspace",
                swarmName: "Friends",
                promptSummary: "Generate JSON",
                selectedPaths: ["/tmp/workspace/content.md"],
                exportedPaths: ["/tmp/workspace/content.md"],
                blockedPaths: [],
                warnings: ["Trimmed content"]
            )
        )

        let historyURL = OnlyMacsStatePaths.historyURL()
        let historyData = try Data(contentsOf: historyURL)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let records = try decoder.decode([OnlyMacsFileAccessAuditRecord].self, from: historyData)
        #expect(records.count == 1)
        #expect(records.first?.id == "audit-1")
    }

    @Test
    func latestPendingRequestSkipsAnsweredRequests() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stateURL = tempRoot.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)

        let previousStateDir = ProcessInfo.processInfo.environment["ONLYMACS_STATE_DIR"]
        setenv("ONLYMACS_STATE_DIR", stateURL.path, 1)
        defer {
            if let previousStateDir {
                setenv("ONLYMACS_STATE_DIR", previousStateDir, 1)
            } else {
                unsetenv("ONLYMACS_STATE_DIR")
            }
        }

        let olderRequest = OnlyMacsFileAccessRequest(
            id: "request-old",
            createdAt: Date(timeIntervalSince1970: 1_000),
            workspaceID: "/tmp/old",
            workspaceRoot: "/tmp/old",
            threadID: "thread-old",
            prompt: "old",
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )
        let newerRequest = OnlyMacsFileAccessRequest(
            id: "request-new",
            createdAt: Date(timeIntervalSince1970: 2_000),
            workspaceID: "/tmp/new",
            workspaceRoot: "/tmp/new",
            threadID: "thread-new",
            prompt: "new",
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        try FileManager.default.createDirectory(at: OnlyMacsStatePaths.fileAccessDirectoryURL(), withIntermediateDirectories: true)
        try OnlyMacsFileAccessStore.encodeJSON(olderRequest).write(to: OnlyMacsStatePaths.requestURL(id: olderRequest.id))
        try OnlyMacsFileAccessStore.encodeJSON(newerRequest).write(to: OnlyMacsStatePaths.requestURL(id: newerRequest.id))
        try OnlyMacsFileAccessStore.saveResponse(
            OnlyMacsFileAccessResponse(
                id: newerRequest.id,
                decidedAt: Date(),
                status: .approved,
                selectedPaths: [],
                contextPath: nil,
                manifestPath: nil,
                bundlePath: nil,
                bundleSHA256: nil,
                exportMode: nil,
                warnings: [],
                message: nil
            )
        )

        let pending = try OnlyMacsFileAccessStore.latestPendingRequest()
        #expect(pending?.id == olderRequest.id)
    }

    @Test
    func reviewModeBlocksOversizedFileInsteadOfSilentlyTrimming() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let largeDocURL = workspaceURL.appendingPathComponent("MASTER-PIPELINE.md", isDirectory: false)
        let oversizedContent = String(repeating: "review-line\n", count: 80_000)
        try oversizedContent.write(to: largeDocURL, atomically: true, encoding: .utf8)

        let request = OnlyMacsFileAccessRequest(
            id: "request-review-blocked",
            createdAt: Date(),
            workspaceID: workspaceURL.path,
            workspaceRoot: workspaceURL.path,
            threadID: "thread-review",
            prompt: "Review the pipeline docs in this project and tell me what is unclear.",
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        let preview = OnlyMacsFileExportBuilder.buildPreview(for: request, selectedPaths: [largeDocURL.path])
        #expect(preview.entries.count == 1)
        #expect(preview.entries.first?.status == .blocked)
        #expect(preview.warnings.contains(where: { $0.contains("full file") || $0.contains("review-grade") }))
    }

    @Test
    func saveClaimWritesClaimArtifact() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stateURL = tempRoot.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(at: stateURL, withIntermediateDirectories: true)

        let previousStateDir = ProcessInfo.processInfo.environment["ONLYMACS_STATE_DIR"]
        setenv("ONLYMACS_STATE_DIR", stateURL.path, 1)
        defer {
            if let previousStateDir {
                setenv("ONLYMACS_STATE_DIR", previousStateDir, 1)
            } else {
                unsetenv("ONLYMACS_STATE_DIR")
            }
        }

        let claim = OnlyMacsFileAccessClaim(
            id: "request-claim",
            claimedAt: Date(),
            workspaceRoot: "/tmp/workspace"
        )

        try OnlyMacsFileAccessStore.saveClaim(claim)

        let data = try Data(contentsOf: OnlyMacsStatePaths.claimURL(id: claim.id))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(OnlyMacsFileAccessClaim.self, from: data)
        #expect(decoded.id == claim.id)
        #expect(decoded.workspaceRoot == claim.workspaceRoot)
    }

    @Test
    func contentPipelineSuggestionsPreferMasterDocsOverDeprecatedRunArtifacts() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("content-pipeline", isDirectory: true)

        try FileManager.default.createDirectory(
            at: workspaceURL.appendingPathComponent("docs/content-pipeline/content-generation", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: workspaceURL.appendingPathComponent("scripts/content-pipeline/configs/lib", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: workspaceURL.appendingPathComponent("docs/content-pipeline/deprecated/2026-04-12-pipeline-testing-reset/content-generation/learn-portuguese-lisbon/v2", isDirectory: true),
            withIntermediateDirectories: true
        )

        let files: [(String, String)] = [
            ("docs/content-pipeline/1 - MASTER LANGUAGE INTAKE.md", "intake"),
            ("docs/content-pipeline/2 - MASTER CONTENT CREATION.md", "creation"),
            ("docs/content-pipeline/3 - MASTER CONTENT QA PASS.md", "qa"),
            ("docs/content-pipeline/README.md", "overview"),
            ("docs/content-pipeline/content-generation/README.md", "generation overview"),
            ("scripts/content-pipeline/README.md", "script overview"),
            ("scripts/content-pipeline/step2_pilot_runner.js", "runner"),
            ("scripts/content-pipeline/configs/lib/build_standard_step2_config.js", "config"),
            ("scripts/content-pipeline/lib/locale_guide_schema.js", "schema"),
            ("docs/content-pipeline/deprecated/2026-04-12-pipeline-testing-reset/content-generation/learn-portuguese-lisbon/v2/run-manifest.json", "{}"),
            ("docs/content-pipeline/deprecated/2026-04-12-pipeline-testing-reset/content-generation/learn-portuguese-lisbon/v2/STEP-2 RUN NOTES.md", "old notes")
        ]

        for (relativePath, contents) in files {
            let url = workspaceURL.appendingPathComponent(relativePath, isDirectory: false)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }

        let request = OnlyMacsFileAccessRequest(
            id: "request-pipeline",
            createdAt: Date(),
            workspaceID: workspaceURL.path,
            workspaceRoot: workspaceURL.path,
            threadID: "thread-pipeline",
            prompt: "review the pipeline docs in this project and tell me what is unclear, inconsistent, or likely to break when generating content",
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "My Swarm"
        )

        let suggestions = OnlyMacsFileAccessStore.suggestFiles(for: request)
        let recommendedPaths = suggestions.filter(\.isRecommended).map(\.relativePath)
        let topPaths = Array(suggestions.prefix(6).map(\.relativePath))

        #expect(recommendedPaths.contains("docs/content-pipeline/1 - MASTER LANGUAGE INTAKE.md"))
        #expect(recommendedPaths.contains("docs/content-pipeline/2 - MASTER CONTENT CREATION.md"))
        #expect(recommendedPaths.contains("docs/content-pipeline/README.md"))
        #expect(recommendedPaths.contains("docs/content-pipeline/content-generation/README.md"))
        #expect(recommendedPaths.contains("scripts/content-pipeline/README.md"))
        #expect(topPaths.contains("docs/content-pipeline/2 - MASTER CONTENT CREATION.md"))
        #expect(topPaths.contains("docs/content-pipeline/README.md"))
        #expect(!topPaths.contains("docs/content-pipeline/deprecated/2026-04-12-pipeline-testing-reset/content-generation/learn-portuguese-lisbon/v2/run-manifest.json"))
        #expect(
            suggestions.firstIndex(where: { $0.relativePath.contains("/deprecated/") }) ?? Int.max >
            suggestions.firstIndex(where: { $0.relativePath == "docs/content-pipeline/2 - MASTER CONTENT CREATION.md" }) ?? Int.min
        )
    }

    @Test
    func contentPipelineFullSourceSetPromptsPreselectAllMasterDocsAndCoreInputs() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("pipeline-workspace", isDirectory: true)

        let files: [(String, String)] = [
            ("docs/pipeline/1 - MASTER SOURCE INTAKE.md", "source intake"),
            ("docs/pipeline/2 - MASTER GENERATION CONTRACT.md", "generation contract"),
            ("docs/pipeline/3 - MASTER QUALITY PASS.md", "quality pass"),
            ("docs/pipeline/4 - MASTER PACK ASSEMBLY.md", "pack assembly"),
            ("docs/pipeline/5 - MASTER RELEASE CHECKS.md", "release checks"),
            ("docs/pipeline/6 - MASTER FEEDBACK LOOP.md", "feedback loop"),
            ("docs/pipeline/master-intake-language.md", "language intake assumptions"),
            ("docs/pipeline/README.md", "pipeline overview"),
            ("docs/pipeline/glossary.md", "glossary"),
            ("schema/delivery.schema.json", #"{"type":"object"}"#),
            ("examples/delivery.example.json", #"{"name":"sample"}"#),
            ("scripts/pipeline/build_delivery_pack.js", "console.log('build');")
        ]

        for (relativePath, contents) in files {
            let url = workspaceURL.appendingPathComponent(relativePath, isDirectory: false)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }

        let request = OnlyMacsFileAccessRequest(
            id: "request-full-source-set",
            createdAt: Date(),
            workspaceID: workspaceURL.path,
            workspaceRoot: workspaceURL.path,
            threadID: "thread-full-source-set",
            prompt: "generate a full delivery pack from the language intake, master pipeline docs, glossary, schema, and example outputs",
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        let suggestions = OnlyMacsFileAccessStore.suggestFiles(for: request)
        let preselected = Set(OnlyMacsFileAccessStore.preselectedPaths(for: request, suggestions: suggestions))
        let preselectedRelativePaths = Set(
            suggestions
                .filter { preselected.contains($0.path) }
                .map(\.relativePath)
        )
        let masterDocPaths = [
            "docs/pipeline/1 - MASTER SOURCE INTAKE.md",
            "docs/pipeline/2 - MASTER GENERATION CONTRACT.md",
            "docs/pipeline/3 - MASTER QUALITY PASS.md",
            "docs/pipeline/4 - MASTER PACK ASSEMBLY.md",
            "docs/pipeline/5 - MASTER RELEASE CHECKS.md",
            "docs/pipeline/6 - MASTER FEEDBACK LOOP.md"
        ]

        for relativePath in masterDocPaths {
            #expect(preselectedRelativePaths.contains(relativePath))
        }
        #expect(preselectedRelativePaths.contains("docs/pipeline/master-intake-language.md"))
        #expect(preselectedRelativePaths.contains("docs/pipeline/README.md"))
        #expect(preselectedRelativePaths.contains("schema/delivery.schema.json"))
        #expect(preselectedRelativePaths.contains("examples/delivery.example.json"))
        #expect(preselectedRelativePaths.count >= 10)
    }
}
