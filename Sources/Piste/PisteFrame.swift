//
//  PisteFrame.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/4/25.
//

enum PisteFrame<Payload: Sendable> {
    case payload(Payload)
    case stream(PisteStreamFrame)
    case error(PisteErrorFrame)
    
    var type: PisteFrameType {
        switch self {
        case .payload(_): return .payload
        case .stream(_): return .stream
        case .error(_): return .error
        }
    }
}
