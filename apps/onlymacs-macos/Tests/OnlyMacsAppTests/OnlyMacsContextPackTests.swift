import Foundation
import Testing
@testable import OnlyMacsApp

@Suite(.serialized)
struct OnlyMacsContextPackTests {
    @Test
    func ignoresInvalidBroadPublicPackConfig() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let configDir = tempRoot.appendingPathComponent(".onlymacs", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let yaml = """
        schema: v1
        packs:
          - id: public-bad
            description: Too broad
            scope: public_safe
            include:
              - "**/*"
        """
        try yaml.write(to: configDir.appendingPathComponent("context-packs.yml"), atomically: true, encoding: .utf8)

        let profile = OnlyMacsPromptProfile(prompt: "review the docs in this project")
        let catalog = OnlyMacsContextPackStore.loadCatalog(workspaceRoot: tempRoot.path, promptProfile: profile)

        #expect(catalog.packs.contains(where: { $0.id == "docs-review" }))
        #expect(!catalog.packs.contains(where: { $0.id == "public-bad" }))
        #expect(catalog.warnings.contains(where: { $0.contains("public-bad") }))
    }

    @Test
    func customContextPackCanSurfaceNonDefaultInterestingFiles() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        let configDir = workspaceURL.appendingPathComponent(".onlymacs", isDirectory: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceURL.appendingPathComponent("notes", isDirectory: true), withIntermediateDirectories: true)

        let yaml = """
        schema: v1
        packs:
          - id: docs-review
            description: Extra docs
            scope: public_safe
            include:
              - "notes/**/*.adoc"
        """
        try yaml.write(to: configDir.appendingPathComponent("context-packs.yml"), atomically: true, encoding: .utf8)
        try "Architecture notes".write(
            to: workspaceURL.appendingPathComponent("notes/architecture.adoc"),
            atomically: true,
            encoding: .utf8
        )

        let request = OnlyMacsFileAccessRequest(
            id: "request-pack-123",
            createdAt: Date(),
            workspaceID: workspaceURL.path,
            workspaceRoot: workspaceURL.path,
            threadID: "thread-pack-1",
            prompt: "review the docs in this project",
            routeScope: "trusted_only",
            toolName: "codex",
            wrapperName: "onlymacs",
            swarmName: "Friends"
        )

        let suggestions = OnlyMacsFileAccessStore.suggestFiles(for: request)
        #expect(suggestions.contains(where: { $0.relativePath == "notes/architecture.adoc" }))
    }

    @Test
    func selectedManifestEntriesFollowPromptSuggestedPacks() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspaceURL = tempRoot.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL.appendingPathComponent("docs", isDirectory: true), withIntermediateDirectories: true)
        try "Pipeline overview".write(
            to: workspaceURL.appendingPathComponent("docs/README.md"),
            atomically: true,
            encoding: .utf8
        )

        let profile = OnlyMacsPromptProfile(prompt: "review the pipeline docs in this project")
        let catalog = OnlyMacsContextPackStore.loadCatalog(workspaceRoot: workspaceURL.path, promptProfile: profile)
        let manifestEntries = catalog.selectedManifestEntries(selectedRelativePaths: ["docs/README.md"])

        #expect(manifestEntries.contains(where: { $0.id == "content-pipeline" || $0.id == "docs-review" }))
        #expect(manifestEntries.allSatisfy { !$0.matchedFiles.isEmpty })
    }
}
