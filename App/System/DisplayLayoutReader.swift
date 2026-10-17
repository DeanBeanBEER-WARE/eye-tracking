import AppKit
import CoreGraphics
import GazeKit

enum DisplayLayoutReader {
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

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    @MainActor
    static func name(of id: CGDirectDisplayID) -> String {
        NSScreen.screens.first { displayID(of: $0) == id }?.localizedName ?? String(id)
    }
}
