import Foundation

enum OnlyMacsContextPackScope: String, Codable, Hashable, Sendable {
    case publicSafe = "public_safe"
    case privateOnly = "private_only"
    case privateTrusted = "private_trusted"
}

struct OnlyMacsContextPackDefinition: Hashable, Sendable {
    let id: String
    let description: String
    let scope: OnlyMacsContextPackScope
    let include: [String]
    let exclude: [String]
    let source: String
}

struct OnlyMacsContextPackCatalog: Sendable {
    let packs: [OnlyMacsContextPackDefinition]
    let selectedPackIDs: Set<String>
    let warnings: [String]

    func suggestedMatches(for relativePath: String) -> [OnlyMacsContextPackDefinition] {
        matchingPacks(for: relativePath, selectedOnly: true)
    }

    func matchingPacks(for relativePath: String, selectedOnly: Bool = false) -> [OnlyMacsContextPackDefinition] {
        packs.filter { pack in
            (!selectedOnly || selectedPackIDs.contains(pack.id)) && pack.matches(relativePath: relativePath)
        }
    }

    func selectedManifestEntries(selectedRelativePaths: [String]) -> [OnlyMacsCapsuleContextPack] {
        let selectedSet = Set(selectedRelativePaths)
        return packs
            .filter { selectedPackIDs.contains($0.id) }
            .compactMap { pack in
                let matchedFiles = selectedSet
                    .filter { pack.matches(relativePath: $0) }
                    .sorted()
                guard !matchedFiles.isEmpty else { return nil }
                return OnlyMacsCapsuleContextPack(
                    id: pack.id,
                    description: pack.description,
                    scope: pack.scope.rawValue,
                    source: pack.source,
                    matchedFiles: matchedFiles
                )
            }
            .sorted { $0.id < $1.id }
    }
}

enum OnlyMacsContextPackStore {
    static func loadCatalog(workspaceRoot: String, promptProfile: OnlyMacsPromptProfile) -> OnlyMacsContextPackCatalog {
        let builtIns = builtInPacks()
        let requestedPackIDs = Set(promptProfile.suggestedContextPackIDs)
        let fileURL = contextPackConfigURL(workspaceRoot: workspaceRoot)
        let loaded = loadCustomPacks(from: fileURL)

        var mergedByID: [String: OnlyMacsContextPackDefinition] = [:]
        for pack in builtIns {
            mergedByID[pack.id] = pack
        }
        for pack in loaded.packs {
            mergedByID[pack.id] = pack
        }

        let packs = mergedByID.values.sorted { $0.id < $1.id }
        let selectedPackIDs = Set(packs.map(\.id)).intersection(requestedPackIDs)
        return OnlyMacsContextPackCatalog(
            packs: packs,
            selectedPackIDs: selectedPackIDs,
            warnings: loaded.warnings
        )
    }

    private static func contextPackConfigURL(workspaceRoot: String) -> URL? {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: workspaceRoot, isDirectory: true).appendingPathComponent(".onlymacs", isDirectory: true)
        for name in ["context-packs.yml", "context-packs.yaml"] {
            let candidate = base.appendingPathComponent(name, isDirectory: false)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private static func loadCustomPacks(from url: URL?) -> (packs: [OnlyMacsContextPackDefinition], warnings: [String]) {
        guard let url else { return ([], []) }
        guard let data = try? Data(contentsOf: url), let raw = String(data: data, encoding: .utf8) else {
            return ([], ["OnlyMacs could not read \(url.lastPathComponent)."])
        }

        if raw.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            return loadJSONPacks(raw: raw, source: url.lastPathComponent)
        }
        return parseYAMLPacks(raw: raw, source: url.lastPathComponent)
    }

