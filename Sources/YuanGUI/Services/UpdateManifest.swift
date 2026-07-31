import Foundation

enum UpdateMetadataSource: Equatable, Sendable {
    case manifest(URL, provider: UpdateAsset.Provider)
    case githubReleaseAPI

    var manifestProvider: UpdateAsset.Provider? {
        guard case .manifest(_, let provider) = self else { return nil }
        return provider
    }
}

struct UpdateAsset: Equatable, Sendable {
    enum Provider: String, Codable, Sendable {
        case gitee
        case github
        case other
    }

    let provider: Provider
    let downloadURL: URL
    /// Manifest assets always provide a checksum. The legacy GitHub API
    /// fallback may omit it when GitHub does not expose an asset digest.
    let sha256: String?
    let size: Int64?
}

struct AvailableUpdate: Equatable, Sendable {
    let version: String
    let build: Int?
    let minimumSystemVersion: String?
    let publishedAt: Date?
    let localizedHighlights: [String]
    let releasePageURL: URL?
    let assets: [UpdateAsset]
    let metadataSource: UpdateMetadataSource
}

struct UpdateManifestAsset: Codable, Equatable, Sendable {
    let provider: UpdateAsset.Provider
    let url: URL
    let sha256: String
    let size: Int64

    func asUpdateAsset() -> UpdateAsset {
        UpdateAsset(provider: provider, downloadURL: url, sha256: sha256, size: size)
    }
}

struct UpdateManifest: Codable, Equatable, Sendable {
    static let supportedSchemaVersion = 1

    let schemaVersion: Int
    let version: String
    let build: Int?
    let minimumSystemVersion: String?
    let publishedAt: Date?
    let releasePageURL: URL?
    let highlights: [String: [String]]
    let assets: [UpdateManifestAsset]

    func validate(currentSystemVersion: String? = nil) throws {
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw AppUpdateError.invalidManifest("unsupported schemaVersion")
        }
        guard SemanticVersion.isStable(version) else {
            throw AppUpdateError.invalidManifest("invalid version")
        }
        guard let build, build > 0 else {
            throw AppUpdateError.invalidManifest("build must be positive")
        }
        guard let minimumSystemVersion, SemanticVersion.isValid(minimumSystemVersion) else {
            throw AppUpdateError.invalidManifest("invalid minimumSystemVersion")
        }
        if let currentSystemVersion,
           SemanticVersion.compare(currentSystemVersion, minimumSystemVersion) == .orderedAscending {
            throw AppUpdateError.unsupportedSystemVersion
        }
        guard publishedAt != nil else {
            throw AppUpdateError.invalidManifest("publishedAt is missing or invalid")
        }
        if let releasePageURL, !Self.isHTTPS(releasePageURL) {
            throw AppUpdateError.invalidManifest("releasePageURL must use HTTPS")
        }
        guard !assets.isEmpty else {
            throw AppUpdateError.invalidManifest("assets is empty")
        }

        var identities = Set<String>()
        for asset in assets {
            guard Self.isHTTPS(asset.url) else {
                throw AppUpdateError.invalidManifest("asset URL must use HTTPS")
            }
            guard Self.isAllowedAssetURL(asset.url, provider: asset.provider) else {
                throw AppUpdateError.invalidManifest("asset provider does not match its URL")
            }
            let lowercaseHex = Set("0123456789abcdef")
            guard asset.sha256.count == 64,
                  asset.sha256.allSatisfy({ lowercaseHex.contains($0) })
            else {
                throw AppUpdateError.invalidManifest("sha256 must be lowercase hexadecimal")
            }
            guard asset.size > 0 else {
                throw AppUpdateError.invalidManifest("asset size must be positive")
            }
            let identity = "\(asset.provider.rawValue)|\(asset.url.absoluteString)"
            guard identities.insert(identity).inserted else {
                throw AppUpdateError.invalidManifest("duplicate asset")
            }
        }
    }

    func asAvailableUpdate(
        source: UpdateMetadataSource,
        language: AppLanguage
    ) -> AvailableUpdate {
        let languageKey = language == .simplifiedChinese ? "zh-Hans" : "en"
        let localized = highlights[languageKey] ?? highlights["en"] ?? highlights.values.first ?? []
        return AvailableUpdate(
            version: version,
            build: build,
            minimumSystemVersion: minimumSystemVersion,
            publishedAt: publishedAt,
            localizedHighlights: localized,
            releasePageURL: releasePageURL,
            assets: assets.map { $0.asUpdateAsset() },
            metadataSource: source
        )
    }

    private static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil
    }

    private static func isAllowedAssetURL(_ url: URL, provider: UpdateAsset.Provider) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        switch provider {
        case .gitee:
            return host == "gitee.com" || host.hasSuffix(".gitee.com")
        case .github:
            return [
                "github.com",
                "objects.githubusercontent.com",
                "github-releases.githubusercontent.com"
            ].contains(host)
        case .other:
            return false
        }
    }
}

