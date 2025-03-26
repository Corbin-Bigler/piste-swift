//
//  PisteServiceHandler.swift
//  piste
//
//  Created by Corbin Bigler on 3/17/25.
//

public protocol PisteServiceHandler: Sendable {
    associatedtype Service: PisteService
    func handle(inbound: PisteFrame<Service.ServerBound>) async -> PisteResponse<Service.ClientBound>
}

extension PisteServiceHandler {
    var function: PisteFunction { Service.function }
    var version: Int { Service.version }
}
