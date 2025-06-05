//
//  PistePayload.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/4/25.
//

enum PistePayload<Content: Sendable> {
    case content(Content)
    case stream(PisteStreamPayload)
    case error(PisteErrorPayload)
    
    var type: PistePayloadType {
        switch self {
        case .content(_): return .content
        case .stream(_): return .stream
        case .error(_): return .error
        }
    }
}
