import OnlyMacsCore
import SwiftUI

extension BridgeStore {
    var modelRuntimeDependencyPresentation: ModelRuntimeDependencyPresentation? {
        deriveModelRuntimeDependencyPresentation(
            ollamaStatus: runtimeState.ollamaStatus,
            ollamaDetail: runtimeState.ollamaDetail
        )
    }

    var modelRuntimeDependencyAction: (() -> Void)? {
        switch runtimeState.ollamaStatus {
        case .missing:
            return { self.installOllamaNow() }
        case .installedButUnavailable:
            return { self.launchOllamaNow() }
        case .ready, .external:
            return nil
        }
    }

    var installerQueueDisplayItems: [InstallerQueueDisplayItem] {
        Array(modelDownloadQueue.items.enumerated()).map { index, item in
            let model = libraryModel(for: item.id)
            return InstallerQueueDisplayItem(
                id: item.id,
                title: "\(index + 1). \(model.map(Self.presentableModelName) ?? item.id)",
                phaseLabel: item.phase.rawValue.capitalized,
                detail: item.failureReason ?? installerQueueDetails[item.id]
            )
        }
    }

    var modelLibraryDisplayItems: [ModelLibraryDisplayItem] {
        let discoveredRuntimeModelIDs = Set(localShare.discoveredModels.map(\.id))
        let publishedRuntimeModelIDs = Set(localShare.publishedModels.map(\.id))

        return libraryCatalogModels.map { model in
            let runtimeModelID = model.proofRuntimeModelID
            let queueItem = modelDownloadQueue.item(for: model.id)
            let isInstalled = runtimeModelID.map(discoveredRuntimeModelIDs.contains) ?? false
            let isActive = runtimeModelID.map(publishedRuntimeModelIDs.contains) ?? false
            let isQueued = isInstallingStarterModels && queueItem?.phase == .pending
            let isWorking = queueItem?.phase == .downloading || queueItem?.phase == .warming
            let didFail = queueItem?.phase == .failed
            let needsMoreDisk = modelNeedsMoreDisk(model)
            let largerModel = modelIsLargeForThisMac(model)
            let priorityPowerModel = modelIs128GBOnlyPowerModel(model) && shouldPrioritize128GBOnlyPowerModels
            let recommendation = installerRecommendationLookupByID[model.id]

            let statusTitle: String
            let statusColor: Color
            let statusDetail: String
            let actionTitle: String?
            let actionEnabled: Bool
            let group: ModelLibraryGroup

            if isActive {
                statusTitle = "Active"
                statusColor = .green
                statusDetail = ""
                actionTitle = nil
                actionEnabled = false
                group = .onThisMac
            } else if isInstalled {
                statusTitle = "Installed"
                statusColor = .blue
                statusDetail = ""
                actionTitle = nil
                actionEnabled = false
                group = .onThisMac
            } else if isWorking {
                statusTitle = queueItem?.phase == .warming ? "Finalizing" : "Downloading"
                statusColor = .accentColor
                statusDetail = installerQueueDetails[model.id] ?? "OnlyMacs is adding this model in the background now."
                actionTitle = nil
                actionEnabled = false
                group = .onThisMac
            } else if isQueued {
                statusTitle = "Queued"
                statusColor = .orange
                statusDetail = installerQueueDetails[model.id] ?? "Queued behind the current download."
                actionTitle = nil
                actionEnabled = false
                group = .onThisMac
            } else if didFail {
                statusTitle = "Retry Available"
                statusColor = .red
                statusDetail = queueItem?.failureReason ?? "The last download failed. Try again."
                actionTitle = "Retry"
                actionEnabled = runtimeModelID != nil
                group = .onThisMac
            } else if needsMoreDisk {
                statusTitle = "More Space Needed"
                statusColor = .orange
                statusDetail = priorityPowerModel ? "This 128GB-only power model fits this Mac, but needs more free disk space before download." : "Free up more disk space before adding this model."
                actionTitle = nil
                actionEnabled = false
                group = .needsMoreSpace
            } else if runtimeModelID == nil {
                statusTitle = "Manual"
                statusColor = .orange
                statusDetail = "This model fits this Mac, but OnlyMacs cannot download it with one click yet."
                actionTitle = nil
                actionEnabled = false
                group = .readyToAdd
            } else {
                statusTitle = "Available"
                statusColor = .secondary
                statusDetail = priorityPowerModel ? "This 128GB-only power model fits this Mac and is ready when you want maximum local range." : (largerModel ? "This heavier model fits this Mac and is ready when you want more power." : "This model fits this Mac and is ready to download whenever you want it.")
                actionTitle = "Download"
                actionEnabled = true
                group = .readyToAdd
            }

            return ModelLibraryDisplayItem(
                id: model.id,
                group: group,
                displayName: Self.presentableModelName(model),
                exactModelName: model.exactModelName,
                roleLabel: Self.humanModelRole(model.role),
                quantLabel: model.quant.label,
                recommendationBadge: recommendation?.selectedByDefault == true ? "Starter Pick" : (priorityPowerModel ? "Power" : (largerModel ? "Power" : nil)),
                statusTitle: statusTitle,
                statusDetail: statusDetail,
                statusColor: statusColor,
                requirementLabel: "\(Self.gbLabel(model.installer.estimatedInstalledGB)) disk • \(Self.gbLabel(Double(model.approximateRAMGB))) RAM",
                downloadLabel: group == .onThisMac ? nil : "• ~\(Self.gbLabel(model.installer.estimatedDownloadGB)) download",
                actionTitle: actionTitle,
                actionEnabled: actionEnabled,
                showsProgress: isWorking,
                isPriorityPowerModel: priorityPowerModel,
                requiredRAMGB: model.approximateRAMGB
            )
        }
    }