    private static func loadJSONPacks(raw: String, source: String) -> (packs: [OnlyMacsContextPackDefinition], warnings: [String]) {
        struct RawConfig: Decodable {
            let schema: String
            let packs: [RawPack]
        }
        struct RawPack: Decodable {
            let id: String
            let description: String
            let scope: String
            let include: [String]
            let exclude: [String]?
        }

        guard let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(RawConfig.self, from: data) else {
            return ([], ["OnlyMacs ignored \(source) because it is not valid JSON context-pack config."])
        }
        guard decoded.schema == "v1" else {
            return ([], ["OnlyMacs ignored \(source) because it uses an unknown context-pack schema."])
        }
        return validateCustomPacks(
            decoded.packs.map {
                OnlyMacsContextPackDefinition(
                    id: $0.id,
                    description: $0.description,
                    scope: OnlyMacsContextPackScope(rawValue: $0.scope) ?? .privateOnly,
                    include: $0.include,
                    exclude: $0.exclude ?? [],
                    source: "custom"
                )
            },
            source: source
        )
    }

    private static func parseYAMLPacks(raw: String, source: String) -> (packs: [OnlyMacsContextPackDefinition], warnings: [String]) {
        var schema = ""
        var packs: [OnlyMacsContextPackDefinition] = []
        var current: (id: String, description: String, scope: String, include: [String], exclude: [String])?
        var activeListKey: String?

        func finishCurrent() {
            guard let current else { return }
            packs.append(
                OnlyMacsContextPackDefinition(
                    id: current.id,
                    description: current.description,
                    scope: OnlyMacsContextPackScope(rawValue: current.scope) ?? .privateOnly,
                    include: current.include,
                    exclude: current.exclude,
                    source: "custom"
                )
            )
        }

        for rawLine in raw.components(separatedBy: .newlines) {
            let line = rawLine.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            let indent = line.prefix { $0 == " " }.count
            if indent == 0, trimmed.hasPrefix("schema:") {
                schema = valueAfterColon(trimmed)
                activeListKey = nil
                continue
            }
            if indent == 0, trimmed == "packs:" {
                activeListKey = nil
                continue
            }
            if indent == 2, trimmed.hasPrefix("- ") {
                finishCurrent()
                current = (id: "", description: "", scope: "private_only", include: [], exclude: [])
                activeListKey = nil
                let remainder = String(trimmed.dropFirst(2))
                if remainder.hasPrefix("id:") {
                    current?.id = valueAfterColon(remainder)
                }
                continue
            }
            if indent == 4, trimmed.hasPrefix("id:") {
                current?.id = valueAfterColon(trimmed)
                activeListKey = nil
                continue
            }
            if indent == 4, trimmed.hasPrefix("description:") {
                current?.description = valueAfterColon(trimmed)
                activeListKey = nil
                continue
            }
            if indent == 4, trimmed.hasPrefix("scope:") {
                current?.scope = valueAfterColon(trimmed)
                activeListKey = nil
                continue
            }
            if indent == 4, trimmed == "include:" || trimmed == "exclude:" {
                activeListKey = String(trimmed.dropLast())
                continue
            }
            if indent >= 6, trimmed.hasPrefix("- "), let activeListKey {
                let value = sanitizeScalar(String(trimmed.dropFirst(2)))
                switch activeListKey {
                case "include":
                    current?.include.append(value)
                case "exclude":
                    current?.exclude.append(value)
                default:
                    break
                }
            }
        }
        finishCurrent()

        guard schema == "v1" else {
            return ([], ["OnlyMacs ignored \(source) because it uses an unknown context-pack schema."])
        }
        return validateCustomPacks(packs, source: source)
    }

    private static func validateCustomPacks(
        _ packs: [OnlyMacsContextPackDefinition],
        source: String
    ) -> (packs: [OnlyMacsContextPackDefinition], warnings: [String]) {
        var accepted: [OnlyMacsContextPackDefinition] = []
        var warnings: [String] = []

        for pack in packs {
            if pack.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pack.include.isEmpty {
                warnings.append("OnlyMacs ignored an invalid context pack in \(source) because it was missing an id or include rules.")
                continue
            }
            if pack.scope == .publicSafe && pack.include.contains(where: isBroadPublicPattern) {
                warnings.append("OnlyMacs ignored \(pack.id) in \(source) because public-safe packs cannot include broad workspace globs.")
                continue
            }
            if pack.scope == .publicSafe && (pack.include.contains(where: isHiddenPattern) || pack.exclude.contains(where: isHiddenPattern)) {
                warnings.append("OnlyMacs ignored \(pack.id) in \(source) because public-safe packs cannot target hidden files by default.")
                continue
            }
            accepted.append(pack)
        }

        return (accepted, warnings)
    }

