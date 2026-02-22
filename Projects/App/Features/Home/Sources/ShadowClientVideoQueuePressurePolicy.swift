import Foundation

struct ShadowClientVideoQueuePressurePolicy: Equatable, Sendable {
    let allowsDepacketizerPacketShedding: Bool
    let allowsDecodeQueueProducerTrim: Bool
    let allowsDecodeQueueConsumerTrim: Bool

    static let conservative = Self(
        allowsDepacketizerPacketShedding: true,
        allowsDecodeQueueProducerTrim: true,
        allowsDecodeQueueConsumerTrim: true
    )

    static func fromTailTruncationStrategy(
        _ strategy: ShadowClientAV1RTPDepacketizer.TailTruncationStrategy
    ) -> Self {
        switch strategy {
        case .passthroughForAnnexBCodecs:
            return .init(
                allowsDepacketizerPacketShedding: true,
                allowsDecodeQueueProducerTrim: true,
                allowsDecodeQueueConsumerTrim: true
            )
        case .trimUsingLastPacketLength:
            return .init(
                allowsDepacketizerPacketShedding: false,
                allowsDecodeQueueProducerTrim: true,
                allowsDecodeQueueConsumerTrim: true
            )
        }
    }
}