    var modelLibrarySummaryTitle: String {
        "Models This Mac Can Run"
    }

    var modelLibrarySummaryDetail: String {
        switch runtimeState.ollamaStatus {
        case .missing:
            return "Install Ollama first. Then OnlyMacs can download and host local models on this Mac."
        case .installedButUnavailable:
            return "Ollama is installed but not responding yet. Open it, wait a moment, and OnlyMacs can continue local model work."
        case .ready, .external:
            break
        }
        if capabilityAssessment != nil, catalog != nil {
            return "Installed models stay at the top. Add more in the background whenever you want more range or more power."
        }
        if let catalogError, !catalogError.isEmpty {
            return catalogError
        }
        return "OnlyMacs is still loading the model list for this Mac."
    }

    var selectedModelRecommendations: [InstallerRecommendationItem] {
        installerPlan?.selectedModels ?? []
    }

    var optionalModelRecommendations: [InstallerRecommendationItem] {
        installerPlan?.optionalModels ?? []
    }

    var beastModeRecommendations: [InstallerRecommendationItem] {
        installerPlan?.beastModeModels ?? []
    }

    var setupVisibleModelRecommendations: [InstallerRecommendationItem] {
        libraryCatalogModels.map { model in
            if let existing = installerRecommendationLookupByID[model.id] {
                return existing
            }
            return InstallerRecommendationItem(
                model: model,
                selectedByDefault: false,
                reason: "Fits this Mac, but OnlyMacs leaves it unchecked until you choose to add it."
            )
        }
    }

    var diskBlockedInstallerModelIDs: Set<String> {
        Set(setupVisibleModelRecommendations.compactMap { item in
            modelNeedsMoreDisk(item.model) ? item.id : nil
        })
    }

    var allInstallerRecommendations: [InstallerRecommendationItem] {
        var seen = Set<String>()
        return (selectedModelRecommendations + optionalModelRecommendations + beastModeRecommendations).filter {
            seen.insert($0.id).inserted
        }
    }

    var installableInstallerModelIDs: Set<String> {
        Set(setupVisibleModelRecommendations.compactMap { item in
            item.model.proofRuntimeModelID == nil ? nil : item.id
        })
    }

    var installedInstallerModelIDs: Set<String> {
        Set(setupVisibleModelRecommendations.compactMap { item in
            modelIsInstalled(item.model) ? item.id : nil
        })
    }

    var selectedInstallerCount: Int {
        selectedInstallerModelIDs.count
    }

    var selectedInstallerDownloadGB: Double {
        setupVisibleModelRecommendations.reduce(0) { partial, item in
            guard selectedInstallerModelIDs.contains(item.id) else { return partial }
            return partial + item.model.installer.estimatedDownloadGB
        }
    }

    var starterModelSetupNeedsAttention: Bool {
        isInstallingStarterModels || !hasCompletedStarterModelSetup || localShare.discoveredModels.isEmpty
    }

    var starterModelSetupSummary: String {
        if isInstallingStarterModels {
            return "OnlyMacs is downloading the models you picked now."
        }
        if let completionDetail = starterModelCompletionDetail, !completionDetail.isEmpty {
            return completionDetail
        }
        if selectedInstallerModelIDs.isEmpty {
            return "Pick at least one model for this Mac."
        }
        return "OnlyMacs will download \(selectedInstallerCount) selected model(s) one at a time and let you know when they are ready."
    }

    var nextModelSuggestion: ModelSummary? {
        guard selectedMode.allowsShare, selfTestState.isSuccessful else {
            return nil
        }

        let published = Set(localShare.publishedModels.map(\.id))
        return localShare.discoveredModels.first(where: { !published.contains($0.id) })
    }

    func modelIsInstalled(_ model: ModelCatalogEntry) -> Bool {
        guard let runtimeModelID = model.proofRuntimeModelID else { return false }
        return localShare.discoveredModels.contains(where: { $0.id == runtimeModelID })
    }

    func libraryModel(for id: String) -> ModelCatalogEntry? {
        catalog?.models.first(where: { $0.id == id })
    }

    func modelNeedsMoreDisk(_ model: ModelCatalogEntry) -> Bool {
        guard capabilitySnapshot.freeDiskGB > 0 else { return false }
        return model.installer.estimatedInstalledGB > Double(capabilitySnapshot.freeDiskGB)
    }

