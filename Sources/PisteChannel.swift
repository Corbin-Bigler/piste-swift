//
//  PisteContext.swift
//  piste
//
//  Created by Corbin Bigler on 4/23/25.
//

import Foundation
@preconcurrency import SwiftCBOR

public class PisteChannel<Service: PisteService>: @unchecked Sendable {
    private let write: (Data) -> Void
    
    init(write: @escaping (Data) -> Void) {
        self.write = write
    }
    
    private func write<Frame: Codable & Sendable>(frame: Frame) {
        do {
            let data = try CodableCBOREncoder().encode(frame)
            write(data)
        } catch {
            print(error)
        }
    }
    
    public func respond(with payload: Service.Clientbound) {
        self.write(frame: Service.clientbound(payload))
    }
    
    public func respond() where Service.Clientbound == Empty {
        respond(with: Empty())
    }

    public func error(_ error: String, message: String? = nil) {
        self.write(frame: Service.error(error, message: message))
    }
}
