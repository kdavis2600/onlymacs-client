import Foundation

public struct ProviderCapabilitySnapshot: Codable, Equatable, Hashable, Sendable {
    public let unifiedMemoryGB: Int
    public let freeDiskGB: Int
    public let verifiedLargestSafeModelRAMGB: Int?
    public let verifiedSustainedSlots: Int?

    public init(
        unifiedMemoryGB: Int,
        freeDiskGB: Int,
        verifiedLargestSafeModelRAMGB: Int? = nil,
        verifiedSustainedSlots: Int? = nil
    ) {
        self.unifiedMemoryGB = max(0, unifiedMemoryGB)
        self.freeDiskGB = max(0, freeDiskGB)
        self.verifiedLargestSafeModelRAMGB = verifiedLargestSafeModelRAMGB.map { max(0, $0) }
        self.verifiedSustainedSlots = verifiedSustainedSlots.map { max(0, $0) }
    }
}

public struct ProviderCapabilityAssessment: Equatable, Hashable, Sendable {
    public let tier: ProviderCapabilityTier
    public let confidence: Double
    public let rationale: String

    public init(tier: ProviderCapabilityTier, confidence: Double, rationale: String) {
        self.tier = tier
        self.confidence = confidence
        self.rationale = rationale
    }
}

public enum ProviderCapabilityTiering {
    public static func assess(_ snapshot: ProviderCapabilitySnapshot) -> ProviderCapabilityAssessment {
        let memoryTier = tierForUnifiedMemory(snapshot.unifiedMemoryGB)
        let verifiedTier = snapshot.verifiedLargestSafeModelRAMGB.map(tierForVerifiedHosting)
        let slots = snapshot.verifiedSustainedSlots ?? 0

        let tier: ProviderCapabilityTier
        let confidence: Double
        let rationale: String

        if let verifiedTier {
            tier = min(memoryTier, verifiedTier)
            confidence = 0.9
            rationale = "Verified hosting capability is available, so OnlyMacs is using the safer lower of hardware memory and benchmarked hosting capacity."
        } else {
            tier = memoryTier
            confidence = 0.6
            rationale = "OnlyMacs is using unified memory as a provisional tier until benchmarked hosting capacity is available."
        }

        if tier == .tier1, slots > 0, slots < 2 {
            return ProviderCapabilityAssessment(
                tier: .tier2,
                confidence: min(confidence + 0.05, 0.95),
                rationale: "This Mac has Tier 1-class memory, but the current sustained slot estimate is still conservative, so OnlyMacs is temporarily treating it as Tier 2."
            )
        }

        return ProviderCapabilityAssessment(tier: tier, confidence: confidence, rationale: rationale)
    }

    public static func tier(for snapshot: ProviderCapabilitySnapshot) -> ProviderCapabilityTier {
        assess(snapshot).tier
    }

    private static func tierForUnifiedMemory(_ unifiedMemoryGB: Int) -> ProviderCapabilityTier {
        switch unifiedMemoryGB {
        case 224...:
            return .tier1
        case 112...:
            return .tier2
        case 56...:
            return .tier3
        default:
            return .tier4
        }
    }

    private static func tierForVerifiedHosting(_ largestSafeModelRAMGB: Int) -> ProviderCapabilityTier {
        switch largestSafeModelRAMGB {
        case 180...:
            return .tier1
        case 48...:
            return .tier2
        case 28...:
            return .tier3
        default:
            return .tier4
        }
    }
}

private func min(_ lhs: ProviderCapabilityTier, _ rhs: ProviderCapabilityTier) -> ProviderCapabilityTier {
    lhs.sortRank <= rhs.sortRank ? lhs : rhs
}

private extension ProviderCapabilityTier {
    var sortRank: Int {
        switch self {
        case .tier1:
            return 1
        case .tier2:
            return 2
        case .tier3:
            return 3
        case .tier4:
            return 4
        }
    }
}