    func setInstallerQueueDetail(_ modelID: String, _ detail: String?) {
        if let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            installerQueueDetails[modelID] = detail
        } else {
            installerQueueDetails.removeValue(forKey: modelID)
        }
    }

    static func gbLabel(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " GB"
    }

    static func presentableModelName(_ model: ModelCatalogEntry) -> String {
        var name = model.exactModelName.split(separator: "/").last.map(String.init) ?? model.exactModelName
        name = name.replacingOccurrences(of: "-GGUF", with: "")
        name = name.replacingOccurrences(of: "-Instruct", with: "")
        name = name.replacingOccurrences(of: "-it", with: "")
        name = name.replacingOccurrences(of: "_", with: " ")
        name = name.replacingOccurrences(of: "-", with: " ")
        name = name.replacingOccurrences(of: "Qwen2.5", with: "Qwen 2.5")
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func humanModelRole(_ role: ModelRole) -> String {
        switch role {
        case .coding:
            return "Coding"
        case .general:
            return "General"
        case .reasoning:
            return "Reasoning"
        case .multimodal:
            return "Multimodal"
        }
    }
}

private extension BridgeStore {
    var installerRecommendationLookupByID: [String: InstallerRecommendationItem] {
        Dictionary(uniqueKeysWithValues: allInstallerRecommendations.map { ($0.id, $0) })
    }

    var libraryCatalogModels: [ModelCatalogEntry] {
        guard let catalog else { return [] }
        return catalog.models
            .filter(modelFitsLibrary)
            .sorted(by: compareLibraryModels)
    }

    func modelFitsLibrary(_ model: ModelCatalogEntry) -> Bool {
        capabilitySnapshot.unifiedMemoryGB > 0 && model.approximateRAMGB <= capabilitySnapshot.unifiedMemoryGB
    }

    func modelIsLargeForThisMac(_ model: ModelCatalogEntry) -> Bool {
        model.advancedVisibility.beastModeEligible
            || (shouldPrioritize128GBOnlyPowerModels && modelIs128GBOnlyPowerModel(model))
            || Double(model.approximateRAMGB) >= Double(capabilitySnapshot.unifiedMemoryGB) * 0.75
    }

    func compareLibraryModels(_ lhs: ModelCatalogEntry, _ rhs: ModelCatalogEntry) -> Bool {
        compareLibraryModelsForDisplay(
            lhs,
            rhs,
            lhsInstalled: modelIsInstalled(lhs),
            rhsInstalled: modelIsInstalled(rhs),
            lhsRecommended: installerRecommendationLookupByID[lhs.id]?.selectedByDefault == true,
            rhsRecommended: installerRecommendationLookupByID[rhs.id]?.selectedByDefault == true,
            prioritize128GBOnlyPowerModels: shouldPrioritize128GBOnlyPowerModels
        )
    }

    var shouldPrioritize128GBOnlyPowerModels: Bool {
        let tier = capabilityAssessment?.tier ?? ProviderCapabilityTiering.tier(for: capabilitySnapshot)
        return tier == .tier2
    }
}

func modelIs128GBOnlyPowerModel(_ model: ModelCatalogEntry) -> Bool {
    model.approximateRAMGB > 64
        && model.capabilityTiers.firstRunVisibleTiers.contains(.tier2)
        && !model.capabilityTiers.firstRunVisibleTiers.contains(.tier3)
        && !model.capabilityTiers.firstRunVisibleTiers.contains(.tier4)
        && !model.installer.starterSubset
}

func compareLibraryModelsForDisplay(
    _ lhs: ModelCatalogEntry,
    _ rhs: ModelCatalogEntry,
    lhsInstalled: Bool,
    rhsInstalled: Bool,
    lhsRecommended: Bool,
    rhsRecommended: Bool,
    prioritize128GBOnlyPowerModels: Bool
) -> Bool {
    let lhsPriority = libraryModelDisplayPriority(
        lhs,
        installed: lhsInstalled,
        recommended: lhsRecommended,
        prioritize128GBOnlyPowerModels: prioritize128GBOnlyPowerModels
    )
    let rhsPriority = libraryModelDisplayPriority(
        rhs,
        installed: rhsInstalled,
        recommended: rhsRecommended,
        prioritize128GBOnlyPowerModels: prioritize128GBOnlyPowerModels
    )
    if lhsPriority != rhsPriority {
        return lhsPriority < rhsPriority
    }

    if lhs.approximateRAMGB != rhs.approximateRAMGB {
        return lhs.approximateRAMGB > rhs.approximateRAMGB
    }
    return lhs.id < rhs.id
}

func libraryModelDisplayPriority(
    _ model: ModelCatalogEntry,
    installed: Bool,
    recommended: Bool,
    prioritize128GBOnlyPowerModels: Bool
) -> Int {
    if installed {
        return 0
    }
    if prioritize128GBOnlyPowerModels, modelIs128GBOnlyPowerModel(model) {
        return 1
    }
    if recommended {
        return 2
    }
    return 3
}