enum UpdateManifestCodec {
    /// Manifest integrity is checked with HTTPS, strict schema validation and
    /// the SHA-256 metadata for each downloaded asset. This release does not
    /// add an independent manifest signature; trust therefore also depends on
    /// repository account security and the existing downloaded-app checks.
    static func decodeAndValidate(jsonData: Data) throws -> UpdateManifest {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let manifest = try decoder.decode(UpdateManifest.self, from: jsonData)
            let systemVersion = ProcessInfo.processInfo.operatingSystemVersion
            let currentSystemVersion = "\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)"
            try manifest.validate(currentSystemVersion: currentSystemVersion)
            return manifest
        } catch let error as AppUpdateError {
            throw error
        } catch {
            throw AppUpdateError.invalidManifest(error.localizedDescription)
        }
    }
}

struct UpdateEndpoint: Equatable, Sendable {
    let provider: UpdateAsset.Provider
    let manifestURL: URL
    let automaticTimeout: TimeInterval

    static let giteeManifest = UpdateEndpoint(
        provider: .gitee,
        manifestURL: URL(string: "https://gitee.com/yangchen716/yuangui/raw/main/updates/latest.json")!,
        automaticTimeout: 6
    )

    static let githubManifest = UpdateEndpoint(
        provider: .github,
        manifestURL: URL(string: "https://raw.githubusercontent.com/YangChen-cn/yuangui/main/updates/latest.json")!,
        automaticTimeout: 8
    )

}

struct UpdateManifestHedgeConfiguration: Equatable, Sendable {
    let giteeStartDelay: Duration
    let githubPrimaryDeadline: Duration

    static let production = UpdateManifestHedgeConfiguration(
        giteeStartDelay: .seconds(2),
        githubPrimaryDeadline: .seconds(5)
    )
}

protocol UpdateSourceFetching: Sendable {
    func fetchManifest(endpoint: UpdateEndpoint, timeout: TimeInterval) async throws -> AvailableUpdate
    func fetchGitHubRelease(timeout: TimeInterval) async throws -> AvailableUpdate
    func fetchGitHubRelease(timeout: TimeInterval, language: AppLanguage) async throws -> AvailableUpdate
}

extension UpdateSourceFetching {
    func fetchGitHubRelease(timeout: TimeInterval, language: AppLanguage) async throws -> AvailableUpdate {
        try await fetchGitHubRelease(timeout: timeout)
    }
}

enum UpdateHighlightExtractor {
    static func highlights(from body: String, limit: Int = 2) -> [String] {
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let rows = ReleaseNoteRow.parse(body)
        let bullets = rows.filter { $0.kind == .bullet }.map(\.text)
        let candidates = bullets.isEmpty ? rows.filter { $0.kind == .paragraph }.map(\.text) : bullets
        return candidates.compactMap(clean).prefix(limit).map { String($0) }
    }

    private static func clean(_ value: String) -> String? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "**", with: "")
        text = text.replacingOccurrences(of: "__", with: "")
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: #"^[-*+•]\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"^\d+[.)]\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"#{1,6}\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
