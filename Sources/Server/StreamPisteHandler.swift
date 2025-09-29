//
//  StreamPisteHandler.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

public protocol StreamPisteHandler: PisteHandler, Sendable where Service: StreamPisteService {
    func handle(channel: StreamPisteHandlerChannel<Service>) async throws
}
