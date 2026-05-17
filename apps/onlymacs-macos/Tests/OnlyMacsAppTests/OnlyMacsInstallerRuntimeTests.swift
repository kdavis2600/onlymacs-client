import Testing
@testable import OnlyMacsApp
import OnlyMacsCore

@Test
func curatedStarterModelsMapOntoCurrentProofRuntimeTags() throws {
    let catalog = try ModelCatalogLoader.loadBundled()

    let mapped = Dictionary(uniqueKeysWithValues: catalog.models.map { ($0.id, $0.proofRuntimeModelID) })

    #expect(mapped["qwen25-coder-7b-q4km"] == "qwen2.5-coder:7b")
    #expect(mapped["qwen25-coder-14b-q4km"] == "qwen2.5-coder:14b")
    #expect(mapped["qwen25-coder-32b-q4km"] == "qwen2.5-coder:32b")
    #expect(mapped["qwen36-35b-a3b-q4km"] == "qwen3.6:35b-a3b-q4_K_M")
    #expect(mapped["qwen36-35b-a3b-q8_0"] == "qwen3.6:35b-a3b-q8_0")
    #expect(mapped["gemma3-27b-q4km"] == "gemma3:27b")
    #expect(mapped["gemma4-31b-q4km"] == "gemma4:31b")
    #expect(mapped["codestral-22b-q4km"] == "codestral:22b")
    #expect(mapped["qwq-32b-q4km"] == "qwq:32b")
    #expect(mapped["gpt-oss-120b-mxfp4"] == "gpt-oss:120b")
    #expect(mapped["deepseek-r1-70b-q4km"] == "deepseek-r1:70b")
    #expect(mapped["qwen25-72b-q4km"] == "qwen2.5:72b")
    #expect(mapped["llama31-70b-q4km"] == "llama3.1:70b")
}

@Test
func beastModeCatalogEntriesStayVisibleButUnmappedForAutoInstall() throws {
    let catalog = try ModelCatalogLoader.loadBundled()
    let beastIDs = Set(catalog.models.filter { $0.advancedVisibility.beastModeEligible }.map(\.id))

    #expect(beastIDs.contains("qwen3-235b-a22b-beast"))
    #expect(beastIDs.contains("llama4-maverick-beast"))
    #expect(catalog.models.first(where: { $0.id == "qwen3-235b-a22b-beast" })?.proofRuntimeModelID == nil)
    #expect(catalog.models.first(where: { $0.id == "llama4-maverick-beast" })?.proofRuntimeModelID == nil)
}

@Test
func installerProgressDetailIncludesTransferRateWhenAvailable() {
    let progress = InstallerDownloadProgress(
        modelID: "qwen2.5-coder:14b",
        status: "Downloading",
        completedBytes: 512_000_000,
        totalBytes: 2_048_000_000,
        bytesPerSecond: 1_536_000
    )

    #expect(progress.detail.contains("Downloading"))
    #expect(progress.detail.contains("%"))
    #expect(progress.detail.contains("/s"))
}
