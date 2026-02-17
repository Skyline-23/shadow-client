import ShadowClientInput
import ShadowClientUI
import SwiftUI

struct ControllerFeedbackPanelSnapshot: Equatable, Sendable {
    let statusModel: ControllerFeedbackStatusModel
    let mappedButtonCount: Int
    let mappedAxisCount: Int
    let mappedButtonNames: [String]
    let leftTriggerValue: Double?
}

struct ControllerFeedbackSimulationInputPlan: Equatable, Sendable {
    let crossPressed: Bool
    let menuPressed: Bool
    let leftTriggerValue: Double

    init(
        crossPressed: Bool = true,
        menuPressed: Bool = true,
        leftTriggerValue: Double = 0.75
    ) {
        self.crossPressed = crossPressed
        self.menuPressed = menuPressed
        self.leftTriggerValue = leftTriggerValue
    }
}

actor ControllerFeedbackPanelRuntime {
    private let runtime: GameControllerFeedbackRuntime
    private let presenter: ControllerFeedbackStatusPresenter

    init(
        runtime: GameControllerFeedbackRuntime = .init(),
        presenter: ControllerFeedbackStatusPresenter = .init()
    ) {
        self.runtime = runtime
        self.presenter = presenter
    }

    func makeSnapshot(
        state: ControllerFeedbackSimulationState,
        inputPlan: ControllerFeedbackSimulationInputPlan
    ) async -> ControllerFeedbackPanelSnapshot {
        let evaluation = await runtime.ingest(
            gameControllerState: ControllerFeedbackSimulationInputState(inputPlan: inputPlan),
            device: ControllerFeedbackSimulationDevice(
                transport: state.transport,
                capabilities: state.capabilities
            )
        )

        let mappedButtonNames = evaluation.state.pressedButtons
            .map(\.rawValue)
            .sorted()

        return ControllerFeedbackPanelSnapshot(
            statusModel: presenter.makeModel(evaluation: evaluation),
            mappedButtonCount: evaluation.state.pressedButtons.count,
            mappedAxisCount: evaluation.state.axisValues.count,
            mappedButtonNames: mappedButtonNames,
            leftTriggerValue: evaluation.state.axisValues[.leftTrigger]
        )
    }
}

private struct ControllerFeedbackSimulationDevice: DualSenseFeedbackDevice {
    let transport: DualSenseTransport
    let capabilities: DualSenseFeedbackCapabilities
}

private struct ControllerFeedbackSimulationInputState: GameControllerStateProviding {
    let inputPlan: ControllerFeedbackSimulationInputPlan

    var faceSouthPressed: Bool { inputPlan.crossPressed }
    var faceEastPressed: Bool { false }
    var faceWestPressed: Bool { false }
    var faceNorthPressed: Bool { false }
    var leftShoulderPressed: Bool { false }
    var rightShoulderPressed: Bool { false }
    var leftStickPressed: Bool { false }
    var rightStickPressed: Bool { false }
    var dpadUpPressed: Bool { false }
    var dpadDownPressed: Bool { false }
    var dpadLeftPressed: Bool { false }
    var dpadRightPressed: Bool { false }
    var menuPressed: Bool { inputPlan.menuPressed }
    var leftStickX: Double { 0.0 }
    var leftStickY: Double { 0.0 }
    var rightStickX: Double { 0.0 }
    var rightStickY: Double { 0.0 }
    var leftTriggerValue: Double { inputPlan.leftTriggerValue }
    var rightTriggerValue: Double { 0.0 }
}

struct ControllerFeedbackStatusPanel: View {
    @State private var transport: DualSenseTransport = .usb
    @State private var supportsRumble = true
    @State private var supportsAdaptiveTriggers = true
    @State private var supportsLED = true
    @State private var simulateCrossPressed = true
    @State private var simulateMenuPressed = true
    @State private var simulateLeftTriggerValue = 0.75
    @State private var runtimeSnapshot: ControllerFeedbackPanelSnapshot?

    private let presenter = ControllerFeedbackStatusPresenter()
    private let runtime = ControllerFeedbackPanelRuntime()

    private var simulationState: ControllerFeedbackSimulationState {
        .init(
            transport: transport,
            supportsRumble: supportsRumble,
            supportsAdaptiveTriggers: supportsAdaptiveTriggers,
            supportsLED: supportsLED
        )
    }

    private var statusModel: ControllerFeedbackStatusModel {
        runtimeSnapshot?.statusModel ?? presenter.makeModel(state: simulationState)
    }

    private var inputPlan: ControllerFeedbackSimulationInputPlan {
        .init(
            crossPressed: simulateCrossPressed,
            menuPressed: simulateMenuPressed,
            leftTriggerValue: simulateLeftTriggerValue
        )
    }

    private var runtimeTaskKey: RuntimeTaskKey {
        .init(simulationState: simulationState, inputPlan: inputPlan)
    }

    private var mappingSummary: String {
        guard let runtimeSnapshot else {
            return "Input Mapping: pending"
        }

        let buttonList = runtimeSnapshot.mappedButtonNames.joined(separator: ", ")
        let mappedButtons = buttonList.isEmpty ? "none" : buttonList
        let leftTriggerValue = String(format: "%.2f", runtimeSnapshot.leftTriggerValue ?? 0.0)

        return "Input Mapping: \(runtimeSnapshot.mappedButtonCount) button(s), \(runtimeSnapshot.mappedAxisCount) axis value(s), LT \(leftTriggerValue) [\(mappedButtons)]"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            capabilityRows

            VStack(alignment: .leading, spacing: 6) {
                Text("Simulated Controller State")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(mappingSummary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.78))
                Picker("Transport", selection: $transport) {
                    Text("USB").tag(DualSenseTransport.usb)
                    Text("Bluetooth").tag(DualSenseTransport.bluetooth)
                }
                .pickerStyle(.segmented)

                Toggle("Rumble Support", isOn: $supportsRumble)
                Toggle("Adaptive Triggers", isOn: $supportsAdaptiveTriggers)
                Toggle("LED Indicator", isOn: $supportsLED)
                Divider()
                Toggle("Simulate CROSS Press", isOn: $simulateCrossPressed)
                Toggle("Simulate MENU Press", isOn: $simulateMenuPressed)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Simulate Left Trigger")
                    Slider(value: $simulateLeftTriggerValue, in: -1.0 ... 2.0, step: 0.05)
                    Text(String(format: "%.2f", simulateLeftTriggerValue))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
            }
            .font(.caption)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .task(id: runtimeTaskKey) {
            await refreshRuntimeSnapshot(state: simulationState, inputPlan: inputPlan)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusModel.tone == .healthy ? "gamecontroller.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(statusModel.tone == .healthy ? .green : .orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(statusModel.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(statusModel.detail)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
    }

    private var capabilityRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(statusModel.rows, id: \.title) { row in
                capabilityRow(title: row.title, passes: row.passes)
            }
        }
        .font(.callout)
    }

    private func capabilityRow(title: String, passes: Bool) -> some View {
        HStack {
            Image(systemName: passes ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(passes ? .green : .red)
            Text(title)
                .foregroundStyle(.white)
        }
    }

    @MainActor
    private func refreshRuntimeSnapshot(
        state: ControllerFeedbackSimulationState,
        inputPlan: ControllerFeedbackSimulationInputPlan
    ) async {
        runtimeSnapshot = await runtime.makeSnapshot(state: state, inputPlan: inputPlan)
    }
}

private struct RuntimeTaskKey: Equatable, Sendable {
    let simulationState: ControllerFeedbackSimulationState
    let inputPlan: ControllerFeedbackSimulationInputPlan
}
