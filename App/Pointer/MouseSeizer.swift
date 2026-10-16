import CoreKit
import Foundation
import IOKit.hid
import PointerKit

/// Takes exclusive access to the external mice, so their motion no longer reaches the system, and forwards their
/// input values. The built-in trackpad, other trackpads and virtual devices (Karabiner) are never touched.
///
/// The kernel ends the exclusive access when the process exits, also after a crash or a forced kill.
@MainActor
final class MouseSeizer {
    private static let seizeOptions = IOOptionBits(kIOHIDOptionsTypeSeizeDevice)

    private let log = Log("Mouse")
    private let manager: IOHIDManager
    private var seized: [IOHIDDevice] = []
    private var refused: Set<String> = []

    /// Whether the seizer takes the matching mice, including mice connected later.
    private(set) var isEngaged = false

    /// Receives the input of the seized mice on the main thread.
    var onInput: ((MouseInput) -> Void)?

    /// Called when the system refuses a mouse for lack of a permission.
    var onPermissionRefused: (() -> Void)?

    /// Whether a matching mouse could not be taken over.
    var hasRefusedDevices: Bool {
        !refused.isEmpty
    }

    /// Creates the seizer; nothing is seized until ``engage()``.
    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Int] = [
            kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDPrimaryUsageKey: kHIDUsage_GD_Mouse,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(
            manager,
            { context, _, _, device in
                guard let context else {
                    return
                }
                let seizer = Unmanaged<MouseSeizer>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated {
                    seizer.deviceAppeared(device)
                }
            }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(
            manager,
            { context, _, _, device in
                guard let context else {
                    return
                }
                let seizer = Unmanaged<MouseSeizer>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated {
                    seizer.deviceDisappeared(device)
                }
            }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    }

    /// Seizes all matching mice now and every matching mouse connected later.
    func engage() {
        guard !isEngaged else {
            return
        }
        isEngaged = true
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        for device in devices {
            seize(device)
        }
        if seized.isEmpty {
            log.info("No external mouse to take over.")
        }
    }

    /// Tries again to take the mice that were refused, for example after a permission was granted.
    func retry() {
        guard isEngaged else {
            return
        }
        let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
        for device in devices {
            seize(device)
        }
    }

    /// Gives all seized mice back to the system.
    func release() {
        guard isEngaged else {
            return
        }
        isEngaged = false
        for device in seized {
            IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDDeviceClose(device, Self.seizeOptions)
        }
        if !seized.isEmpty {
            log.info("Released \(seized.count) mouse interface(s).")
        }
        seized.removeAll()
    }

    private func deviceAppeared(_ device: IOHIDDevice) {
        if isEngaged {
            seize(device)
        }
    }

    private func deviceDisappeared(_ device: IOHIDDevice) {
        guard let index = seized.firstIndex(where: { $0 === device }) else {
            return
        }
        seized.remove(at: index)
        log.info("\(Self.describe(device)) disconnected.")
    }

    private func seize(_ device: IOHIDDevice) {
        guard Self.isExternalMouse(device), !seized.contains(where: { $0 === device }) else {
            return
        }
        let name = Self.describe(device)
        let result = IOHIDDeviceOpen(device, Self.seizeOptions)
        guard result == kIOReturnSuccess else {
            if refused.insert(name).inserted {
                log.error("Could not take over \(name): IOReturn 0x\(String(UInt32(bitPattern: result), radix: 16)).")
                if result == kIOReturnNotPermitted || result == kIOReturnNotPrivileged {
                    onPermissionRefused?()
                }
            }
            return
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputValueCallback(
            device,
            { context, _, _, value in
                guard let context else {
                    return
                }
                let element = IOHIDValueGetElement(value)
                let input = MouseInput.decode(
                    usagePage: IOHIDElementGetUsagePage(element), usage: IOHIDElementGetUsage(element),
                    value: IOHIDValueGetIntegerValue(value))
                guard let input else {
                    return
                }
                let seizer = Unmanaged<MouseSeizer>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated {
                    seizer.onInput?(input)
                }
            }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        seized.append(device)
        refused.remove(name)
        log.info("Took over \(name).")
    }

    /// Whether a device is an external mouse that may be seized.
    private static func isExternalMouse(_ device: IOHIDDevice) -> Bool {
        let builtIn = (property(device, kIOHIDBuiltInKey) as? Bool) ?? false
        let transport = (property(device, kIOHIDTransportKey) as? String) ?? ""
        let product = (property(device, kIOHIDProductKey) as? String) ?? ""
        let vendor = (property(device, kIOHIDVendorIDKey) as? Int) ?? 0
        let internalTransports: Set<String> = ["FIFO", "SPI", "Virtual"]
        let excludedNames = ["Karabiner", "Trackpad", "Virtual"]
        // 0x16C0 is the vendor of the Karabiner virtual HID devices.
        return !builtIn && !internalTransports.contains(transport) && vendor != 0x16C0
            && !excludedNames.contains { product.localizedCaseInsensitiveContains($0) }
    }

    private static func describe(_ device: IOHIDDevice) -> String {
        let product = (property(device, kIOHIDProductKey) as? String) ?? "Unknown"
        let vendor = (property(device, kIOHIDVendorIDKey) as? Int) ?? 0
        let productID = (property(device, kIOHIDProductIDKey) as? Int) ?? 0
        let transport = (property(device, kIOHIDTransportKey) as? String) ?? "?"
        return "\(product) (\(vendor):\(productID), \(transport))"
    }

    private static func property(_ device: IOHIDDevice, _ key: String) -> Any? {
        IOHIDDeviceGetProperty(device, key as CFString)
    }
}
