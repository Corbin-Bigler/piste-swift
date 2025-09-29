//
//  CallPisteHandler.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

public protocol CallPisteHandler: PisteHandler, Sendable where Service: CallPisteService {
    func handle(request: Service.Serverbound) async throws -> Service.Clientbound
}
