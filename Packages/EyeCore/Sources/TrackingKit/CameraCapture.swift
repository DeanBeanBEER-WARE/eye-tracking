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

    case configurationFailed(String)

    public var description: String {
        switch self {
        case .accessDenied: "camera access denied"
        case .noDevice: "no camera available"
        case .configurationFailed(let message): "camera configuration failed: \(message)"
        }
    }
}

public final class CameraCapture: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    public static let frameRate: Int32 = 30

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue: DispatchQueue
    private let handler: @Sendable (CVPixelBuffer, TimeInterval) -> Void
    private let log = Log("Camera")

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
    public func start(deviceID: String?) throws(CameraError) -> String {
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
        log.info("Camera started: \(device.localizedName) (\(device.deviceType.rawValue)).")
        return device.localizedName
    }

    public func stop() {
        guard session.isRunning else {
            return
        }
        session.stopRunning()
        log.info("Camera stopped.")
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
