//
//  PisteHandler.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

public protocol PisteHandler: Sendable {
    associatedtype Service: PisteService
    
    nonisolated var service: Service.Type { get }
}

extension PisteHandler {
    nonisolated var id: PisteId { service.id }
}
