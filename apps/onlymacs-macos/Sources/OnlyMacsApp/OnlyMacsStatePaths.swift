import Foundation

enum OnlyMacsStatePaths {
    static func homeDirectoryURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let testHome = environment["ONLYMACS_TEST_HOME"], !testHome.isEmpty {
            return URL(fileURLWithPath: testHome, isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    static func stateDirectoryURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if allowsStateDirectoryOverride(environment),
           let stateDir = environment["ONLYMACS_STATE_DIR"], !stateDir.isEmpty {
            return URL(fileURLWithPath: stateDir, isDirectory: true)
        }
        if let xdgStateHome = environment["XDG_STATE_HOME"], !xdgStateHome.isEmpty {
            return URL(fileURLWithPath: xdgStateHome, isDirectory: true)
                .appendingPathComponent("onlymacs", isDirectory: true)
        }
        return homeDirectoryURL()
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("onlymacs", isDirectory: true)
    }

    static func allowsStateDirectoryOverride(_ environment: [String: String]) -> Bool {
        if ProcessInfo.processInfo.arguments.contains("--onlymacs-automation-mode") {
            return true
        }
        let flag = environment["ONLYMACS_ALLOW_STATE_DIR_OVERRIDE"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if flag == "1" || flag == "true" || flag == "yes" {
            return true
        }
        return Bundle.main.bundleIdentifier != "com.kizzle.onlymacs"
    }

    static func fileAccessDirectoryURL() -> URL {
        stateDirectoryURL().appendingPathComponent("file-access", isDirectory: true)
    }

    static func automationDirectoryURL() -> URL {
        stateDirectoryURL().appendingPathComponent("automation", isDirectory: true)
    }

    static func requestURL(id: String) -> URL {
        fileAccessDirectoryURL().appendingPathComponent("request-\(id).json", isDirectory: false)
    }

    static func responseURL(id: String) -> URL {
        fileAccessDirectoryURL().appendingPathComponent("response-\(id).json", isDirectory: false)
    }

    static func claimURL(id: String) -> URL {
        fileAccessDirectoryURL().appendingPathComponent("claim-\(id).json", isDirectory: false)
    }

    static func manifestURL(id: String) -> URL {
        fileAccessDirectoryURL().appendingPathComponent("manifest-\(id).json", isDirectory: false)
    }

    static func contextURL(id: String) -> URL {
        fileAccessDirectoryURL().appendingPathComponent("context-\(id).txt", isDirectory: false)
    }

    static func bundleURL(id: String) -> URL {
        fileAccessDirectoryURL().appendingPathComponent("bundle-\(id).tgz", isDirectory: false)
    }

    static func bundleStagingDirectoryURL(id: String) -> URL {
        fileAccessDirectoryURL().appendingPathComponent("bundle-\(id)", isDirectory: true)
    }

    static func historyURL() -> URL {
        fileAccessDirectoryURL().appendingPathComponent("history.json", isDirectory: false)
    }

    static func automationCommandURL(id: String) -> URL {
        automationDirectoryURL().appendingPathComponent("command-\(id).json", isDirectory: false)
    }

    static func automationReceiptURL(id: String) -> URL {
        automationDirectoryURL().appendingPathComponent("receipt-\(id).json", isDirectory: false)
    }
}
