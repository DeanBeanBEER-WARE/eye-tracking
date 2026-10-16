/// A command of the status menu.
public enum MenuCommand: Equatable, Sendable {
    /// Switches gaze control of the pointer on or off.
    case toggleGazeControl

    /// Starts the calibration.
    case calibrate

    /// Shows or hides the live gaze dot.
    case toggleGazeDot

    /// Shows or hides the camera preview window.
    case togglePreview

    /// Switches tracking to another camera.
    case selectCamera(String)

    /// Checks GitHub for a newer release and reports the outcome.
    case checkForUpdates

    /// Installs the newer release found by the last check.
    case installUpdate

    /// Opens the log file.
    case showLog

    /// Quits the app, which ends every override.
    case quit
}

/// The text of a menu entry; the app turns it into a localized title.
public enum MenuLabel: Equatable, Sendable {
    /// The app name with the installed version.
    case version(String)

    /// "Gaze control".
    case gazeControl

    /// "Calibrate…".
    case calibrate

    /// "Calibrating…", shown while a calibration runs.
    case calibrating

    /// "Show gaze point".
    case gazeDot

    /// "Camera preview".
    case preview

    /// "Camera", the title of the camera submenu.
    case camera

    /// The name of a camera.
    case cameraDevice(String)

    /// "Check for updates".
    case checkForUpdates

    /// "Checking for updates", shown while a check runs.
    case checkingForUpdates

    /// "Install update to version", with the display version of the release.
    case installUpdate(String)

    /// "Show log".
    case showLog

    /// "Quit".
    case quit
}

/// One clickable or disabled entry of the status menu.
public struct MenuItem: Equatable, Sendable {
    /// The text of the entry.
    public var label: MenuLabel

    /// The command, or `nil` for a disabled entry.
    public var command: MenuCommand?

    /// The key equivalent shown next to the entry, empty for none.
    public var keyEquivalent: String

    /// Whether the entry shows a check mark.
    public var isChecked: Bool

    /// Creates an entry.
    ///
    /// - Parameters:
    ///   - label: The text of the entry.
    ///   - command: The command, or `nil` for a disabled entry.
    ///   - keyEquivalent: The key equivalent, empty for none.
    ///   - isChecked: Whether the entry shows a check mark.
    public init(
        _ label: MenuLabel, command: MenuCommand? = nil, keyEquivalent: String = "", isChecked: Bool = false
    ) {
        self.label = label
        self.command = command
        self.keyEquivalent = keyEquivalent
        self.isChecked = isChecked
    }
}

/// A node of the status menu.
public indirect enum MenuNode: Equatable, Sendable {
    /// An entry.
    case item(MenuItem)

    /// A submenu with its title and entries.
    case submenu(MenuLabel, [MenuNode])

    /// A separator line.
    case separator
}

/// A camera as offered in the camera submenu.
public struct CameraChoice: Equatable, Sendable {
    /// The camera identifier.
    public var id: String

    /// The camera name.
    public var name: String

    /// Whether tracking uses this camera.
    public var isSelected: Bool

    /// Creates a choice.
    ///
    /// - Parameters:
    ///   - id: The camera identifier.
    ///   - name: The camera name.
    ///   - isSelected: Whether tracking uses this camera.
    public init(id: String, name: String, isSelected: Bool) {
        self.id = id
        self.name = name
        self.isSelected = isSelected
    }
}

/// What the status menu shows.
public struct MenuState: Equatable, Sendable {
    /// The installed version.
    public var version: String

    /// The display version of a newer release found by the last check, if any.
    public var availableUpdate: String?

    /// Whether an update check is running.
    public var isCheckingForUpdates: Bool

    /// Whether the camera preview window is open.
    public var isPreviewVisible: Bool

    /// The available cameras.
    public var cameras: [CameraChoice]

    /// Whether a calibration for the current displays exists.
    public var hasCalibration: Bool

    /// Whether a calibration runs.
    public var isCalibrating: Bool

    /// Whether the live gaze dot is shown.
    public var isGazeDotVisible: Bool

    /// Whether gaze control of the pointer is on.
    public var isGazeControlOn: Bool

    /// Creates a state.
    ///
    /// - Parameters:
    ///   - version: The installed version.
    ///   - availableUpdate: The display version of a newer release, if any.
    ///   - isCheckingForUpdates: Whether an update check is running.
    ///   - isPreviewVisible: Whether the camera preview window is open.
    ///   - cameras: The available cameras.
    ///   - hasCalibration: Whether a calibration for the current displays exists.
    ///   - isCalibrating: Whether a calibration runs.
    ///   - isGazeDotVisible: Whether the live gaze dot is shown.
    ///   - isGazeControlOn: Whether gaze control of the pointer is on.
    public init(
        version: String,
        availableUpdate: String? = nil,
        isCheckingForUpdates: Bool = false,
        isPreviewVisible: Bool = false,
        cameras: [CameraChoice] = [],
        hasCalibration: Bool = false,
        isCalibrating: Bool = false,
        isGazeDotVisible: Bool = false,
        isGazeControlOn: Bool = false
    ) {
        self.version = version
        self.availableUpdate = availableUpdate
        self.isCheckingForUpdates = isCheckingForUpdates
        self.isPreviewVisible = isPreviewVisible
        self.cameras = cameras
        self.hasCalibration = hasCalibration
        self.isCalibrating = isCalibrating
        self.isGazeDotVisible = isGazeDotVisible
        self.isGazeControlOn = isGazeControlOn
    }
}

/// Builds the status menu from the app state.
public enum MenuModel {
    /// Builds the menu nodes in display order.
    ///
    /// - Parameter state: The app state.
    /// - Returns: The nodes of the status menu.
    public static func build(state: MenuState) -> [MenuNode] {
        var nodes: [MenuNode] = [.item(MenuItem(.version(state.version))), .separator]
        let canUseGaze = state.hasCalibration && !state.isCalibrating
        // Gaze control can always be switched off, so a broken state never locks the user in.
        let canToggleControl = canUseGaze || state.isGazeControlOn
        nodes.append(
            .item(
                MenuItem(
                    .gazeControl, command: canToggleControl ? .toggleGazeControl : nil, isChecked: state.isGazeControlOn
                )))
        if state.isCalibrating {
            nodes.append(.item(MenuItem(.calibrating)))
        } else {
            nodes.append(.item(MenuItem(.calibrate, command: .calibrate)))
        }
        nodes.append(
            .item(
                MenuItem(
                    .gazeDot, command: canUseGaze ? .toggleGazeDot : nil, isChecked: state.isGazeDotVisible)))
        nodes.append(.separator)
        nodes.append(.item(MenuItem(.preview, command: .togglePreview, isChecked: state.isPreviewVisible)))
        if !state.cameras.isEmpty {
            let cameras = state.cameras.map { camera in
                MenuNode.item(
                    MenuItem(
                        .cameraDevice(camera.name), command: .selectCamera(camera.id), isChecked: camera.isSelected))
            }
            nodes.append(.submenu(.camera, cameras))
        }
        nodes.append(.separator)
        if let update = state.availableUpdate {
            nodes.append(.item(MenuItem(.installUpdate(update), command: .installUpdate)))
        }
        if state.isCheckingForUpdates {
            nodes.append(.item(MenuItem(.checkingForUpdates)))
        } else {
            nodes.append(.item(MenuItem(.checkForUpdates, command: .checkForUpdates)))
        }
        nodes.append(.separator)
        nodes.append(.item(MenuItem(.showLog, command: .showLog)))
        nodes.append(.item(MenuItem(.quit, command: .quit, keyEquivalent: "q")))
        return nodes
    }
}
