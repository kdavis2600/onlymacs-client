import Foundation

public enum ModelDownloadPhase: String, Codable, CaseIterable, Sendable {
    case pending
    case downloading
    case warming
    case ready
    case failed

    public var isActive: Bool {
        self == .downloading || self == .warming
    }
}

public struct ModelDownloadQueueItem: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public var phase: ModelDownloadPhase
    public var failureReason: String?

    public init(id: String, phase: ModelDownloadPhase = .pending, failureReason: String? = nil) {
        self.id = id
        self.phase = phase
        self.failureReason = failureReason
    }
}

public enum ModelDownloadQueueError: Error, CustomStringConvertible, Sendable {
    case duplicateModelID(String)
    case concurrentActiveItem
    case missingModelID(String)
    case invalidTransition(String, from: ModelDownloadPhase, to: ModelDownloadPhase)

    public var description: String {
        switch self {
        case .duplicateModelID(let id):
            return "The queue already contains '\(id)'."
        case .concurrentActiveItem:
            return "Only one model may be downloading or warming at a time."
        case .missingModelID(let id):
            return "The queue does not contain '\(id)'."
        case .invalidTransition(let id, let from, let to):
            return "The queue cannot move '\(id)' from \(from.rawValue) to \(to.rawValue)."
        }
    }
}

public struct ModelDownloadQueue: Codable, Equatable, Sendable {
    public private(set) var items: [ModelDownloadQueueItem]

    public init(items: [ModelDownloadQueueItem] = []) throws {
        try Self.validate(items)
        self.items = items
    }

    public init(modelIDs: [String]) {
        self.items = modelIDs.map { ModelDownloadQueueItem(id: $0) }
    }

    public var activeItem: ModelDownloadQueueItem? {
        items.first(where: { $0.phase.isActive })
    }

    public func item(for modelID: String) -> ModelDownloadQueueItem? {
        items.first(where: { $0.id == modelID })
    }

    public mutating func enqueue(_ modelID: String) throws {
        guard items.contains(where: { $0.id == modelID }) == false else {
            throw ModelDownloadQueueError.duplicateModelID(modelID)
        }
        items.append(ModelDownloadQueueItem(id: modelID))
    }

    @discardableResult
    public mutating func startNextIfPossible() throws -> ModelDownloadQueueItem? {
        guard activeItem == nil else {
            return nil
        }

        guard let index = items.firstIndex(where: { $0.phase == .pending }) else {
            return nil
        }

        items[index].phase = .downloading
        items[index].failureReason = nil
        return items[index]
    }

    public mutating func markWarming(_ modelID: String) throws {
        try transition(modelID, from: .downloading, to: .warming)
    }

    public mutating func markReady(_ modelID: String) throws {
        guard let index = items.firstIndex(where: { $0.id == modelID }) else {
            throw ModelDownloadQueueError.missingModelID(modelID)
        }

        let phase = items[index].phase
        guard phase == .warming || phase == .downloading else {
            throw ModelDownloadQueueError.invalidTransition(modelID, from: phase, to: .ready)
        }

        items[index].phase = .ready
        items[index].failureReason = nil
    }

    public mutating func markFailed(_ modelID: String, reason: String) throws {
        guard let index = items.firstIndex(where: { $0.id == modelID }) else {
            throw ModelDownloadQueueError.missingModelID(modelID)
        }

        let phase = items[index].phase
        guard phase == .pending || phase.isActive else {
            throw ModelDownloadQueueError.invalidTransition(modelID, from: phase, to: .failed)
        }

        items[index].phase = .failed
        items[index].failureReason = reason
    }

    public mutating func retry(_ modelID: String) throws {
        guard let index = items.firstIndex(where: { $0.id == modelID }) else {
            throw ModelDownloadQueueError.missingModelID(modelID)
        }

        let phase = items[index].phase
        guard phase == .failed else {
            throw ModelDownloadQueueError.invalidTransition(modelID, from: phase, to: .pending)
        }

        items[index].phase = .pending
        items[index].failureReason = nil
    }

    private mutating func transition(_ modelID: String, from allowedPhase: ModelDownloadPhase, to targetPhase: ModelDownloadPhase) throws {
        guard let index = items.firstIndex(where: { $0.id == modelID }) else {
            throw ModelDownloadQueueError.missingModelID(modelID)
        }

        let phase = items[index].phase
        guard phase == allowedPhase else {
            throw ModelDownloadQueueError.invalidTransition(modelID, from: phase, to: targetPhase)
        }

        items[index].phase = targetPhase
        items[index].failureReason = nil
    }

    private static func validate(_ items: [ModelDownloadQueueItem]) throws {
        var seen = Set<String>()
        var activeCount = 0

        for item in items {
            guard seen.insert(item.id).inserted else {
                throw ModelDownloadQueueError.duplicateModelID(item.id)
            }
            if item.phase.isActive {
                activeCount += 1
            }
        }

        guard activeCount <= 1 else {
            throw ModelDownloadQueueError.concurrentActiveItem
        }
    }
}
