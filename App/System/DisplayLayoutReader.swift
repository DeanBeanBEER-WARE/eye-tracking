import AppKit
import CoreGraphics
import GazeKit

/// Reads the current display arrangement from CoreGraphics.
enum DisplayLayoutReader {
    /// The active displays without mirrors, in CoreGraphics global coordinates.
    ///
    /// - Returns: The layout.
    static func current() -> ScreenLayout {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return ScreenLayout(displays: [])
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return ScreenLayout(displays: [])
        }
        let displays = ids.prefix(Int(count))
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { id in
                DisplayInfo(
                    id: id, frame: CGDisplayBounds(id), physicalSize: CGDisplayScreenSize(id),
                    isBuiltIn: CGDisplayIsBuiltin(id) != 0)
            }
        return ScreenLayout(displays: Array(displays))
    }

    /// The display identifier of a screen.
    ///
    /// - Parameter screen: The screen.
    /// - Returns: The CoreGraphics display identifier, or `nil` if the screen has none.
    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// The name of a display as the system shows it.
    ///
    /// - Parameter id: The display identifier.
    /// - Returns: The localized name, or the identifier if no screen has it.
    @MainActor
    static func name(of id: CGDirectDisplayID) -> String {
        NSScreen.screens.first { displayID(of: $0) == id }?.localizedName ?? String(id)
    }
}
