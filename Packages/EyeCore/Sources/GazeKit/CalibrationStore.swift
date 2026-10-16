import CoreKit
import Foundation

/// Loads and saves the fitted gaze model as JSON.
public struct CalibrationStore: Sendable {
    /// The calibration file.
    public let fileURL: URL

    private let log: Log

    /// Creates the store.
    ///
    /// - Parameters:
    ///   - fileURL: The calibration file.
    ///   - log: The logger.
    public init(
        fileURL: URL = Paths.standard.supportDirectory.appendingPathComponent("calibration.json"),
        log: Log = Log("Calibration")
    ) {
        self.fileURL = fileURL
        self.log = log
    }

    /// Loads the saved model.
    ///
    /// - Returns: The model, or `nil` if none is saved or the file cannot be read.
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

    /// Saves a model atomically.
    ///
    /// - Parameter model: The model.
    /// - Throws: The encoding or file system error.
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
