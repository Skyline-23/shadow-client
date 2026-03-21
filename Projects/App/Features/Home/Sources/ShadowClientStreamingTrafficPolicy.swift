import CFNetwork
import Darwin
import Foundation
import Network

enum ShadowClientLocalTransportTrafficClass: Sendable {
    case bestEffort
    case interactiveVideo
    case interactiveVoice
    case signaling

    var nwServiceClass: NWParameters.ServiceClass {
        switch self {
        case .bestEffort:
            return .bestEffort
        case .interactiveVideo:
            return .interactiveVideo
        case .interactiveVoice:
            return .interactiveVoice
        case .signaling:
            return .signaling
        }
    }

    var socketServiceType: Int32 {
        switch self {
        case .bestEffort:
            return NET_SERVICE_TYPE_BE
        case .interactiveVideo:
            return NET_SERVICE_TYPE_VI
        case .interactiveVoice:
            return NET_SERVICE_TYPE_VO
        case .signaling:
            return NET_SERVICE_TYPE_SIG
        }
    }

    var dscpValue: Int32? {
        switch self {
        case .bestEffort, .signaling:
            return nil
        case .interactiveVideo:
            return 40
        case .interactiveVoice:
            return 48
        }
    }
}

enum ShadowClientStreamingTrafficPolicy {
    static func rtsp(prioritized: Bool) -> ShadowClientLocalTransportTrafficClass {
        prioritized ? .interactiveVideo : .bestEffort
    }

    static func video(prioritized: Bool) -> ShadowClientLocalTransportTrafficClass {
        prioritized ? .interactiveVideo : .bestEffort
    }

    static func audio(prioritized: Bool) -> ShadowClientLocalTransportTrafficClass {
        prioritized ? .interactiveVoice : .bestEffort
    }

    static func control(prioritized: Bool) -> ShadowClientLocalTransportTrafficClass {
        prioritized ? .signaling : .bestEffort
    }

    static func tcpParameters(
        trafficClass: ShadowClientLocalTransportTrafficClass
    ) -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.serviceClass = trafficClass.nwServiceClass
        return parameters
    }

    static func udpParameters(
        localHost: NWEndpoint.Host? = nil,
        localPort: UInt16? = nil,
        trafficClass: ShadowClientLocalTransportTrafficClass
    ) -> NWParameters {
        let parameters = NWParameters.udp
        parameters.serviceClass = trafficClass.nwServiceClass
        if let localHost {
            let endpointPort: NWEndpoint.Port
            if let localPort, let resolvedPort = NWEndpoint.Port(rawValue: localPort) {
                endpointPort = resolvedPort
            } else {
                endpointPort = .any
            }
            parameters.requiredLocalEndpoint = .hostPort(host: localHost, port: endpointPort)
        }
        return parameters
    }

    static func apply(
        _ trafficClass: ShadowClientLocalTransportTrafficClass,
        to descriptor: Int32,
        addressFamily: Int32
    ) {
        var serviceType = trafficClass.socketServiceType
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NET_SERVICE_TYPE,
            &serviceType,
            socklen_t(MemoryLayout<Int32>.size)
        )

        guard let dscpValue = trafficClass.dscpValue else {
            return
        }

        var trafficClassValue = dscpValue << 2
        switch addressFamily {
        case AF_INET:
            _ = setsockopt(
                descriptor,
                IPPROTO_IP,
                IP_TOS,
                &trafficClassValue,
                socklen_t(MemoryLayout<Int32>.size)
            )
        case AF_INET6:
            _ = setsockopt(
                descriptor,
                IPPROTO_IPV6,
                IPV6_TCLASS,
                &trafficClassValue,
                socklen_t(MemoryLayout<Int32>.size)
            )
        default:
            break
        }
    }

    static var secureHTTPStreamServiceType: CFString {
        kCFStreamNetworkServiceTypeResponsiveAV
    }
}
