import Accelerate
import CoreGraphics
import CoreKit
import CoreVideo
import Foundation
import VideoToolbox
import os

/// The live numbers of the tracking pipeline.
public struct TrackingStatistics: Equatable, Sendable {
    /// The smoothed camera frame rate.
    public var framesPerSecond: Double

    /// The smoothed MediaPipe inference time per frame in milliseconds.
    public var inferenceMilliseconds: Double

    /// Whether the last frame contained a face.
    public var faceFound: Bool

    /// Creates statistics.
    ///
    /// - Parameters:
    ///   - framesPerSecond: The frame rate.
    ///   - inferenceMilliseconds: The inference time in milliseconds.
    ///   - faceFound: Whether the last frame contained a face.
    public init(framesPerSecond: Double = 0, inferenceMilliseconds: Double = 0, faceFound: Bool = false) {
        self.framesPerSecond = framesPerSecond
        self.inferenceMilliseconds = inferenceMilliseconds
        self.faceFound = faceFound
    }
}

/// The files the face landmarker needs.
public struct TrackingResources: Sendable {
    /// The path of `libmediapipe.dylib`.
    public var libraryPath: String

    /// The path of `face_landmarker.task`.
    public var modelPath: String

    /// An empty CA bundle that keeps MediaPipe's usage logging from uploading.
    public var caBundlePath: String

    /// Creates the resource description.
    ///
    /// - Parameters:
    ///   - libraryPath: The path of `libmediapipe.dylib`.
    ///   - modelPath: The path of `face_landmarker.task`.
    ///   - caBundlePath: The path of an empty CA bundle.
    public init(libraryPath: String, modelPath: String, caBundlePath: String) {
        self.libraryPath = libraryPath
        self.modelPath = modelPath
        self.caBundlePath = caBundlePath
    }
}

/// Runs camera capture and face tracking on one serial queue and hands the results to the registered handlers.
///
/// Frames that arrive while the previous one is still processed are dropped by the camera.
public final class TrackingEngine: @unchecked Sendable {
    /// The interval between two preview images.
    public static let previewInterval: TimeInterval = 1.0 / 15

    private struct Handlers {
        var observation: (@Sendable (FaceObservation?) -> Void)?
        var preview: (@Sendable (CGImage, FaceObservation?) -> Void)?
        var statistics = TrackingStatistics()
    }

    private let resources: TrackingResources
    private let queue = DispatchQueue(label: "com.deanbean.eyetracking.tracking", qos: .userInteractive)
    private let shared = OSAllocatedUnfairLock(initialState: Handlers())
    private let log = Log("Tracking")
    private var camera: CameraCapture?

    // Confined to `queue`.
    private var landmarker: FaceLandmarker?
    private var rgb: [UInt8] = []
    private var lastFrameTime: TimeInterval?
    private var lastPreviewTime: TimeInterval = 0
    private var framesPerSecond: Double = 0
    private var inferenceMilliseconds: Double = 0
    private var loggedDetectionError = false

    /// Creates the engine; nothing runs until ``start(deviceID:)``.
    ///
    /// - Parameter resources: The MediaPipe library and model.
    public init(resources: TrackingResources) {
        self.resources = resources
    }

    /// The live numbers of the pipeline.
    public var statistics: TrackingStatistics {
        shared.withLock { $0.statistics }
    }

    /// Sets the receiver of every tracking result (`nil` for a frame without a face), called on the tracking queue.
    ///
    /// - Parameter handler: The receiver, or `nil` to remove it.
    public func setObservationHandler(_ handler: (@Sendable (FaceObservation?) -> Void)?) {
        shared.withLock { $0.observation = handler }
    }

    /// Sets the receiver of preview images (at most 15 per second), called on the tracking queue.
    ///
    /// - Parameter handler: The receiver, or `nil` to stop creating preview images.
    public func setPreviewHandler(_ handler: (@Sendable (CGImage, FaceObservation?) -> Void)?) {
        shared.withLock { $0.preview = handler }
    }

    /// Loads MediaPipe on first use and starts the camera; blocks, so call it off the main thread.
    ///
    /// - Parameter deviceID: The camera to use, or `nil` for the built-in camera.
    /// - Throws: ``FaceLandmarkerError`` or ``CameraError``.
    public func start(deviceID: String?) throws {
        try queue.sync {
            if landmarker == nil {
                landmarker = try FaceLandmarker(
                    libraryPath: resources.libraryPath,
                    modelPath: resources.modelPath,
                    caBundlePath: resources.caBundlePath
                )
                log.info("MediaPipe face landmarker loaded.")
            }
            lastFrameTime = nil
        }
        let camera =
            self.camera
            ?? CameraCapture(queue: queue) { [weak self] buffer, time in
                self?.process(buffer, time: time)
            }
        self.camera = camera
        try camera.start(deviceID: deviceID)
    }

    /// Stops the camera; MediaPipe stays loaded for the next start.
    public func stop() {
        camera?.stop()
        shared.withLock { $0.statistics = TrackingStatistics() }
    }

    private func process(_ buffer: CVPixelBuffer, time: TimeInterval) {
        guard let landmarker else {
            return
        }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard convert(buffer, width: width, height: height) else {
            return
        }
        let started = DispatchTime.now().uptimeNanoseconds
        var observation: FaceObservation?
        do {
            observation = try rgb.withUnsafeBufferPointer { pixels throws(FaceLandmarkerError) in
                try landmarker.detect(rgb: pixels.baseAddress!, width: width, height: height, timestamp: time)
            }
            loggedDetectionError = false
        } catch {
            if !loggedDetectionError {
                log.error("\(error)")
                loggedDetectionError = true
            }
        }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        updateStatistics(time: time, inference: elapsed, faceFound: observation != nil)
        let handlers = shared.withLock { ($0.observation, $0.preview) }
        handlers.0?(observation)
        if let preview = handlers.1, time - lastPreviewTime >= Self.previewInterval {
            lastPreviewTime = time
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
            if let image {
                preview(image, observation)
            }
        }
    }

    private func convert(_ buffer: CVPixelBuffer, width: Int, height: Int) -> Bool {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else {
            return false
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else {
            return false
        }
        if rgb.count != width * height * 3 {
            rgb = [UInt8](repeating: 0, count: width * height * 3)
        }
        var source = vImage_Buffer(
            data: base, height: vImagePixelCount(height), width: vImagePixelCount(width),
            rowBytes: CVPixelBufferGetBytesPerRow(buffer))
        let status = rgb.withUnsafeMutableBytes { bytes in
            var destination = vImage_Buffer(
                data: bytes.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width),
                rowBytes: width * 3)
            return vImageConvert_BGRA8888toRGB888(&source, &destination, vImage_Flags(kvImageNoFlags))
        }
        return status == kvImageNoError
    }

    private func updateStatistics(time: TimeInterval, inference: Double, faceFound: Bool) {
        if let lastFrameTime, time > lastFrameTime {
            let rate = 1 / (time - lastFrameTime)
            framesPerSecond = framesPerSecond == 0 ? rate : framesPerSecond * 0.9 + rate * 0.1
        }
        lastFrameTime = time
        inferenceMilliseconds = inferenceMilliseconds == 0 ? inference : inferenceMilliseconds * 0.9 + inference * 0.1
        let statistics = TrackingStatistics(
            framesPerSecond: framesPerSecond, inferenceMilliseconds: inferenceMilliseconds, faceFound: faceFound)
        shared.withLock { $0.statistics = statistics }
    }
}
