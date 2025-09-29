//
//  UploadPisteHandler.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

public protocol UploadPisteHandler: PisteHandler, Sendable where Service: UploadPisteService {
    func handle(channel: UploadPisteHandlerChannel<Service>) async throws
}
