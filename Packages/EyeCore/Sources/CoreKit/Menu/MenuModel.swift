public enum MenuCommand: Equatable, Sendable {
    case toggleGazeControl

    case toggleSnapping

    case calibrate

    case toggleGazeDot

    case togglePreview

    case selectCamera(String)

    case checkForUpdates

    case installUpdate

    case showLog

    case quit
}

public enum MenuLabel: Equatable, Sendable {
    case version(String)

    case gazeControl

    case snapping

    case calibrate

    case calibrating

    case gazeDot

    case preview

    case camera

    case cameraDevice(String)

    case checkForUpdates

    case checkingForUpdates

    case installUpdate(String)

    case showLog

    case quit
}

public struct MenuItem: Equatable, Sendable {
    public var label: MenuLabel

    public var command: MenuCommand?

    public var keyEquivalent: String

    public var isChecked: Bool

    public init(
        _ label: MenuLabel, command: MenuCommand? = nil, keyEquivalent: String = "", isChecked: Bool = false
    ) {
        self.label = label
        self.command = command
        self.keyEquivalent = keyEquivalent
        self.isChecked = isChecked
    }
}

public indirect enum MenuNode: Equatable, Sendable {
    case item(MenuItem)

    case submenu(MenuLabel, [MenuNode])

    case separator
}

public struct CameraChoice: Equatable, Sendable {
    public var id: String

    public var name: String

    public var isSelected: Bool

    public init(id: String, name: String, isSelected: Bool) {
        self.id = id
        self.name = name
        self.isSelected = isSelected
    }
}

public struct MenuState: Equatable, Sendable {
    public var version: String

    public var availableUpdate: String?

    public var isCheckingForUpdates: Bool

    public var isPreviewVisible: Bool

    public var cameras: [CameraChoice]

    public var hasCalibration: Bool

    public var isCalibrating: Bool

    public var isGazeDotVisible: Bool

    public var isGazeControlOn: Bool

    public var isSnappingOn: Bool

    public init(
        version: String,
        availableUpdate: String? = nil,
        isCheckingForUpdates: Bool = false,
        isPreviewVisible: Bool = false,
        cameras: [CameraChoice] = [],
        hasCalibration: Bool = false,
        isCalibrating: Bool = false,
        isGazeDotVisible: Bool = false,
        isGazeControlOn: Bool = false,
        isSnappingOn: Bool = false
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
        self.isSnappingOn = isSnappingOn
    }
}

public enum MenuModel {
    public static func build(state: MenuState) -> [MenuNode] {
        var nodes: [MenuNode] = [.item(MenuItem(.version(state.version))), .separator]
        let canUseGaze = state.hasCalibration && !state.isCalibrating
        let canToggleControl = canUseGaze || state.isGazeControlOn
        nodes.append(
            .item(
                MenuItem(
                    .gazeControl, command: canToggleControl ? .toggleGazeControl : nil, isChecked: state.isGazeControlOn
                )))
        nodes.append(.item(MenuItem(.snapping, command: .toggleSnapping, isChecked: state.isSnappingOn)))
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
