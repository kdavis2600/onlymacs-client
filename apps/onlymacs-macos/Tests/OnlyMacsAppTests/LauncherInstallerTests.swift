import Foundation
import Testing
@testable import OnlyMacsApp

struct LauncherInstallerTests {
    private static let environmentLock = NSLock()
    private static let integrationRootPath = resolvedIntegrationRootPath()

    @Test
    func applyPathFixWritesSnippetOnce() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let profileURL = tempRoot.appendingPathComponent(".zshrc", isDirectory: false)

        try withOverrides(home: tempRoot.path, shell: "/bin/zsh", profile: profileURL.path) {
            let initial = LauncherInstaller.status()
            #expect(initial.profileConfigured == false)

            let repaired = try LauncherInstaller.applyPathFix()
            let profileText = try String(contentsOf: profileURL, encoding: .utf8)

            #expect(repaired.profileConfigured)
            #expect(profileText.contains("# Added by OnlyMacs"))
            #expect(profileText.contains("export PATH=\"$HOME/.local/bin:$PATH\""))

            let repairedAgain = try LauncherInstaller.applyPathFix()
            let secondProfileText = try String(contentsOf: profileURL, encoding: .utf8)

            #expect(repairedAgain.profileConfigured)
            #expect(secondProfileText.components(separatedBy: "# Added by OnlyMacs").count == 2)
        }
    }

    @Test
    func applyPathFixUsesFishSnippetForFishShell() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let profileURL = tempRoot.appendingPathComponent(".config/fish/config.fish", isDirectory: false)

        try withOverrides(home: tempRoot.path, shell: "/opt/homebrew/bin/fish", profile: profileURL.path) {
            let repaired = try LauncherInstaller.applyPathFix()
            let profileText = try String(contentsOf: profileURL, encoding: .utf8)

            #expect(repaired.profileConfigured)
            #expect(profileText.contains("set -gx PATH \"$HOME/.local/bin\" $PATH"))
        }
    }

    @Test
    func installLaunchersAlsoInstallsGlobalCodexAndClaudeSkillSurfaces() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let profileURL = tempRoot.appendingPathComponent(".zshrc", isDirectory: false)
        let legacyCodexSkill = tempRoot.appendingPathComponent(".codex/skills/onlymacs", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyCodexSkill, withIntermediateDirectories: true)
        try "stale".write(to: legacyCodexSkill.appendingPathComponent("SKILL.md", isDirectory: false), atomically: true, encoding: .utf8)

        try withOverrides(home: tempRoot.path, shell: "/bin/zsh", profile: profileURL.path) {
            let status = try LauncherInstaller.installLaunchers(targets: [.core, .codex, .claude])

            #expect(status.installed)
            #expect(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(".agents/skills/onlymacs/SKILL.md").path))
            #expect(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(".agents/skills/onlymacs/agents/openai.yaml").path))
            #expect(!FileManager.default.fileExists(atPath: legacyCodexSkill.path))
            #expect(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(".local/bin/onlymacs-shell").path))
            #expect(!FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(".local/bin/onlymacs-codex").path))
            #expect(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(".claude/commands/onlymacs.md").path))
            #expect(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent(".claude/skills/onlymacs/SKILL.md").path))
        }
    }

    @Test
    func installedLauncherWithConfiguredProfileDoesNotNeedPathSetup() {
        let status = LauncherInstallStatus(
            installed: true,
            commandOnPath: false,
            profileConfigured: true,
            shimDirectoryURL: URL(fileURLWithPath: "/Users/example/.local/bin", isDirectory: true),
            entrypointURL: URL(fileURLWithPath: "/Users/example/.local/bin/onlymacs", isDirectory: false),
            shellProfilePath: "/Users/example/.zshrc"
        )

        #expect(!status.pathNeedsSetup)
        #expect(status.detail.contains("already includes"))
        #expect(!status.detail.localizedCaseInsensitiveContains("reopen the IDE"))
    }

    @Test
    func installedLauncherWithoutProfileConfigurationNeedsPathSetup() {
        let status = LauncherInstallStatus(
            installed: true,
            commandOnPath: false,
            profileConfigured: false,
            shimDirectoryURL: URL(fileURLWithPath: "/Users/example/.local/bin", isDirectory: true),
            entrypointURL: URL(fileURLWithPath: "/Users/example/.local/bin/onlymacs", isDirectory: false),
            shellProfilePath: "/Users/example/.zshrc"
        )

        #expect(status.pathNeedsSetup)
        #expect(status.detail.contains("not in PATH yet"))
    }

    @Test
    func staleLauncherShimRequiresRefresh() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let profileURL = tempRoot.appendingPathComponent(".zshrc", isDirectory: false)
        let shimDirectory = tempRoot.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: shimDirectory, withIntermediateDirectories: true)
        let staleShim = shimDirectory.appendingPathComponent("onlymacs", isDirectory: false)
        try """
        #!/usr/bin/env bash
        exec /usr/bin/env bash '/tmp/old/OnlyMacs.app/Contents/Resources/Integrations/onlymacs/onlymacs.sh' "$@"
        """.write(to: staleShim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staleShim.path)

        try withOverrides(home: tempRoot.path, shell: "/bin/zsh", profile: profileURL.path) {
            let status = LauncherInstaller.status()

            #expect(!status.installed)
            #expect(status.actionTitle == "Install OnlyMacs CLI")
        }
    }

    @Test
    func staleAssistantLauncherShimRequiresRefresh() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let profileURL = tempRoot.appendingPathComponent(".zshrc", isDirectory: false)
        let shimDirectory = tempRoot.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: shimDirectory, withIntermediateDirectories: true)

        let currentCoreShim = shimDirectory.appendingPathComponent("onlymacs", isDirectory: false)
        try """
        #!/usr/bin/env bash
        exec /usr/bin/env bash '\(Self.integrationRootPath)/onlymacs/onlymacs.sh' "$@"
        """.write(to: currentCoreShim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: currentCoreShim.path)

        let staleCodexShim = shimDirectory.appendingPathComponent("onlymacs-shell", isDirectory: false)
        try """
        #!/usr/bin/env bash
        exec /usr/bin/env bash '/tmp/old/OnlyMacs.app/Contents/Resources/Integrations/codex/onlymacs-shell.sh' "$@"
        """.write(to: staleCodexShim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staleCodexShim.path)

        try withOverrides(home: tempRoot.path, shell: "/bin/zsh", profile: profileURL.path) {
            let status = LauncherInstaller.status()

            #expect(!status.installed)
            #expect(status.actionTitle == "Install OnlyMacs CLI")
        }
    }

    @Test
    func deprecatedCodexLauncherShimRequiresRefresh() throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let profileURL = tempRoot.appendingPathComponent(".zshrc", isDirectory: false)
        let shimDirectory = tempRoot.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: shimDirectory, withIntermediateDirectories: true)

        let currentCoreShim = shimDirectory.appendingPathComponent("onlymacs", isDirectory: false)
        try """
        #!/usr/bin/env bash
        exec /usr/bin/env bash '\(Self.integrationRootPath)/onlymacs/onlymacs.sh' "$@"
        """.write(to: currentCoreShim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: currentCoreShim.path)

        let deprecatedCodexShim = shimDirectory.appendingPathComponent("onlymacs-codex", isDirectory: false)
        try """
        #!/usr/bin/env bash
        exec /usr/bin/env bash '\(Self.integrationRootPath)/codex/onlymacs-codex.sh' "$@"
        """.write(to: deprecatedCodexShim, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deprecatedCodexShim.path)

        try withOverrides(home: tempRoot.path, shell: "/bin/zsh", profile: profileURL.path) {
            let status = LauncherInstaller.status()

            #expect(!status.installed)
            #expect(status.actionTitle == "Install OnlyMacs CLI")
        }
    }

    private func withOverrides(home: String, shell: String, profile: String, body: () throws -> Void) throws {
        Self.environmentLock.lock()
        defer { Self.environmentLock.unlock() }

        let previousHome = ProcessInfo.processInfo.environment["ONLYMACS_TEST_HOME"]
        let previousShell = ProcessInfo.processInfo.environment["ONLYMACS_TEST_SHELL"]
        let previousProfile = ProcessInfo.processInfo.environment["ONLYMACS_TEST_SHELL_PROFILE"]
        let previousIntegrationRoot = ProcessInfo.processInfo.environment["ONLYMACS_TEST_INTEGRATION_ROOT"]

        setenv("ONLYMACS_TEST_HOME", home, 1)
        setenv("ONLYMACS_TEST_SHELL", shell, 1)
        setenv("ONLYMACS_TEST_SHELL_PROFILE", profile, 1)
        setenv("ONLYMACS_TEST_INTEGRATION_ROOT", Self.integrationRootPath, 1)

        defer {
            restore("ONLYMACS_TEST_HOME", previousHome)
            restore("ONLYMACS_TEST_SHELL", previousShell)
            restore("ONLYMACS_TEST_SHELL_PROFILE", previousProfile)
            restore("ONLYMACS_TEST_INTEGRATION_ROOT", previousIntegrationRoot)
        }

        try body()
    }

    private func restore(_ key: String, _ previousValue: String?) {
        if let previousValue {
            setenv(key, previousValue, 1)
        } else {
            unsetenv(key)
        }
    }

    private static func resolvedIntegrationRootPath(filePath: String = #filePath) -> String {
        var cursor = URL(fileURLWithPath: filePath, isDirectory: false).deletingLastPathComponent()
        for _ in 0..<4 {
            cursor.deleteLastPathComponent()
        }
        return cursor.appendingPathComponent("integrations", isDirectory: true).path
    }
}
