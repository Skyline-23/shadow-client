import Foundation

enum ShadowClientAV1CodecConfigurationOrigin: Equatable, Sendable {
    case explicit
    case stream
    case fallback
}

enum ShadowClientAV1CodecConfigurationPolicy {
    static func resolve(
        currentParameterSets: [Data],
        currentOrigin: ShadowClientAV1CodecConfigurationOrigin?,
        explicitParameterSets: [Data],
        discoveredConfiguration: Data?,
        fallbackConfiguration: Data
    ) -> (
        parameterSets: [Data],
        origin: ShadowClientAV1CodecConfigurationOrigin
    ) {
        if let explicitConfiguration = firstAV1CodecConfiguration(from: explicitParameterSets) {
            return ([explicitConfiguration], .explicit)
        }

        if currentParameterSets.isEmpty {
            if let discoveredConfiguration {
                return ([discoveredConfiguration], .stream)
            }
            return ([fallbackConfiguration], .fallback)
        }

        if currentOrigin == .fallback,
           let discoveredConfiguration,
           currentParameterSets != [discoveredConfiguration]
        {
            return ([discoveredConfiguration], .stream)
        }

        return (currentParameterSets, currentOrigin ?? .stream)
    }

    private static func firstAV1CodecConfiguration(from parameterSets: [Data]) -> Data? {
        for parameterSet in parameterSets where isLikelyAV1CodecConfigurationRecord(parameterSet) {
            return parameterSet
        }
        return nil
    }

    private static func isLikelyAV1CodecConfigurationRecord(_ value: Data) -> Bool {
        guard value.count >= 4 else {
            return false
        }

        let markerSet = (value[0] & 0x80) != 0
        let version = value[0] & 0x7F
        return markerSet && version >= 1
    }
}
