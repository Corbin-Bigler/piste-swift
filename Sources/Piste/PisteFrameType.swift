//
//  PisteFrameType.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/4/25.
//

enum PisteFrameType {
    case payload
    case stream
    case error
    
    var continuationPacketId: UInt8 {
        switch self {
        case .payload: return 128 // 10000000
        case .stream: return 129 // 10000001
        case .error: return 130 // 10000010
        }
    }
    
    var finalPacketId: UInt8 {
        switch self {
        case .payload: return 0 // 00000000
        case .stream: return 1 // 00000001
        case .error: return 2 // 00000010
        }
    }
    
    static func fromPacketId(_ packetId: UInt8) -> PisteFrameType? {
        switch packetId {
        case 128, 0: .payload
        case 129, 1: .stream
        case 130, 2: .error
        default: nil
        }
    }
}
