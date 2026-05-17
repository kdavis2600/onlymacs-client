import Testing
@testable import OnlyMacsCore

@Test
func queueAdvancesOneModelAtATime() throws {
    var queue = ModelDownloadQueue(modelIDs: ["alpha", "beta"])

    let first = try queue.startNextIfPossible()
    #expect(first?.id == "alpha")
    #expect(queue.activeItem?.id == "alpha")

    try queue.markWarming("alpha")
    try queue.markReady("alpha")

    let second = try queue.startNextIfPossible()
    #expect(second?.id == "beta")
    #expect(queue.activeItem?.id == "beta")
}

@Test
func queueRejectsConcurrentActiveItems() throws {
    let items = [
        ModelDownloadQueueItem(id: "alpha", phase: .downloading),
        ModelDownloadQueueItem(id: "beta", phase: .warming),
    ]

    #expect(throws: ModelDownloadQueueError.self) {
        try ModelDownloadQueue(items: items)
    }
}

@Test
func failedItemKeepsReasonAndLetsQueueContinue() throws {
    var queue = ModelDownloadQueue(modelIDs: ["alpha", "beta"])

    _ = try queue.startNextIfPossible()
    try queue.markFailed("alpha", reason: "network timeout")

    let next = try queue.startNextIfPossible()
    #expect(next?.id == "beta")
    #expect(queue.items.first?.failureReason == "network timeout")
}

@Test
func failedItemCanBeRetried() throws {
    var queue = ModelDownloadQueue(modelIDs: ["alpha"])

    _ = try queue.startNextIfPossible()
    try queue.markFailed("alpha", reason: "network timeout")
    try queue.retry("alpha")

    #expect(queue.item(for: "alpha")?.phase == .pending)
    #expect(queue.item(for: "alpha")?.failureReason == nil)
}
