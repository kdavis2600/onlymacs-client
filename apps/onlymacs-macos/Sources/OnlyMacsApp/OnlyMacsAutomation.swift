import Foundation

enum OnlyMacsAutomationSurface: String, Codable {
    case popup
    case controlCenter = "control_center"
    case fileApproval = "file_approval"
}

enum OnlyMacsAutomationAction: String, Codable {
    case open
    case close
    case approve
    case reject
}

struct OnlyMacsAutomationCommand: Codable, Identifiable {
    let id: String
    let createdAt: Date
    let surface: OnlyMacsAutomationSurface
    let action: OnlyMacsAutomationAction
    let section: String?

    var controlCenterSection: ControlCenterSection? {
        guard let section else { return nil }
        return ControlCenterSection(rawValue: section)
    }
}

struct OnlyMacsAutomationReceipt: Codable, Identifiable {
    enum Status: String, Codable {
        case handled
        case failed
    }

    let id: String
    let handledAt: Date
    let status: Status
    let message: String?
}

enum OnlyMacsAutomationStore {
    private static let maxPendingCommandAge: TimeInterval = 120

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static func latestPendingCommand() throws -> OnlyMacsAutomationCommand? {
        try ensureAutomationDirectoryExists()
        let directoryURL = OnlyMacsStatePaths.automationDirectoryURL()
        let staleCutoff = Date().addingTimeInterval(-maxPendingCommandAge)
        let commandURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
            .filter { $0.lastPathComponent.hasPrefix("command-") && $0.pathExtension == "json" }

        let commands = try commandURLs.compactMap { url -> OnlyMacsAutomationCommand? in
            let data = try Data(contentsOf: url)
            let command = try decoder.decode(OnlyMacsAutomationCommand.self, from: data)
            guard !FileManager.default.fileExists(atPath: OnlyMacsStatePaths.automationReceiptURL(id: command.id).path) else {
                return nil
            }
            if command.createdAt < staleCutoff {
                try? saveReceipt(
                    OnlyMacsAutomationReceipt(
                        id: command.id,
                        handledAt: Date(),
                        status: .failed,
                        message: "Ignored stale automation command."
                    )
                )
                return nil
            }
            return command
        }

        return commands.max(by: { $0.createdAt < $1.createdAt })
    }

    static func saveReceipt(_ receipt: OnlyMacsAutomationReceipt) throws {
        try ensureAutomationDirectoryExists()
        let data = try encoder.encode(receipt)
        try data.write(to: OnlyMacsStatePaths.automationReceiptURL(id: receipt.id), options: .atomic)
    }

    static func encodeJSON<T: Encodable>(_ value: T) throws -> Data {
        try encoder.encode(value)
    }

    private static func ensureAutomationDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: OnlyMacsStatePaths.automationDirectoryURL(),
            withIntermediateDirectories: true
        )
    }
}
