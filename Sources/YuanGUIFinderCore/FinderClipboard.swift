import Foundation

public enum FinderClipboardFormatter {
    public static func pathString(for urls: [URL]) -> String? {
        let paths = urls.compactMap(FinderTargetResolver.normalizedFileURL).map(\.path)
        return paths.isEmpty ? nil : paths.joined(separator: "\n")
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
