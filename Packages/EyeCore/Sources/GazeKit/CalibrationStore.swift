import CoreKit
import Foundation

public struct CalibrationStore: Sendable {
    public let fileURL: URL

    private let log: Log

    public init(
        fileURL: URL = Paths.standard.supportDirectory.appendingPathComponent("calibration.json"),
        log: Log = Log("Calibration")
    ) {
        self.fileURL = fileURL
        self.log = log
    }

    public func load() -> GazeModel? {
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(GazeModel.self, from: data)
        } catch {
            log.warning("Unreadable calibration \(fileURL.path): \(error)")
            return nil
        }
    }

    public func save(_ model: GazeModel) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(model)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