    private static func builtInPacks() -> [OnlyMacsContextPackDefinition] {
        [
            OnlyMacsContextPackDefinition(
                id: "content-pipeline",
                description: "Master pipeline docs, schemas, examples, and runner logic for content-generation work.",
                scope: .privateOnly,
                include: [
                    "docs/**/*.md",
                    "scripts/**/*.js",
                    "scripts/**/*.ts",
                    "**/*schema*.md",
                    "**/*schema*.json",
                    "**/*example*",
                    "**/*sample*"
                ],
                exclude: ["**/deprecated/**", "**/.git/**", "**/node_modules/**"],
                source: "built_in"
            ),
            OnlyMacsContextPackDefinition(
                id: "docs-review",
                description: "Readable docs, READMEs, guides, and prompts for doc-grounded review tasks.",
                scope: .publicSafe,
                include: ["README.md", "**/*.md", "**/*.txt", "**/*.yaml", "**/*.yml"],
                exclude: ["**/.git/**", "**/.env*", "**/node_modules/**"],
                source: "built_in"
            ),
            OnlyMacsContextPackDefinition(
                id: "code-review-core",
                description: "Primary source, config, and tests for grounded code review.",
                scope: .privateOnly,
                include: ["src/**/*", "app/**/*", "tests/**/*", "package.json", "tsconfig*.json", "**/*.swift", "**/*.ts", "**/*.tsx", "**/*.js"],
                exclude: ["**/node_modules/**", "**/dist/**", "**/build/**", "**/.git/**"],
                source: "built_in"
            ),
            OnlyMacsContextPackDefinition(
                id: "schema-generation",
                description: "Schemas, examples, and data-shape docs for generation and transform tasks.",
                scope: .publicSafe,
                include: ["**/*schema*", "**/*example*", "**/*sample*", "**/*.json", "**/*.yaml", "**/*.yml", "**/*.csv"],
                exclude: ["**/.env*", "**/.git/**", "**/node_modules/**"],
                source: "built_in"
            ),
            OnlyMacsContextPackDefinition(
                id: "transform-context",
                description: "Target file plus supporting schema/config context for grounded edits and transforms.",
                scope: .privateTrusted,
                include: ["**/*.json", "**/*.yaml", "**/*.yml", "**/*.md", "package.json", "tsconfig*.json", "**/*.ts", "**/*.tsx", "**/*.swift"],
                exclude: ["**/.env*", "**/.git/**", "**/node_modules/**"],
                source: "built_in"
            )
        ]
    }

    private static func valueAfterColon(_ line: String) -> String {
        sanitizeScalar(String(line.split(separator: ":", maxSplits: 1).dropFirst().first ?? ""))
    }

    private static func sanitizeScalar(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static func isBroadPublicPattern(_ pattern: String) -> Bool {
        let normalized = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "**/*" || normalized == "**" || normalized == "*"
    }

    private static func isHiddenPattern(_ pattern: String) -> Bool {
        let normalized = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.hasPrefix(".") || normalized.contains("/.")
    }
}

private extension OnlyMacsContextPackDefinition {
    func matches(relativePath: String) -> Bool {
        let normalized = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard include.contains(where: { globMatches($0, normalized) }) else {
            return false
        }
        return !exclude.contains(where: { globMatches($0, normalized) })
    }

    func globMatches(_ pattern: String, _ value: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*\\*\\/", with: "§§DOUBLESTARSLASH§§")
            .replacingOccurrences(of: "\\*\\*/", with: "§§DOUBLESTARSLASH§§")
            .replacingOccurrences(of: "\\*\\*", with: "§§DOUBLESTAR§§")
            .replacingOccurrences(of: "\\*", with: "[^/]*")
            .replacingOccurrences(of: "§§DOUBLESTARSLASH§§", with: "(?:.*/)?")
            .replacingOccurrences(of: "§§DOUBLESTAR§§", with: ".*")
            .replacingOccurrences(of: "\\?", with: "[^/]")
        let regex = "^" + escaped + "$"
        return value.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
