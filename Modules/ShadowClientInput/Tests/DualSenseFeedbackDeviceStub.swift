@testable import ShadowClientInput

struct DualSenseFeedbackDeviceStub: DualSenseFeedbackDevice {
    let transport: DualSenseTransport
    let capabilities: DualSenseFeedbackCapabilities
}
