import Foundation
import OnlyMacsCore

extension ModelCatalogEntry {
    var proofRuntimeModelID: String? {
        switch id {
        case "qwen25-coder-7b-q4km":
            return "qwen2.5-coder:7b"
        case "qwen25-coder-14b-q4km":
            return "qwen2.5-coder:14b"
        case "qwen25-coder-32b-q4km", "qwen25-coder-32b-q5km":
            return "qwen2.5-coder:32b"
        case "qwen36-35b-a3b-q4km":
            return "qwen3.6:35b-a3b-q4_K_M"
        case "qwen36-35b-a3b-q8_0":
            return "qwen3.6:35b-a3b-q8_0"
        case "gemma3-27b-q4km":
            return "gemma3:27b"
        case "gemma4-31b-q4km":
            return "gemma4:31b"
        case "codestral-22b-q4km":
            return "codestral:22b"
        case "qwq-32b-q4km":
            return "qwq:32b"
        case "gpt-oss-120b-mxfp4":
            return "gpt-oss:120b"
        case "deepseek-r1-70b-q4km":
            return "deepseek-r1:70b"
        case "qwen25-72b-q4km":
            return "qwen2.5:72b"
        case "llama31-70b-q4km":
            return "llama3.1:70b"
        default:
            return nil
        }
    }
}

struct InstallerDownloadProgress: Sendable {
    let modelID: String
    let status: String
    let completedBytes: Int64?
    let totalBytes: Int64?
    let bytesPerSecond: Double?

    var detail: String {
        let trimmedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []

        if !trimmedStatus.isEmpty {
            parts.append(trimmedStatus)
        }

        if let completedBytes, let totalBytes, totalBytes > 0 {
            let percent = min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
            let percentLabel = percent.formatted(.percent.precision(.fractionLength(0)))
            let completedLabel = Self.byteCountLabel(completedBytes)
            let totalLabel = Self.byteCountLabel(totalBytes)
            parts.append(percentLabel)
            parts.append("\(completedLabel) / \(totalLabel)")
        }

        if let bytesPerSecond, bytesPerSecond > 0 {
            parts.append("\(Self.transferRateLabel(bytesPerSecond))/s")
        }

        if parts.isEmpty {
            return "Working…"
        }
        return parts.joined(separator: " • ")
    }

    private static func byteCountLabel(_ byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: byteCount)
    }

    private static func transferRateLabel(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useBytes]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytesPerSecond.rounded()))
    }
}

actor ModelInstallerService {
    private struct ProgressSample: Sendable {
        let completedBytes: Int64
        let timestamp: Date
        let bytesPerSecond: Double?
    }

    private let session: URLSession
    private let baseURL: URL
    private let decoder = JSONDecoder()
    private var progressSamples: [String: ProgressSample] = [:]

    init(baseURL: URL? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL ?? Self.defaultBaseURL()
        self.session = session
    }

    func pullModel(
        _ model: ModelCatalogEntry,
        progress: @escaping @Sendable (InstallerDownloadProgress) -> Void
    ) async throws -> String {
        guard let runtimeModelID = model.proofRuntimeModelID else {
            throw ModelInstallerServiceError.unsupportedModel(model.exactModelName)
        }

        progressSamples.removeValue(forKey: runtimeModelID)

        var request = URLRequest(url: baseURL.appending(path: "/api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaPullRequest(model: runtimeModelID, stream: true))

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelInstallerServiceError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ModelInstallerServiceError.backendFailure(message ?? "HTTP \(httpResponse.statusCode)")
        }

        var sawEvent = false
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            sawEvent = true

            let event = try decoder.decode(OllamaPullEvent.self, from: Data(trimmed.utf8))
            if let error = event.error?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
                progressSamples.removeValue(forKey: runtimeModelID)
                throw ModelInstallerServiceError.backendFailure(error)
            }

            let bytesPerSecond = transferRate(
                for: runtimeModelID,
                completedBytes: event.completed
            )

            progress(
                InstallerDownloadProgress(
                    modelID: runtimeModelID,
                    status: event.status ?? "Downloading…",
                    completedBytes: event.completed,
                    totalBytes: event.total,
                    bytesPerSecond: bytesPerSecond
                )
            )
        }

        if !sawEvent {
            progress(
                InstallerDownloadProgress(
                    modelID: runtimeModelID,
                    status: "Download request sent.",
                    completedBytes: nil,
                    totalBytes: nil,
                    bytesPerSecond: nil
                )
            )
        }

        progressSamples.removeValue(forKey: runtimeModelID)
        return runtimeModelID
    }

    private func transferRate(for runtimeModelID: String, completedBytes: Int64?) -> Double? {
        guard let completedBytes, completedBytes >= 0 else {
            return progressSamples[runtimeModelID]?.bytesPerSecond
        }

        let now = Date()
        guard let previous = progressSamples[runtimeModelID] else {
            progressSamples[runtimeModelID] = ProgressSample(
                completedBytes: completedBytes,
                timestamp: now,
                bytesPerSecond: nil
            )
            return nil
        }

        let deltaBytes = completedBytes - previous.completedBytes
        let deltaTime = now.timeIntervalSince(previous.timestamp)
        guard deltaBytes > 0, deltaTime > 0.15 else {
            progressSamples[runtimeModelID] = ProgressSample(
                completedBytes: completedBytes,
                timestamp: now,
                bytesPerSecond: previous.bytesPerSecond
            )
            return previous.bytesPerSecond
        }

        let rate = Double(deltaBytes) / deltaTime
        progressSamples[runtimeModelID] = ProgressSample(
            completedBytes: completedBytes,
            timestamp: now,
            bytesPerSecond: rate
        )
        return rate
    }

    private static func defaultBaseURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["ONLYMACS_OLLAMA_URL"],
           let url = URL(string: override.trimmingCharacters(in: .whitespacesAndNewlines)),
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return url
        }
        return URL(string: "http://127.0.0.1:11434")!
    }
}

enum ModelInstallerServiceError: LocalizedError {
    case unsupportedModel(String)
    case invalidResponse
    case backendFailure(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedModel(modelName):
            return "\(modelName) is listed for this Mac, but OnlyMacs cannot download it with one click yet."
        case .invalidResponse:
            return "OnlyMacs could not understand the local model runtime response."
        case let .backendFailure(message):
            return "The local model runtime refused the download: \(message)"
        }
    }
}

private struct OllamaPullRequest: Encodable {
    let model: String
    let stream: Bool
}

private struct OllamaPullEvent: Decodable {
    let status: String?
    let error: String?
    let total: Int64?
    let completed: Int64?
}
