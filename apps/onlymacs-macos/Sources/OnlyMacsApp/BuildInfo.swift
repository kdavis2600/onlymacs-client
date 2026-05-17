import Foundation
import OnlyMacsCore

struct BuildInfo {
    let version: String
    let buildNumber: String
    let buildTimestamp: String?
    let buildChannel: String?
    let sparkleFeedURLString: String?
    let sparklePublicEDKey: String?
    let defaultCoordinatorURLString: String?

    static let current = BuildInfo(bundle: .main)

    init(
        version: String,
        buildNumber: String,
        buildTimestamp: String? = nil,
        buildChannel: String? = nil,
        sparkleFeedURLString: String? = nil,
        sparklePublicEDKey: String? = nil,
        defaultCoordinatorURLString: String? = nil
    ) {
        self.version = version
        self.buildNumber = buildNumber
        self.buildTimestamp = buildTimestamp
        self.buildChannel = buildChannel
        self.sparkleFeedURLString = sparkleFeedURLString
        self.sparklePublicEDKey = sparklePublicEDKey
        self.defaultCoordinatorURLString = defaultCoordinatorURLString
    }

    init(bundle: Bundle) {
        let info = bundle.infoDictionary ?? [:]
        version = info["CFBundleShortVersionString"] as? String ?? "dev"
        buildNumber = info["CFBundleVersion"] as? String ?? "dev"
        buildTimestamp = info["OnlyMacsBuildTimestamp"] as? String
        buildChannel = info["OnlyMacsBuildChannel"] as? String
        sparkleFeedURLString = info["SUFeedURL"] as? String
        sparklePublicEDKey = info["SUPublicEDKey"] as? String
        defaultCoordinatorURLString = info["OnlyMacsDefaultCoordinatorURL"] as? String
    }

    var displayLabel: String {
        var parts = ["v\(version)", "build \(buildNumber)"]
        if let buildChannel, !buildChannel.isEmpty {
            parts.append(buildChannel)
        }
        return parts.joined(separator: " · ")
    }

    var detailLabel: String {
        if let buildTimestamp, !buildTimestamp.isEmpty {
            return "\(displayLabel) · \(buildTimestamp)"
        }
        return displayLabel
    }

    var channelIdentifier: String {
        let trimmed = buildChannel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "public" : trimmed
    }

    var sparkleFeedURL: URL? {
        guard let sparkleFeedURLString, !sparkleFeedURLString.isEmpty else { return nil }
        return URL(string: sparkleFeedURLString)
    }

    var sparkleReleaseManifestURL: URL? {
        guard let sparkleFeedURL else { return nil }
        let fileName = "latest-\(channelIdentifier).json"

        if sparkleFeedURL.lastPathComponent == "appcast-\(channelIdentifier).xml" {
            return sparkleFeedURL.deletingLastPathComponent().appendingPathComponent(fileName)
        }

        return sparkleFeedURL.deletingLastPathComponent().appendingPathComponent(fileName)
    }

    var sparkleConfigured: Bool {
        guard sparkleFeedURL != nil else { return false }
        let trimmedKey = sparklePublicEDKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmedKey.isEmpty
    }

    var normalizedDefaultCoordinatorURL: String? {
        CoordinatorConnectionSettings(
            mode: .hostedRemote,
            remoteCoordinatorURL: defaultCoordinatorURLString ?? ""
        ).normalizedRemoteCoordinatorURL
    }

    var preferredCoordinatorSettings: CoordinatorConnectionSettings? {
        guard let normalizedDefaultCoordinatorURL else { return nil }
        return CoordinatorConnectionSettings(
            mode: .hostedRemote,
            remoteCoordinatorURL: normalizedDefaultCoordinatorURL
        )
    }
}
