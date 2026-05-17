import Foundation
import Darwin

enum LaunchAtLoginManager {
    private static let label = "com.kizzle.onlymacs.launch-at-login"

    static var launchAgentURL: URL {
        let base = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist", isDirectory: false)
    }

    static func isEnabled() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try installLaunchAgent()
        } else {
            removeLaunchAgent()
        }
    }

    private static func installLaunchAgent() throws {
        let fileManager = FileManager.default
        let parentURL = launchAgentURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)

        let plist = launchAgentPlist(appBundlePath: Bundle.main.bundlePath)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: launchAgentURL, options: .atomic)
        syncLaunchctl(enabled: true)
    }

    private static func removeLaunchAgent() {
        syncLaunchctl(enabled: false)
        try? FileManager.default.removeItem(at: launchAgentURL)
    }

    private static func launchAgentPlist(appBundlePath: String) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [
                "/usr/bin/open",
                "-a",
                appBundlePath,
            ],
            "RunAtLoad": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": [
                "Aqua",
            ],
        ]
    }

    private static func syncLaunchctl(enabled: Bool) {
        let domain = "gui/\(getuid())"
        let path = launchAgentURL.path

        if enabled {
            _ = runLaunchctl(arguments: ["bootstrap", domain, path])
        } else {
            _ = runLaunchctl(arguments: ["bootout", domain, path])
        }
    }

    @discardableResult
    private static func runLaunchctl(arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
