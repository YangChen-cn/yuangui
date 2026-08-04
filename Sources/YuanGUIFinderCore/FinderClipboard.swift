import Foundation

public enum FinderClipboardFormatter {
    public static func pathString(for urls: [URL]) -> String? {
        let paths = urls.compactMap(FinderTargetResolver.normalizedFileURL).map(\.path)
        return paths.isEmpty ? nil : paths.joined(separator: "\n")
    }

    /// The last path component of each URL, one per line.
    public static func fileNameString(for urls: [URL]) -> String? {
        let names = urls.compactMap(FinderTargetResolver.normalizedFileURL).map(\.lastPathComponent)
        return names.isEmpty ? nil : names.joined(separator: "\n")
    }

    /// Each path wrapped in single quotes with embedded quotes escaped, one
    /// per line — safe to paste into a shell as positional arguments.
    public static func terminalArgumentString(for urls: [URL]) -> String? {
        let quoted = urls
            .compactMap(FinderTargetResolver.normalizedFileURL)
            .map { shellQuote($0.path) }
        return quoted.isEmpty ? nil : quoted.joined(separator: "\n")
    }

    /// POSIX single-quote escaping: `'` becomes `'\''` inside a `'…'` pair.
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum FinderCutPayloadCodec {
    public static func encode(_ payload: FinderCutPayload) throws -> Data {
        try JSONEncoder().encode(payload)
    }

    public static func decode(_ data: Data?) -> FinderCutPayload? {
        guard let data,
              let payload = try? JSONDecoder().decode(FinderCutPayload.self, from: data),
              !payload.items.isEmpty else { return nil }
        return payload
    }
}
