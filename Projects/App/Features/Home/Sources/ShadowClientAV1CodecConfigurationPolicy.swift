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
        fallbackConfiguration _: Data
    ) -> (
        parameterSets: [Data],
        origin: ShadowClientAV1CodecConfigurationOrigin
    ) {
        let explicitConfiguration = firstAV1CodecConfiguration(from: explicitParameterSets)

        if currentParameterSets.isEmpty {
            if let discoveredConfiguration {
                return ([discoveredConfiguration], .stream)
            }
            if let explicitConfiguration {
                return ([explicitConfiguration], .explicit)
            }
            // Avoid synthesizing av1C from heuristics before stream config appears.
            return ([], .fallback)
        }

        if let discoveredConfiguration {
            if currentOrigin == .explicit || currentOrigin == .fallback {
                if currentParameterSets != [discoveredConfiguration] {
                    return ([discoveredConfiguration], .stream)
                }
                return (currentParameterSets, .stream)
            }

            // Once stream-derived AV1 configuration is active, keep it stable to
            // avoid unnecessary VT session churn from noisy sequence-header variants.
            if currentOrigin == .stream {
                return (currentParameterSets, .stream)
            }
        }

        if currentOrigin == .fallback,
           let explicitConfiguration,
           currentParameterSets != [explicitConfiguration]
        {
            return ([explicitConfiguration], .explicit)
        }

        let resolvedOrigin = currentOrigin ?? (explicitConfiguration == nil ? .fallback : .explicit)
        return (currentParameterSets, resolvedOrigin)
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
