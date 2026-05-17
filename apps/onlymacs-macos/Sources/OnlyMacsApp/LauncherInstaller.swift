import AppKit
import Foundation
import Darwin

enum LauncherInstallTarget: String, CaseIterable, Hashable {
    case core
    case codex
    case claude

    var title: String {
        switch self {
        case .core:
            return "OnlyMacs CLI"
        case .codex:
            return "Codex"
        case .claude:
            return "Claude Code"
        }
    }
}

struct LauncherInstallStatus: Equatable {
    let installed: Bool
    let commandOnPath: Bool
    let profileConfigured: Bool
    let shimDirectoryURL: URL
    let entrypointURL: URL
    let shellProfilePath: String

    var detail: String {
        if installed && commandOnPath {
            return "The branded OnlyMacs launchers are installed at \(shimDirectoryURL.path) and should work in a new terminal or reopened IDE session."
        }
        if installed && profileConfigured {
            return "The launchers are installed at \(shimDirectoryURL.path), and \(shellProfilePath) already includes that directory. If one already-open terminal cannot see `onlymacs`, open a fresh terminal or use the full launcher path below."
        }
        if installed {
            return "The launchers are installed at \(shimDirectoryURL.path), but that directory is not in PATH yet. OnlyMacs can repair \(shellProfilePath) for you, or you can add it manually."
        }
        return "Install the OnlyMacs CLI at \(shimDirectoryURL.path)."
    }

    var actionTitle: String {
        installed ? "Refresh OnlyMacs CLI" : "Install OnlyMacs CLI"
    }

    var pathFixSnippet: String {
        if shellProfilePath.hasSuffix("/config.fish") {
            return "set -gx PATH \"$HOME/.local/bin\" $PATH"
        }
        return "export PATH=\"$HOME/.local/bin:$PATH\""
    }

    var needsPathFix: Bool {
        installed && !commandOnPath && !profileConfigured
    }

    var pathNeedsSetup: Bool {
        installed && !commandOnPath && !profileConfigured
    }
}

enum LauncherInstaller {
    static var shimDirectoryURL: URL {
        homeDirectoryURL.appendingPathComponent(".local/bin", isDirectory: true)
    }

    static var claudeCommandsDirectoryURL: URL {
        homeDirectoryURL.appendingPathComponent(".claude/commands", isDirectory: true)
    }

    static var claudeSkillsDirectoryURL: URL {
        homeDirectoryURL.appendingPathComponent(".claude/skills", isDirectory: true)
    }

    static var agentsSkillsDirectoryURL: URL {
        homeDirectoryURL.appendingPathComponent(".agents/skills", isDirectory: true)
    }

    static var legacyCodexSkillsDirectoryURL: URL {
        homeDirectoryURL.appendingPathComponent(".codex/skills", isDirectory: true)
    }

    static func status() -> LauncherInstallStatus {
        let shellProfilePath = preferredShellProfilePath()
        let entrypointURL = shimDirectoryURL.appendingPathComponent("onlymacs", isDirectory: false)
        let installed = launcherInstallationIsCurrent()
        return LauncherInstallStatus(
            installed: installed,
            commandOnPath: commandExists("onlymacs"),
            profileConfigured: shellProfileFileContainsPathFix(shellProfilePath),
            shimDirectoryURL: shimDirectoryURL,
            entrypointURL: entrypointURL,
            shellProfilePath: shellProfilePath
        )
    }

