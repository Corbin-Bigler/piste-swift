//
//  AnyPisteChannel.swift
//  Piste
//
//  Created by Corbin Bigler on 9/24/25.
//

import Foundation

protocol AnyPisteChannel: Sendable {
    func resumeClosed(error: Error?) async
    func sendInbound(payload: Data, server: PisteServer) async throws
    func resumeCompleted(payload: Data, with codec: PisteCodec) async throws
    func sendInbound(payload: Data, with codec: PisteCodec) async throws
}

extension PisteChannel: AnyPisteChannel {
    func sendInbound(payload: Data, server: PisteServer) async throws {
        inboundContinuation.yield(try await server.handleDecode(payload: payload))
    }
    func resumeCompleted(payload: Data, with codec: PisteCodec) async throws {
        await resumeCompleted(inbound: try codec.decode(payload))
    }
    func sendInbound(payload: Data, with codec: PisteCodec) throws {
        inboundContinuation.yield(try codec.decode(payload))
    }
}
