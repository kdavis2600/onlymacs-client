import Foundation

struct InstallerPackageSelections: Equatable {
    let joinPublicSwarm: Bool
    let shareThisMac: Bool
    let runOnStartup: Bool
    let installStarterModels: Bool
    let installCodex: Bool
    let installClaude: Bool
    let presentedByInstaller: Bool

    static func loadCurrent() -> InstallerPackageSelections? {
        let rootURL = selectionsRootURL
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: rootURL.path) else { return nil }

        let seedPresented = fileManager.fileExists(atPath: rootURL.appendingPathComponent("seed-present").path)
        guard seedPresented else { return nil }

        return InstallerPackageSelections(
            joinPublicSwarm: fileManager.fileExists(atPath: rootURL.appendingPathComponent("join-public").path),
            shareThisMac: fileManager.fileExists(atPath: rootURL.appendingPathComponent("share-this-mac").path),
            runOnStartup: fileManager.fileExists(atPath: rootURL.appendingPathComponent("run-on-startup").path),
            installStarterModels: fileManager.fileExists(atPath: rootURL.appendingPathComponent("install-starter-models").path),
            installCodex: fileManager.fileExists(atPath: rootURL.appendingPathComponent("install-codex").path),
            installClaude: fileManager.fileExists(atPath: rootURL.appendingPathComponent("install-claude").path),
            presentedByInstaller: seedPresented
        )
    }

    var requestedMode: AppMode {
        shareThisMac ? .both : .use
    }

    var requestedLauncherTargets: Set<LauncherInstallTarget> {
        var targets = Set<LauncherInstallTarget>()
        if installCodex {
            targets.insert(.codex)
        }
        if installClaude {
            targets.insert(.claude)
        }
        return targets
    }

    var canAutoProvisionWithoutExtraInput: Bool {
        joinPublicSwarm
    }

    var signature: String {
        [
            joinPublicSwarm ? "public" : "no-public",
            shareThisMac ? "share" : "use-only",
            runOnStartup ? "startup" : "manual-launch",
            installStarterModels ? "starter-models" : "no-models",
            installCodex ? "codex" : "no-codex",
            installClaude ? "claude" : "no-claude",
        ].joined(separator: "|")
    }

    private static var selectionsRootURL: URL {
        if let override = ProcessInfo.processInfo.environment["ONLYMACS_TEST_INSTALLER_SELECTIONS_ROOT"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: "/Library/Application Support/OnlyMacs/InstallerSelections", isDirectory: true)
    }
}

func shouldAutoBootstrapOllamaDependency(
    launchRequestedInstallerSelectionApply: Bool,
    installerPackageSelections: InstallerPackageSelections?
) -> Bool {
    guard launchRequestedInstallerSelectionApply else { return false }
    guard let installerPackageSelections else { return false }
    return installerPackageSelections.canAutoProvisionWithoutExtraInput
        && installerPackageSelections.shareThisMac
        && installerPackageSelections.installStarterModels
}