    @discardableResult
    static func installLaunchers(targets: Set<LauncherInstallTarget> = Set(LauncherInstallTarget.allCases)) throws -> LauncherInstallStatus {
        let fileManager = FileManager.default
        let integrationRoot = try resolveIntegrationRoot()
        try fileManager.createDirectory(at: shimDirectoryURL, withIntermediateDirectories: true)

        var wrappers = [
            "onlymacs": "onlymacs/onlymacs.sh",
        ]
        if targets.contains(.codex) {
            wrappers["onlymacs-shell"] = "codex/onlymacs-shell.sh"
        }
        if targets.contains(.claude) {
            wrappers["onlymacs-claude"] = "claude/onlymacs-claude.sh"
        }

        for (name, relativePath) in wrappers {
            let wrapperURL = integrationRoot.appendingPathComponent(relativePath, isDirectory: false)
            guard fileManager.fileExists(atPath: wrapperURL.path) else {
                throw LauncherInstallerError.missingWrapper(wrapperURL.path)
            }
            let shimURL = shimDirectoryURL.appendingPathComponent(name, isDirectory: false)
            let script = """
            #!/usr/bin/env bash
            set -euo pipefail
            exec /usr/bin/env bash \(shellQuote(wrapperURL.path)) "$@"
            """
            try script.write(to: shimURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shimURL.path)
        }
        try removeDeprecatedLauncherShims(["onlymacs-codex"])

        try installGlobalAgentSurfaces(targets: targets, integrationRoot: integrationRoot)

        return status()
    }

    @discardableResult
    static func applyPathFix() throws -> LauncherInstallStatus {
        let profilePath = preferredShellProfilePath()
        let profileURL = URL(fileURLWithPath: profilePath, isDirectory: false)
        let fileManager = FileManager.default
        let parentURL = profileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let existing = (try? String(contentsOf: profileURL, encoding: .utf8)) ?? ""
        if shellProfileTextContainsPathFix(existing) {
            return status()
        }

        let snippet = status().pathFixSnippet
        var updated = existing
        if !updated.isEmpty, !updated.hasSuffix("\n") {
            updated.append("\n")
        }
        if !updated.isEmpty {
            updated.append("\n")
        }
        updated.append("# Added by OnlyMacs\n")
        updated.append(snippet)
        updated.append("\n")

        try updated.write(to: profileURL, atomically: true, encoding: .utf8)
        return status()
    }

