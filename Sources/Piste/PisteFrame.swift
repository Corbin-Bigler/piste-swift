//
//  PisteFrame.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/4/25.
//

import SwiftCBOR
import Foundation

struct PisteFrame {
    let serviceId: String
    let requestId: UInt64
    let payload: PistePayload<Sendable & Codable>
    
    func packets(maxSize: Int = 1400) throws -> [Data] {
        let encoder = CodableCBOREncoder()
        let encodedPayload = switch payload {
        case .content(let payload): try encoder.encode(payload)
        case .stream(let payload): try encoder.encode(payload)
        case .error(let payload): try encoder.encode(payload)
        }

        return try PisteFrameData(serviceId: serviceId, requestId: requestId, type: payload.type, payload: encodedPayload).packets(maxSize: maxSize)
    }
}
