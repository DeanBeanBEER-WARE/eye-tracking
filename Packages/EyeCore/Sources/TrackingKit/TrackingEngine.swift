import Accelerate
import CoreGraphics
import CoreKit
import CoreVideo
import Foundation
import VideoToolbox
import os

public struct TrackingStatistics: Equatable, Sendable {
    public var framesPerSecond: Double

    public var inferenceMilliseconds: Double

    public var faceFound: Bool

    public init(framesPerSecond: Double = 0, inferenceMilliseconds: Double = 0, faceFound: Bool = false) {
        self.framesPerSecond = framesPerSecond
        self.inferenceMilliseconds = inferenceMilliseconds
        self.faceFound = faceFound
    }
}

public struct TrackingResources: Sendable {
    public var libraryPath: String

    public var modelPath: String

    public var caBundlePath: String

    public init(libraryPath: String, modelPath: String, caBundlePath: String) {
        self.libraryPath = libraryPath
        self.modelPath = modelPath
        self.caBundlePath = caBundlePath
    }
}

public final class TrackingEngine: @unchecked Sendable {
    public static let previewInterval: TimeInterval = 1.0 / 15

    private struct Handlers {
        var observation: (@Sendable (FaceObservation?) -> Void)?
        var preview: (@Sendable (CGImage, FaceObservation?) -> Void)?
        var statistics = TrackingStatistics()
        var frameCount = 0
        var cameraName: String?
        var cameraEvent: (@Sendable (CameraEvent) -> Void)?
        var rotationLocked: (@Sendable (Int) -> Void)?
    }

    private let resources: TrackingResources
    private let queue = DispatchQueue(label: "com.deanbean.eyetracking.tracking", qos: .userInteractive)
    private let sessionQueue = DispatchQueue(label: "com.deanbean.eyetracking.camera-session", qos: .userInitiated)
    private let shared = OSAllocatedUnfairLock(initialState: Handlers())
    private let log = Log("Tracking")
    private var camera: CameraCapture?

    private var landmarker: FaceLandmarker?
    private var rgb: [UInt8] = []
    private var lastFrameTime: TimeInterval?
    private var lastPreviewTime: TimeInterval = 0
    private var framesPerSecond: Double = 0
    private var inferenceMilliseconds: Double = 0
    private var loggedDetectionError = false
    private var orientation = OrientationSearch()

    public init(resources: TrackingResources) {
        self.resources = resources
    }

    public var statistics: TrackingStatistics {
        shared.withLock { $0.statistics }
    }

    public var frameCount: Int {
        shared.withLock { $0.frameCount }
    }

    public var cameraName: String? {
        shared.withLock { $0.cameraName }
    }

    public func setObservationHandler(_ handler: (@Sendable (FaceObservation?) -> Void)?) {
        shared.withLock { $0.observation = handler }
    }

    public func setPreviewHandler(_ handler: (@Sendable (CGImage, FaceObservation?) -> Void)?) {
        shared.withLock { $0.preview = handler }
    }

    public func setCameraEventHandler(_ handler: (@Sendable (CameraEvent) -> Void)?) {
        shared.withLock { $0.cameraEvent = handler }
    }

    public func setRotationLockedHandler(_ handler: (@Sendable (Int) -> Void)?) {
        shared.withLock { $0.rotationLocked = handler }
    }

    public func start(deviceID: String?, rotationOffset: Int = 0) throws {
        try sessionQueue.sync {
            try startCamera(deviceID: deviceID, rotationOffset: rotationOffset)
        }
    }

    public func restart(deviceID: String?, rotationOffset: Int = 0) throws {
        try sessionQueue.sync {
            stopCamera()
            try startCamera(deviceID: deviceID, rotationOffset: rotationOffset)
        }
    }

    public func stop() {
        sessionQueue.sync {
            stopCamera()
        }
    }

    private func startCamera(deviceID: String?, rotationOffset: Int) throws {
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
            orientation = OrientationSearch(offset: rotationOffset)
        }
        let camera =
            self.camera
            ?? CameraCapture(queue: queue) { [weak self] buffer, time in
                self?.process(buffer, time: time)
            }
        camera.eventHandler = { [weak self] event in
            let handler = self?.shared.withLock { $0.cameraEvent }
            handler?(event)
        }
        self.camera = camera
        shared.withLock {
            $0.frameCount = 0
            $0.cameraName = nil
        }
        let name = try camera.start(deviceID: deviceID, rotationOffset: orientation.offset)
        shared.withLock { $0.cameraName = name }
    }

    private func stopCamera() {
        camera?.stop()
        shared.withLock {
            $0.statistics = TrackingStatistics()
            $0.frameCount = 0
            $0.cameraName = nil
        }
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
        updateOrientation(faceFound: observation != nil, time: time)
        updateStatistics(time: time, inference: elapsed, faceFound: observation != nil)
        let (handlers, firstFrame, cameraName) = shared.withLock { state in
            state.frameCount += 1
            return ((state.observation, state.preview), state.frameCount == 1, state.cameraName)
        }
        if firstFrame {
            log.info("First frame from \(cameraName ?? "the camera"): \(width)x\(height).")
        }
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

    private func updateOrientation(faceFound: Bool, time: TimeInterval) {
        let wasLocked = orientation.isLocked
        if let offset = orientation.update(faceFound: faceFound, now: time) {
            log.info("No face found; trying a rotation offset of \(offset) degrees.")
            camera?.setRotationOffset(offset)
        }
        if orientation.isLocked, !wasLocked {
            log.info("Face found with a rotation offset of \(orientation.offset) degrees.")
            let handler = shared.withLock { $0.rotationLocked }
            handler?(orientation.offset)
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
