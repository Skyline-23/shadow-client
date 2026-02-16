import ShadowClientInput
import ShadowClientUI
import SwiftUI

struct ControllerFeedbackStatusPanel: View {
    @State private var transport: DualSenseTransport = .usb
    @State private var supportsRumble = true
    @State private var supportsAdaptiveTriggers = true
    @State private var supportsLED = true

    private let presenter = ControllerFeedbackStatusPresenter()

    private var simulationState: ControllerFeedbackSimulationState {
        .init(
            transport: transport,
            supportsRumble: supportsRumble,
            supportsAdaptiveTriggers: supportsAdaptiveTriggers,
            supportsLED: supportsLED
        )
    }

    private var statusModel: ControllerFeedbackStatusModel {
        presenter.makeModel(state: simulationState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            capabilityRows

            VStack(alignment: .leading, spacing: 6) {
                Text("Simulated Controller State")
                    .font(.headline)
                Picker("Transport", selection: $transport) {
                    Text("USB").tag(DualSenseTransport.usb)
                    Text("Bluetooth").tag(DualSenseTransport.bluetooth)
                }
                .pickerStyle(.segmented)

                Toggle("Rumble Support", isOn: $supportsRumble)
                Toggle("Adaptive Triggers", isOn: $supportsAdaptiveTriggers)
                Toggle("LED Indicator", isOn: $supportsLED)
            }
            .font(.caption)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusModel.tone == .healthy ? "gamecontroller.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(statusModel.tone == .healthy ? .green : .orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(statusModel.title)
                    .font(.headline)
                Text(statusModel.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
        }
    }
}
