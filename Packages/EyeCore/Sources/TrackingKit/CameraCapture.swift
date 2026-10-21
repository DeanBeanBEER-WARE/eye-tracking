@preconcurrency import AVFoundation
import CoreKit
import Foundation

public struct CameraDevice: Equatable, Sendable {
    public var id: String

    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum CameraError: Error, Equatable, Sendable, CustomStringConvertible {
    case accessDenied

    case noDevice

    case deviceUnavailable

    case configurationFailed(String)

    public var description: String {
        switch self {
        case .accessDenied: "camera access denied"
        case .noDevice: "no camera available"
        case .deviceUnavailable: "the selected camera is not connected"
        case .configurationFailed(let message): "camera configuration failed: \(message)"
        }
    }
}

public enum CameraEvent: Equatable, Sendable {
    case interrupted(String)

    case interruptionEnded

    case runtimeError(String)

    case disconnected

    case suspended(Bool)
}

public final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public static let frameRate: Int32 = 30

    public static let preferredSize = (width: 1280, height: 720)

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue: DispatchQueue
    private let controlQueue = DispatchQueue(label: "com.deanbean.eyetracking.camera-control")
    private let handler: @Sendable (CVPixelBuffer, TimeInterval) -> Void
    private let log = Log("Camera")
    private var device: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var observations: [NSKeyValueObservation] = []
    private var notificationTokens: [NSObjectProtocol] = []
    private var rotationOffset = 0
    private var appliedRotation: CGFloat?

    public var eventHandler: (@Sendable (CameraEvent) -> Void)?

    public init(queue: DispatchQueue, handler: @escaping @Sendable (CVPixelBuffer, TimeInterval) -> Void) {
        self.queue = queue
        self.handler = handler
        super.init()
    }

    public static func devices() -> [CameraDevice] {
        discovery().devices.map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

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

    @discardableResult
    public func start(deviceID: String?, rotationOffset: Int = 0) throws(CameraError) -> String {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            throw .accessDenied
        }
        let devices = Self.discovery().devices
        let found: AVCaptureDevice?
        if let deviceID {
            found = devices.first { $0.uniqueID == deviceID }
            guard found != nil else {
                throw .deviceUnavailable
            }
        } else {
            found = devices.first { $0.deviceType == .builtInWideAngleCamera } ?? devices.first
        }
        guard let device = found else {
            throw .noDevice
        }
        try configure(device)
        selectFormat(device)
        self.device = device
        controlQueue.sync {
            self.rotationOffset = rotationOffset
            self.appliedRotation = nil
        }
        observe(device)
        session.startRunning()
        let size = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
        log.info(
            "Camera started: \(device.localizedName) (\(device.deviceType.rawValue), \(size.width)x\(size.height), "
                + "suspended \(device.isSuspended)).")
        return device.localizedName
    }

    public func stop() {
        removeObservers()
        device = nil
        guard session.isRunning else {
            return
        }
        session.stopRunning()
        log.info("Camera stopped.")
    }

    public func setRotationOffset(_ offset: Int) {
        controlQueue.async {
            self.rotationOffset = offset
            self.applyRotation()
        }
    }

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

    private func selectFormat(_ device: AVCaptureDevice) {
        let rate = Double(Self.frameRate)
        let candidates = device.formats.filter { format in
            format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= rate && $0.minFrameRate <= rate }
        }
        let best = candidates.min { lhs, rhs in
            Self.distance(lhs) < Self.distance(rhs)
        }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            if let best {
                device.activeFormat = best
                let duration = CMTime(value: 1, timescale: Self.frameRate)
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
            }
        } catch {
            log.warning("Could not configure \(device.localizedName): \(error)")
        }
    }

    private static func distance(_ format: AVCaptureDevice.Format) -> Int {
        let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let landscapeWidth = Int(max(size.width, size.height))
        let landscapeHeight = Int(min(size.width, size.height))
        return abs(landscapeWidth - preferredSize.width) + abs(landscapeHeight - preferredSize.height)
    }

    private func observe(_ device: AVCaptureDevice) {
        removeObservers()
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        observations.append(
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial]) { [weak self] _, _ in
                guard let capture = self else {
                    return
                }
                capture.controlQueue.async {
                    capture.applyRotation()
                }
            })
        observations.append(
            device.observe(\.isSuspended, options: [.new]) { [weak self] device, _ in
                let suspended = device.isSuspended
                self?.log.info("\(device.localizedName) suspended: \(suspended).")
                self?.eventHandler?(.suspended(suspended))
            })
        let center = NotificationCenter.default
        notificationTokens.append(
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) {
                [weak self] notification in
                let reason = notification.userInfo.map { "\($0)" } ?? "unknown reason"
                self?.log.warning("Camera session interrupted: \(reason).")
                self?.eventHandler?(.interrupted(reason))
            })
        notificationTokens.append(
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) {
                [weak self] _ in
                self?.log.info("Camera session interruption ended.")
                self?.eventHandler?(.interruptionEnded)
            })
        notificationTokens.append(
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) {
                [weak self] notification in
                let error = notification.userInfo?[AVCaptureSessionErrorKey].map { "\($0)" } ?? "unknown error"
                self?.log.error("Camera session error: \(error).")
                self?.eventHandler?(.runtimeError(error))
            })
        notificationTokens.append(
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: device, queue: nil) {
                [weak self] _ in
                self?.log.warning("Camera disconnected.")
                self?.eventHandler?(.disconnected)
            })
    }

    private func removeObservers() {
        for observation in observations {
            observation.invalidate()
        }
        observations.removeAll()
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
        rotationCoordinator = nil
    }

    private func applyRotation() {
        guard let connection = output.connection(with: .video) else {
            return
        }
        let horizon = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 0
        let angle = (horizon + CGFloat(rotationOffset)).truncatingRemainder(dividingBy: 360)
        guard angle != appliedRotation else {
            return
        }
        guard connection.isVideoRotationAngleSupported(angle) else {
            log.warning("Rotation \(Int(angle)) degrees is not supported by this camera.")
            return
        }
        connection.videoRotationAngle = angle
        appliedRotation = angle
        log.info("Video rotation \(Int(angle)) degrees (horizon \(Int(horizon)), offset \(rotationOffset)).")
    }

    private static func discovery() -> AVCaptureDevice.DiscoverySession {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
    }
}
