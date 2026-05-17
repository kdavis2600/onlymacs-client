import Foundation

public enum CoordinatorConnectionMode: String, CaseIterable, Codable, Sendable {
    case embeddedLocal
    case hostedRemote

    public static var userSelectableCases: [CoordinatorConnectionMode] {
        [.hostedRemote]
    }

    public var title: String {
        switch self {
        case .embeddedLocal:
            return "Internal"
        case .hostedRemote:
            return "Hosted Remote"
        }
    }

    public var detail: String {
        switch self {
        case .embeddedLocal:
            return "Reserved for internal builds."
        case .hostedRemote:
            return "Point OnlyMacs at a shared coordinator URL."
        }
    }
}

public struct CoordinatorConnectionSettings: Codable, Equatable, Sendable {
    public static let embeddedCoordinatorURL = "http://127.0.0.1:4319"
    public static let defaultHostedCoordinatorURL = "https://onlymacs.ai"
    public static let localBridgeURL = "http://127.0.0.1:4318"

    public var mode: CoordinatorConnectionMode
    public var remoteCoordinatorURL: String

    public init(mode: CoordinatorConnectionMode = .hostedRemote, remoteCoordinatorURL: String = Self.defaultHostedCoordinatorURL) {
        self.mode = mode
        self.remoteCoordinatorURL = remoteCoordinatorURL
    }

    public var usesEmbeddedLocalDefault: Bool {
        mode == .embeddedLocal && normalizedRemoteCoordinatorURL == nil
    }

    public var launchesEmbeddedCoordinator: Bool {
        mode == .embeddedLocal
    }

    public var validationError: String? {
        guard mode == .hostedRemote else { return nil }
        guard normalizedRemoteCoordinatorURL != nil else {
            return "Enter a valid hosted coordinator URL."
        }
        return nil
    }

    public var effectiveCoordinatorURL: String {
        switch mode {
        case .embeddedLocal:
            return Self.embeddedCoordinatorURL
        case .hostedRemote:
            return normalizedRemoteCoordinatorURL ?? Self.defaultHostedCoordinatorURL
        }
    }

    public var normalizedRemoteCoordinatorURL: String? {
        let trimmed = remoteCoordinatorURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var components = URLComponents(string: trimmed) else { return nil }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard components.host?.isEmpty == false else { return nil }
        components.path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.query = nil
        components.fragment = nil
        guard var normalized = components.url?.absoluteString else { return nil }
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }
}
