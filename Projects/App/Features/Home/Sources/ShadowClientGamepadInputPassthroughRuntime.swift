import Foundation
import GameController
import os
import CoreHaptics

#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@MainActor
final class ShadowClientGamepadInputPassthroughRuntime {
    struct Configuration: Equatable, Sendable {
        var swapABXYButtons: Bool = false
        var forceGamepadOneAlwaysConnected: Bool = false
        var processInputInBackground: Bool = false
    }

    typealias EventSink = @MainActor (ShadowClientRemoteInputEvent) -> Void

    private enum ButtonFlags {
        static let dpadUp: UInt32 = 0x0001
        static let dpadDown: UInt32 = 0x0002
        static let dpadLeft: UInt32 = 0x0004
        static let dpadRight: UInt32 = 0x0008
        static let play: UInt32 = 0x0010
        static let back: UInt32 = 0x0020
        static let leftStickClick: UInt32 = 0x0040
        static let rightStickClick: UInt32 = 0x0080
        static let leftShoulder: UInt32 = 0x0100
        static let rightShoulder: UInt32 = 0x0200
        static let special: UInt32 = 0x0400
        static let actionSouth: UInt32 = 0x1000
        static let actionEast: UInt32 = 0x2000
        static let actionWest: UInt32 = 0x4000
        static let actionNorth: UInt32 = 0x8000
    }

    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "GamepadInput")
    private var configuration = Configuration()
    private var isSessionActive = false
    private var eventSink: EventSink?
    private var didStart = false
    private var observers: [NSObjectProtocol] = []

    private var controllerIndexByID: [ObjectIdentifier: UInt8] = [:]
    private var controllerIDByIndex: [UInt8: ObjectIdentifier] = [:]
    private var controllersByID: [ObjectIdentifier: GCController] = [:]
    private var lastStateByControllerIndex: [UInt8: ShadowClientRemoteGamepadState] = [:]
    private var announcedControllerIndices: Set<UInt8> = []
    private var hasLoggedBackgroundGate = false
    private var controllerFeedbackEventCount: Int = 0
    private var hapticsEngineStoreByControllerID: [ObjectIdentifier: [GCHapticsLocality: CHHapticEngine]] = [:]
    private var loggedHapticsCapabilitiesByControllerID: Set<ObjectIdentifier> = []

    func start(eventSink: @escaping EventSink) {
        self.eventSink = eventSink
        guard !didStart else {
            refreshConnectedControllers()
            return
        }
        didStart = true

        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.handleControllerConnected(controller)
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let controller = notification.object as? GCController else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.handleControllerDisconnected(controller)
                }
            }
        )

        refreshConnectedControllers()
    }

    func stop() {
        guard didStart else {
            return
        }
        didStart = false
        isSessionActive = false
        eventSink = nil

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll(keepingCapacity: false)

        for controller in controllersByID.values {
            controller.extendedGamepad?.valueChangedHandler = nil
        }
        controllersByID.removeAll(keepingCapacity: false)
        controllerIndexByID.removeAll(keepingCapacity: false)
        controllerIDByIndex.removeAll(keepingCapacity: false)
        lastStateByControllerIndex.removeAll(keepingCapacity: false)
        announcedControllerIndices.removeAll(keepingCapacity: false)
        controllerFeedbackEventCount = 0
        stopAndClearAllHapticsEngines()
        loggedHapticsCapabilitiesByControllerID.removeAll(keepingCapacity: false)
        hasLoggedBackgroundGate = false
    }

    func updateConfiguration(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        emitCurrentStates(force: true, includeArrival: true)
    }

    func setSessionActive(_ isActive: Bool) {
        guard isSessionActive != isActive else {
            return
        }
        isSessionActive = isActive
        hasLoggedBackgroundGate = false

        if isActive {
            announcedControllerIndices.removeAll(keepingCapacity: true)
            emitCurrentStates(force: true, includeArrival: true)
        }
    }

    func applyControllerFeedback(_ event: ShadowClientHostControllerFeedbackEvent) {
        guard isSessionActive else {
            logger.notice("RUMBLE TRACE dropped feedback because session is inactive")
            return
        }

        controllerFeedbackEventCount &+= 1

        if shouldLogControllerFeedbackEventSample() {
            logger.notice(
                "RUMBLE TRACE received feedback #\(self.controllerFeedbackEventCount, privacy: .public): \(self.controllerFeedbackSummary(for: event), privacy: .public)"
            )
        }

        switch event {
        case let .rumble(rumble):
            applyRumble(rumble)
        case let .triggerRumble(triggerRumble):
            applyTriggerRumble(triggerRumble)
        }
    }

    private func refreshConnectedControllers() {
        let connected = Set(GCController.controllers().map(ObjectIdentifier.init))
        let known = Set(controllersByID.keys)
        let removed = known.subtracting(connected)

        for id in removed {
            if let controller = controllersByID[id] {
                handleControllerDisconnected(controller)
            }
        }
        for controller in GCController.controllers() {
            handleControllerConnected(controller)
        }
    }

    private func handleControllerConnected(_ controller: GCController) {
        guard let extendedGamepad = controller.extendedGamepad else {
            return
        }
        let controllerID = ObjectIdentifier(controller)
        guard controllerIndexByID[controllerID] == nil else {
            return
        }
        guard let index = nextAvailableControllerIndex() else {
            logger.notice("Gamepad input ignored because all 16 controller slots are occupied")
            return
        }

        controllersByID[controllerID] = controller
        controllerIndexByID[controllerID] = index
        controllerIDByIndex[index] = controllerID
        lastStateByControllerIndex[index] = nil
        announcedControllerIndices.remove(index)
        logControllerHapticsCapabilitiesIfNeeded(controller: controller, index: index)

        extendedGamepad.valueChangedHandler = { [weak self, weak controller] _, _ in
            guard let self, let controller else {
                return
            }
            Task { @MainActor in
                self.emitState(for: controller, force: false, includeArrival: false)
            }
        }

        emitState(for: controller, force: true, includeArrival: true)
    }

    private func handleControllerDisconnected(_ controller: GCController) {
        let controllerID = ObjectIdentifier(controller)
        guard let controllerNumber = controllerIndexByID[controllerID] else {
            return
        }

        controller.extendedGamepad?.valueChangedHandler = nil
        controllerIndexByID.removeValue(forKey: controllerID)
        controllerIDByIndex.removeValue(forKey: controllerNumber)
        controllersByID.removeValue(forKey: controllerID)
        announcedControllerIndices.remove(controllerNumber)
        loggedHapticsCapabilitiesByControllerID.remove(controllerID)
        stopAndRemoveHapticsEngines(for: controllerID)

        let mask = currentActiveGamepadMask()
        let disconnectedState = ShadowClientRemoteGamepadState(
            controllerNumber: controllerNumber,
            activeGamepadMask: mask,
            buttonFlags: 0,
            leftTrigger: 0,
            rightTrigger: 0,
            leftStickX: 0,
            leftStickY: 0,
            rightStickX: 0,
            rightStickY: 0
        )
        lastStateByControllerIndex[controllerNumber] = disconnectedState
        emit(.gamepadState(disconnectedState))

        emitVirtualControllerIfNeeded(force: true, includeArrival: true)
    }

    private func emitCurrentStates(force: Bool, includeArrival: Bool) {
        for controller in controllersByID.values {
            emitState(for: controller, force: force, includeArrival: includeArrival)
        }
        emitVirtualControllerIfNeeded(force: force, includeArrival: includeArrival)
    }

    private func emitState(for controller: GCController, force: Bool, includeArrival: Bool) {
        guard let extendedGamepad = controller.extendedGamepad else {
            return
        }
        let controllerID = ObjectIdentifier(controller)
        guard let controllerNumber = controllerIndexByID[controllerID] else {
            return
        }

        let mask = currentActiveGamepadMask()
        if includeArrival {
            emitArrivalIfNeeded(controllerNumber: controllerNumber, activeMask: mask)
        }

        let mappedState = makeMappedGamepadState(
            from: extendedGamepad,
            controllerNumber: controllerNumber,
            activeGamepadMask: mask
        )
        let previousState = lastStateByControllerIndex[controllerNumber]
        if force || previousState != mappedState {
            lastStateByControllerIndex[controllerNumber] = mappedState
            emit(.gamepadState(mappedState))
        }
    }

    private func emitVirtualControllerIfNeeded(force: Bool, includeArrival: Bool) {
        guard configuration.forceGamepadOneAlwaysConnected else {
            return
        }
        guard controllerIndexByID.values.contains(0) == false else {
            return
        }

        let mask = currentActiveGamepadMask()
        if includeArrival {
            emitArrivalIfNeeded(controllerNumber: 0, activeMask: mask)
        }

        let virtualState = ShadowClientRemoteGamepadState(
            controllerNumber: 0,
            activeGamepadMask: mask,
            buttonFlags: 0,
            leftTrigger: 0,
            rightTrigger: 0,
            leftStickX: 0,
            leftStickY: 0,
            rightStickX: 0,
            rightStickY: 0
        )
        let previousState = lastStateByControllerIndex[0]
        if force || previousState != virtualState {
            lastStateByControllerIndex[0] = virtualState
            emit(.gamepadState(virtualState))
        }
    }

    private func emitArrivalIfNeeded(controllerNumber: UInt8, activeMask: UInt16) {
        guard !announcedControllerIndices.contains(controllerNumber) else {
            return
        }
        announcedControllerIndices.insert(controllerNumber)
        let arrival = ShadowClientHostInputPacketCodec.defaultGamepadArrival(
            controllerNumber: controllerNumber,
            activeGamepadMask: activeMask,
            supportedButtonFlags: supportedGamepadButtons
        )
        emit(.gamepadArrival(arrival))
    }

    private var supportedGamepadButtons: UInt32 {
        ButtonFlags.actionSouth |
            ButtonFlags.actionEast |
            ButtonFlags.actionWest |
            ButtonFlags.actionNorth |
            ButtonFlags.dpadUp |
            ButtonFlags.dpadDown |
            ButtonFlags.dpadLeft |
            ButtonFlags.dpadRight |
            ButtonFlags.leftShoulder |
            ButtonFlags.rightShoulder |
            ButtonFlags.play |
            ButtonFlags.back |
            ButtonFlags.leftStickClick |
            ButtonFlags.rightStickClick |
            ButtonFlags.special
    }

    private func makeMappedGamepadState(
        from gamepad: GCExtendedGamepad,
        controllerNumber: UInt8,
        activeGamepadMask: UInt16
    ) -> ShadowClientRemoteGamepadState {
        let (actionSouth, actionEast, actionWest, actionNorth) = mappedFaceButtons(from: gamepad)

        var buttonFlags: UInt32 = 0
        if actionSouth { buttonFlags |= ButtonFlags.actionSouth }
        if actionEast { buttonFlags |= ButtonFlags.actionEast }
        if actionWest { buttonFlags |= ButtonFlags.actionWest }
        if actionNorth { buttonFlags |= ButtonFlags.actionNorth }
        if gamepad.leftShoulder.isPressed { buttonFlags |= ButtonFlags.leftShoulder }
        if gamepad.rightShoulder.isPressed { buttonFlags |= ButtonFlags.rightShoulder }
        if gamepad.leftThumbstickButton?.isPressed == true { buttonFlags |= ButtonFlags.leftStickClick }
        if gamepad.rightThumbstickButton?.isPressed == true { buttonFlags |= ButtonFlags.rightStickClick }
        if gamepad.dpad.up.isPressed { buttonFlags |= ButtonFlags.dpadUp }
        if gamepad.dpad.down.isPressed { buttonFlags |= ButtonFlags.dpadDown }
        if gamepad.dpad.left.isPressed { buttonFlags |= ButtonFlags.dpadLeft }
        if gamepad.dpad.right.isPressed { buttonFlags |= ButtonFlags.dpadRight }
        if gamepad.buttonMenu.isPressed { buttonFlags |= ButtonFlags.play }

        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, *) {
            if gamepad.buttonOptions?.isPressed == true {
                buttonFlags |= ButtonFlags.back
            }
        }
        if #available(macOS 11.3, iOS 14.5, tvOS 14.5, *) {
            if gamepad.buttonHome?.isPressed == true {
                buttonFlags |= ButtonFlags.special
            }
        }

        return ShadowClientRemoteGamepadState(
            controllerNumber: controllerNumber,
            activeGamepadMask: activeGamepadMask,
            buttonFlags: buttonFlags,
            leftTrigger: normalizedTriggerValue(gamepad.leftTrigger.value),
            rightTrigger: normalizedTriggerValue(gamepad.rightTrigger.value),
            leftStickX: normalizedStickValue(gamepad.leftThumbstick.xAxis.value),
            leftStickY: normalizedStickValue(gamepad.leftThumbstick.yAxis.value),
            rightStickX: normalizedStickValue(gamepad.rightThumbstick.xAxis.value),
            rightStickY: normalizedStickValue(gamepad.rightThumbstick.yAxis.value)
        )
    }

    private func mappedFaceButtons(from gamepad: GCExtendedGamepad) -> (Bool, Bool, Bool, Bool) {
        if configuration.swapABXYButtons {
            return (
                gamepad.buttonB.isPressed, // South
                gamepad.buttonA.isPressed, // East
                gamepad.buttonY.isPressed, // West
                gamepad.buttonX.isPressed // North
            )
        }
        return (
            gamepad.buttonA.isPressed,
            gamepad.buttonB.isPressed,
            gamepad.buttonX.isPressed,
            gamepad.buttonY.isPressed
        )
    }

    private func normalizedTriggerValue(_ value: Float) -> UInt8 {
        let clamped = min(max(Double(value), 0.0), 1.0)
        return UInt8(clamping: Int((clamped * 255.0).rounded()))
    }

    private func normalizedStickValue(_ value: Float) -> Int16 {
        Self.normalizeStickAxisValue(value)
    }

    nonisolated static func normalizeStickAxisValue(_ value: Float) -> Int16 {
        let clamped = min(max(Double(value), -1.0), 1.0)
        let scaled = Int((clamped * 32767.0).rounded())
        return Int16(clamping: scaled)
    }

    private func currentActiveGamepadMask() -> UInt16 {
        var mask: UInt16 = 0
        for controllerIndex in controllerIndexByID.values {
            mask |= (1 << controllerIndex)
        }
        if configuration.forceGamepadOneAlwaysConnected {
            mask |= 0x0001
        }
        return mask
    }

    private func nextAvailableControllerIndex() -> UInt8? {
        let used = Set(controllerIndexByID.values)
        for index in UInt8(0)...UInt8(15) where !used.contains(index) {
            return index
        }
        return nil
    }

    private func emit(_ event: ShadowClientRemoteInputEvent) {
        guard isSessionActive else {
            return
        }
        guard configuration.processInputInBackground || isApplicationActive else {
            if !hasLoggedBackgroundGate {
                hasLoggedBackgroundGate = true
                logger.notice("Gamepad input is suppressed while app is inactive (background processing disabled)")
            }
            return
        }
        hasLoggedBackgroundGate = false
        eventSink?(event)
    }

    private var isApplicationActive: Bool {
#if os(macOS)
        NSApp.isActive
#elseif canImport(UIKit)
        UIApplication.shared.applicationState == .active
#else
        true
#endif
    }

    private func applyRumble(_ rumble: ShadowClientHostControllerRumbleEvent) {
        guard let controller = controller(for: rumble.controllerNumber) else {
            logger.notice(
                "RUMBLE TRACE dropped rumble: unknown controllerNumber=\(rumble.controllerNumber, privacy: .public)"
            )
            return
        }
        guard let haptics = controller.haptics else {
            logger.notice(
                "RUMBLE TRACE dropped rumble: controller has no haptics controllerNumber=\(rumble.controllerNumber, privacy: .public)"
            )
            return
        }

        let lowIntensity = normalizedMotorIntensity(rumble.lowFrequencyMotor)
        let highIntensity = normalizedMotorIntensity(rumble.highFrequencyMotor)

        let localities = haptics.supportedLocalities
        let hasSplitHandles = localities.contains(GCHapticsLocality.leftHandle) &&
            localities.contains(GCHapticsLocality.rightHandle)

        if hasSplitHandles {
            playHapticPulse(
                on: controller,
                haptics: haptics,
                locality: GCHapticsLocality.leftHandle,
                intensity: lowIntensity,
                sharpness: 0.2
            )
            playHapticPulse(
                on: controller,
                haptics: haptics,
                locality: GCHapticsLocality.rightHandle,
                intensity: highIntensity,
                sharpness: 0.8
            )
            return
        }

        playHapticPulse(
            on: controller,
            haptics: haptics,
            locality: GCHapticsLocality.default,
            intensity: max(lowIntensity, highIntensity),
            sharpness: 0.5
        )
    }

    private func applyTriggerRumble(_ rumble: ShadowClientHostControllerTriggerRumbleEvent) {
        guard let controller = controller(for: rumble.controllerNumber) else {
            logger.notice(
                "RUMBLE TRACE dropped trigger rumble: unknown controllerNumber=\(rumble.controllerNumber, privacy: .public)"
            )
            return
        }
        guard let haptics = controller.haptics else {
            logger.notice(
                "RUMBLE TRACE dropped trigger rumble: controller has no haptics controllerNumber=\(rumble.controllerNumber, privacy: .public)"
            )
            return
        }

        let leftIntensity = normalizedMotorIntensity(rumble.leftTriggerMotor)
        let rightIntensity = normalizedMotorIntensity(rumble.rightTriggerMotor)
        let localities = haptics.supportedLocalities
        let hasSplitTriggers = localities.contains(GCHapticsLocality.leftTrigger) &&
            localities.contains(GCHapticsLocality.rightTrigger)

        if hasSplitTriggers {
            playHapticPulse(
                on: controller,
                haptics: haptics,
                locality: GCHapticsLocality.leftTrigger,
                intensity: leftIntensity,
                sharpness: 0.6
            )
            playHapticPulse(
                on: controller,
                haptics: haptics,
                locality: GCHapticsLocality.rightTrigger,
                intensity: rightIntensity,
                sharpness: 0.6
            )
            return
        }

        if localities.contains(GCHapticsLocality.triggers) {
            playHapticPulse(
                on: controller,
                haptics: haptics,
                locality: GCHapticsLocality.triggers,
                intensity: max(leftIntensity, rightIntensity),
                sharpness: 0.6
            )
            return
        }

        // Fallback for controllers that don't expose trigger-specific actuators.
        playHapticPulse(
            on: controller,
            haptics: haptics,
            locality: GCHapticsLocality.default,
            intensity: max(leftIntensity, rightIntensity),
            sharpness: 0.6
        )
    }

    private func playHapticPulse(
        on controller: GCController,
        haptics: GCDeviceHaptics,
        locality: GCHapticsLocality,
        intensity: Float,
        sharpness: Float
    ) {
        let clampedIntensity = min(max(intensity, 0), 1)
        guard clampedIntensity > 0 else {
            return
        }

        guard let engine = hapticEngine(
            on: controller,
            haptics: haptics,
            locality: locality
        ) else {
            logger.notice(
                "RUMBLE TRACE dropped pulse: no haptic engine for locality=\(locality.rawValue, privacy: .public)"
            )
            return
        }

        do {
            try engine.start()
            let event = CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(
                        parameterID: .hapticIntensity,
                        value: clampedIntensity
                    ),
                    CHHapticEventParameter(
                        parameterID: .hapticSharpness,
                        value: min(max(sharpness, 0), 1)
                    ),
                ],
                relativeTime: 0,
                duration: 0.08
            )
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            logger.debug("Gamepad haptic pulse failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func hapticEngine(
        on controller: GCController,
        haptics: GCDeviceHaptics,
        locality: GCHapticsLocality
    ) -> CHHapticEngine? {
        let controllerID = ObjectIdentifier(controller)
        if let cachedEngine = hapticsEngineStoreByControllerID[controllerID]?[locality] {
            return cachedEngine
        }

        guard let engine = haptics.createEngine(withLocality: locality) else {
            logger.notice(
                "RUMBLE TRACE failed to create engine for locality=\(locality.rawValue, privacy: .public)"
            )
            return nil
        }

        engine.isAutoShutdownEnabled = true
        do {
            try engine.start()
        } catch {
            logger.debug("Gamepad haptic engine start failed: \(error.localizedDescription, privacy: .public)")
        }

        var engines = hapticsEngineStoreByControllerID[controllerID] ?? [:]
        engines[locality] = engine
        hapticsEngineStoreByControllerID[controllerID] = engines
        return engine
    }

    private func stopAndClearAllHapticsEngines() {
        for engines in hapticsEngineStoreByControllerID.values {
            for engine in engines.values {
                engine.stop(completionHandler: nil)
            }
        }
        hapticsEngineStoreByControllerID.removeAll(keepingCapacity: false)
    }

    private func stopAndRemoveHapticsEngines(for controllerID: ObjectIdentifier) {
        guard let engines = hapticsEngineStoreByControllerID.removeValue(forKey: controllerID) else {
            return
        }
        for engine in engines.values {
            engine.stop(completionHandler: nil)
        }
    }

    private func controller(for controllerNumber: UInt16) -> GCController? {
        guard let index = UInt8(exactly: controllerNumber),
              let controllerID = controllerIDByIndex[index]
        else {
            return nil
        }
        return controllersByID[controllerID]
    }

    private func normalizedMotorIntensity(_ value: UInt16) -> Float {
        Float(value) / Float(UInt16.max)
    }

    private func shouldLogControllerFeedbackEventSample() -> Bool {
        controllerFeedbackEventCount <= 16 || controllerFeedbackEventCount.isMultiple(of: 120)
    }

    private func controllerFeedbackSummary(
        for event: ShadowClientHostControllerFeedbackEvent
    ) -> String {
        switch event {
        case let .rumble(rumble):
            return "rumble controller=\(rumble.controllerNumber) low=\(rumble.lowFrequencyMotor) high=\(rumble.highFrequencyMotor)"
        case let .triggerRumble(rumble):
            return "trigger controller=\(rumble.controllerNumber) left=\(rumble.leftTriggerMotor) right=\(rumble.rightTriggerMotor)"
        }
    }

    private func logControllerHapticsCapabilitiesIfNeeded(controller: GCController, index: UInt8) {
        let controllerID = ObjectIdentifier(controller)
        guard loggedHapticsCapabilitiesByControllerID.insert(controllerID).inserted else {
            return
        }

        guard let haptics = controller.haptics else {
            logger.notice(
                "RUMBLE TRACE controller connected index=\(index, privacy: .public), haptics=unavailable"
            )
            return
        }

        let localities = haptics.supportedLocalities
            .map(\.rawValue)
            .sorted()
            .joined(separator: ",")
        logger.notice(
            "RUMBLE TRACE controller connected index=\(index, privacy: .public), haptics=available localities=[\(localities, privacy: .public)]"
        )
    }
}
