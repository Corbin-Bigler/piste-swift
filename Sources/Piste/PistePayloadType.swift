//
//  PistePayloadType.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/4/25.
//

enum PistePayloadType {
    case content
    case stream
    case error
    
    var continuationPacketId: UInt8 {
        switch self {
        case .content: return 128 // 10000000
        case .stream: return 129 // 10000001
        case .error: return 130 // 10000010
        }
    }
    
    var finalPacketId: UInt8 {
        switch self {
        case .content: return 0 // 00000000
        case .stream: return 1 // 00000001
        case .error: return 2 // 00000010
        }
    }
    
    static func fromPacketId(_ packetId: UInt8) -> PistePayloadType? {
        switch packetId {
        case 128, 0: .content
        case 129, 1: .stream
        case 130, 2: .error
        default: nil
        }
    }
}
