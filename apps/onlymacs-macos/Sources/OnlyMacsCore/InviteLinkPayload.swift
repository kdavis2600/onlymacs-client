import Foundation

public struct InviteLinkPayload: Equatable, Sendable {
    public let inviteToken: String
    public let coordinatorURL: String?

    public init?(inviteToken: String, coordinatorURL: String?) {
        let trimmedToken = inviteToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedToken = Self.extractInviteToken(from: trimmedToken),
              normalizedToken == trimmedToken else {
            return nil
        }

        self.inviteToken = normalizedToken
        self.coordinatorURL = CoordinatorConnectionSettings(
            mode: .hostedRemote,
            remoteCoordinatorURL: coordinatorURL ?? ""
        ).normalizedRemoteCoordinatorURL
    }

    public var appURL: URL? {
        var components = URLComponents()
        components.scheme = "onlymacs"
        components.host = "join"
        var queryItems = [URLQueryItem(name: "invite_token", value: inviteToken)]
        if let coordinatorURL {
            queryItems.append(URLQueryItem(name: "coordinator_url", value: coordinatorURL))
        }
        components.queryItems = queryItems
        return components.url
    }

    public static func parse(_ raw: String) -> InviteLinkPayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: trimmed),
           let inviteToken = components.queryItems?.first(where: { $0.name == "invite_token" })?.value {
            let coordinatorURL = components.queryItems?.first(where: { $0.name == "coordinator_url" })?.value
            return InviteLinkPayload(inviteToken: inviteToken, coordinatorURL: coordinatorURL)
        }

        if let inviteToken = extractInviteToken(from: trimmed) {
            return InviteLinkPayload(inviteToken: inviteToken, coordinatorURL: nil)
        }

        return nil
    }

    private static func extractInviteToken(from raw: String) -> String? {
        guard let range = raw.range(of: "invite-") else { return nil }
        let suffix = raw[range.lowerBound...]
        let token = suffix.prefix { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
        }
        let normalized = String(token)
        guard normalized.hasPrefix("invite-"), normalized.count >= 20 else { return nil }
        return normalized
    }
}
