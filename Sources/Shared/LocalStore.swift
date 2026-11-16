import Foundation

public enum LocalStore {
    public static func applicationSupportFile(named filename: String) throws -> URL {
        let manager = FileManager.default
        let directory = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "DesktopPush", directoryHint: .isDirectory)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: filename)
    }

    public static func load<Value: Decodable>(_ type: Value.Type, from filename: String, fallback: Value) -> Value {
        guard let url = try? applicationSupportFile(named: filename),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder.desktopPush.decode(Value.self, from: data) else { return fallback }
        return value
    }

    public static func save<Value: Encodable>(_ value: Value, to filename: String) throws {
        let url = try applicationSupportFile(named: filename)
        let data = try JSONEncoder.desktopPush.encode(value)
        try data.write(to: url, options: .atomic)
    }
}

public extension JSONEncoder {
    static let desktopPush: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

public extension JSONDecoder {
    static let desktopPush: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
