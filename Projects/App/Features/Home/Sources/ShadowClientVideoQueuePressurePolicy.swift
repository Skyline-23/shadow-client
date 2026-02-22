import Foundation

struct ShadowClientVideoQueuePressurePolicy: Equatable, Sendable {
    let allowsDepacketizerPacketShedding: Bool
    let allowsDecodeQueueProducerTrim: Bool

    static let conservative = Self(
        allowsDepacketizerPacketShedding: true,
        allowsDecodeQueueProducerTrim: true
    )

    static func fromTailTruncationStrategy(
        _ strategy: ShadowClientAV1RTPDepacketizer.TailTruncationStrategy
    ) -> Self {
        switch strategy {
        case .passthroughForAnnexBCodecs:
            return .init(
                allowsDepacketizerPacketShedding: true,
                allowsDecodeQueueProducerTrim: true
            )
        case .trimUsingLastPacketLength:
            return .init(
                allowsDepacketizerPacketShedding: false,
                allowsDecodeQueueProducerTrim: false
            )
        }
    }
}
