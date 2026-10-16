@preconcurrency import AVFoundation
import CoreKit
import Foundation

/// A camera the app can track with.
public struct CameraDevice: Equatable, Sendable {
    /// The stable AVFoundation unique identifier.
    public var id: String

    /// The user-facing name.
    public var name: String

    /// Creates a device description.
    ///
    /// - Parameters:
    ///   - id: The unique identifier.
    ///   - name: The user-facing name.
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A camera that could not be started.
public enum CameraError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The user has not granted camera access.
    case accessDenied

    /// No camera is available.
    case noDevice

    /// The camera could not be configured.
    case configurationFailed(String)

    /// A short description for the log.
    public var description: String {
        switch self {
        case .accessDenied: "camera access denied"
        case .noDevice: "no camera available"
        case .configurationFailed(let message): "camera configuration failed: \(message)"
        }
    }
}

/// Captures BGRA frames from a camera at up to 30 fps and hands them to a handler on a serial queue.
public final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// The preferred frame rate.
    public static let frameRate: Int32 = 30

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue: DispatchQueue
    private let handler: @Sendable (CVPixelBuffer, TimeInterval) -> Void
    private let log = Log("Camera")

    /// Creates the capture; nothing runs until ``start(deviceID:)``.
    ///
    /// - Parameters:
    ///   - queue: The serial queue the frames are delivered on.
    ///   - handler: Receives every frame with its capture time in seconds of the host clock.
    public init(queue: DispatchQueue, handler: @escaping @Sendable (CVPixelBuffer, TimeInterval) -> Void) {
        self.queue = queue
        self.handler = handler
        super.init()
    }

    /// The cameras that can deliver video.
    ///
    /// - Returns: The built-in, external and Continuity cameras.
    public static func devices() -> [CameraDevice] {
        discovery().devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// Whether camera access is granted, asking the user on the first call.
    ///
    /// - Returns: `true` if the app may use the camera.
    public static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    /// Configures and starts the session; blocks while the camera powers up, so call it off the main thread.
    ///
    /// - Parameter deviceID: The camera to use, or `nil` for the built-in camera.
    /// - Throws: ``CameraError`` if the camera cannot be started.
    public func start(deviceID: String?) throws(CameraError) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw .accessDenied
        }
        let devices = Self.discovery().devices
        let device =
            devices.first { $0.uniqueID == deviceID }
            ?? devices.first { $0.deviceType == .builtInWideAngleCamera } ?? devices.first
        guard let device else {
            throw .noDevice
        }
        try configure(device)
        limitFrameRate(device)
        session.startRunning()
        log.info("Camera started: \(device.localizedName).")
    }

    /// Stops the session and turns the camera off.
    public func stop() {
        guard session.isRunning else {
            return
        }
        session.stopRunning()
        log.info("Camera stopped.")
    }

    /// Delivers a captured frame to the handler.
    ///
    /// - Parameters:
    ///   - output: The video output.
    ///   - sampleBuffer: The frame.
    ///   - connection: The connection the frame arrived on.
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        handler(pixelBuffer, time.isFinite ? time : ProcessInfo.processInfo.systemUptime)
    }

    private func configure(_ device: AVCaptureDevice) throws(CameraError) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        for input in session.inputs {
            session.removeInput(input)
        }
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw .configurationFailed(error.localizedDescription)
        }
        guard session.canAddInput(input) else {
            throw .configurationFailed("input not accepted")
        }
        session.addInput(input)
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        guard !session.outputs.contains(output) else {
            return
        }
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            throw .configurationFailed("output not accepted")
        }
        session.addOutput(output)
    }

    private func limitFrameRate(_ device: AVCaptureDevice) {
        let duration = CMTime(value: 1, timescale: Self.frameRate)
        let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.maxFrameRate >= Double(Self.frameRate) && $0.minFrameRate <= Double(Self.frameRate)
        }
        guard supported else {
            return
        }
        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            log.warning("Could not set the frame rate: \(error)")
        }
    }

    private static func discovery() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
    }
}