    private static func resolveIntegrationRoot() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["ONLYMACS_TEST_INTEGRATION_ROOT"],
           !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Integrations", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.path) {
            return bundled
        }

        if let executableURL = Bundle.main.executableURL {
            var cursor = executableURL.deletingLastPathComponent()
            for _ in 0..<10 {
                let candidate = cursor.appendingPathComponent("integrations", isDirectory: true)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
                let next = cursor.deletingLastPathComponent()
                if next.path == cursor.path {
                    break
                }
                cursor = next
            }
        }

        throw LauncherInstallerError.integrationRootNotFound
    }

    private static func launcherInstallationIsCurrent() -> Bool {
        guard launcherShimIsCurrent(name: "onlymacs", relativePath: "onlymacs/onlymacs.sh") else {
            return false
        }

        let optionalShims = [
            ("onlymacs-shell", "codex/onlymacs-shell.sh"),
            ("onlymacs-claude", "claude/onlymacs-claude.sh"),
        ]
        for (name, relativePath) in optionalShims {
            let shimURL = shimDirectoryURL.appendingPathComponent(name, isDirectory: false)
            if FileManager.default.fileExists(atPath: shimURL.path),
               !launcherShimIsCurrent(name: name, relativePath: relativePath) {
                return false
            }
        }
        if deprecatedLauncherShimExists("onlymacs-codex") {
            return false
        }
        return true
    }

    private static func launcherShimIsCurrent(name: String, relativePath: String) -> Bool {
        let shimURL = shimDirectoryURL.appendingPathComponent(name, isDirectory: false)
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: shimURL.path) else { return false }
        guard let integrationRoot = try? resolveIntegrationRoot() else { return true }
        let expectedWrapperPath = integrationRoot.appendingPathComponent(relativePath, isDirectory: false).path
        guard let script = try? String(contentsOf: shimURL, encoding: .utf8) else { return false }
        return script.contains(expectedWrapperPath)
    }

    private static func deprecatedLauncherShimExists(_ name: String) -> Bool {
        let shimURL = shimDirectoryURL.appendingPathComponent(name, isDirectory: false)
        return FileManager.default.fileExists(atPath: shimURL.path)
    }

    private static func removeDeprecatedLauncherShims(_ names: [String]) throws {
        let fileManager = FileManager.default
        for name in names {
            let shimURL = shimDirectoryURL.appendingPathComponent(name, isDirectory: false)
            if fileManager.fileExists(atPath: shimURL.path) {
                try fileManager.removeItem(at: shimURL)
            }
        }
    }

    private static func installGlobalAgentSurfaces(targets: Set<LauncherInstallTarget>, integrationRoot: URL) throws {
        let fileManager = FileManager.default

        if targets.contains(.codex) {
            let source = integrationRoot.appendingPathComponent("codex/skills/onlymacs", isDirectory: true)
            if fileManager.fileExists(atPath: source.path) {
                try copyDirectoryReplacingExisting(from: source, to: agentsSkillsDirectoryURL.appendingPathComponent("onlymacs", isDirectory: true))
            }
            try removeLegacyCodexSkill()
        }

        if targets.contains(.claude) {
            let commandSource = integrationRoot.appendingPathComponent("claude/commands/onlymacs.md", isDirectory: false)
            let skillSource = integrationRoot.appendingPathComponent("claude/skills/onlymacs.md", isDirectory: false)
            if fileManager.fileExists(atPath: commandSource.path) {
                try copyFileReplacingExisting(from: commandSource, to: claudeCommandsDirectoryURL.appendingPathComponent("onlymacs.md", isDirectory: false))
            }
            if fileManager.fileExists(atPath: skillSource.path) {
                try copyFileReplacingExisting(from: skillSource, to: claudeSkillsDirectoryURL.appendingPathComponent("onlymacs/SKILL.md", isDirectory: false))
            }
        }
    }

    private static func copyDirectoryReplacingExisting(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func copyFileReplacingExisting(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private static func removeLegacyCodexSkill() throws {
        let legacySkillURL = legacyCodexSkillsDirectoryURL.appendingPathComponent("onlymacs", isDirectory: true)
        if FileManager.default.fileExists(atPath: legacySkillURL.path) {
            try FileManager.default.removeItem(at: legacySkillURL)
        }
    }

    private static func commandExists(_ command: String) -> Bool {
        let fileManager = FileManager.default
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for entry in pathValue.split(separator: ":").map(String.init) where !entry.isEmpty {
            let candidate = URL(fileURLWithPath: entry, isDirectory: true)
                .appendingPathComponent(command, isDirectory: false)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return true
            }
        }
        return false
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static var homeDirectoryURL: URL {
        if let override = ProcessInfo.processInfo.environment["ONLYMACS_TEST_HOME"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private static func preferredShellProfilePath() -> String {
        if let override = ProcessInfo.processInfo.environment["ONLYMACS_TEST_SHELL_PROFILE"],
           !override.isEmpty {
            return override
        }

        let shell = resolvedShellPath()
        let home = homeDirectoryURL.path
        if shell.hasSuffix("/zsh") {
            return "\(home)/.zshrc"
        }
        if shell.hasSuffix("/bash") {
            return "\(home)/.bash_profile"
        }
        if shell.hasSuffix("/fish") {
            return "\(home)/.config/fish/config.fish"
        }
        return "\(home)/.zshrc"
    }

    private static func resolvedShellPath() -> String {
        if let override = ProcessInfo.processInfo.environment["ONLYMACS_TEST_SHELL"],
           !override.isEmpty {
            return override
        }
        if let shell = ProcessInfo.processInfo.environment["SHELL"], !shell.isEmpty {
            return shell
        }
        if let passwd = getpwuid(getuid()), let shell = passwd.pointee.pw_shell {
            return String(cString: shell)
        }
        return "/bin/zsh"
    }

    private static func shellProfileFileContainsPathFix(_ path: String) -> Bool {
        let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return shellProfileTextContainsPathFix(contents)
    }

    private static func shellProfileTextContainsPathFix(_ contents: String) -> Bool {
        contents.contains(".local/bin")
    }
}

enum LauncherInstallerError: LocalizedError {
    case integrationRootNotFound
    case missingWrapper(String)

    var errorDescription: String? {
        switch self {
        case .integrationRootNotFound:
            return "OnlyMacs could not find the bundled integration scripts."
        case let .missingWrapper(path):
            return "OnlyMacs expected an integration wrapper at \(path), but it was missing."
        }
    }
}
