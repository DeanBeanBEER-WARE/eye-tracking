import CoreKit
import Foundation

enum MenuStrings {
    static func text(_ label: MenuLabel) -> String {
        switch label {
        case .version(let version):
            String(localized: "menu.version \(AppInfo.displayName) \(version)")
        case .gazeControl:
            String(localized: "menu.gaze_control")
        case .snapping:
            String(localized: "menu.snapping")
        case .calibrate:
            String(localized: "menu.calibrate")
        case .calibrating:
            String(localized: "menu.calibrating")
        case .gazeDot:
            String(localized: "menu.gaze_dot")
        case .preview:
            String(localized: "menu.preview")
        case .camera:
            String(localized: "menu.camera")
        case .cameraDevice(let name):
            name
        case .checkForUpdates:
            String(localized: "menu.check_updates")
        case .checkingForUpdates:
            String(localized: "menu.checking_updates")
        case .installUpdate(let version):
            String(localized: "menu.install_update \(version)")
        case .showLog:
            String(localized: "menu.show_log")
        case .quit:
            String(localized: "menu.quit")
        }
    }
}
