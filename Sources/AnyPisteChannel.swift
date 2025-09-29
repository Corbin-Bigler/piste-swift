//
//  AnyPisteChannel.swift
//  Piste
//
//  Created by Corbin Bigler on 9/24/25.
//

import Foundation

protocol AnyPisteChannel: Sendable {
    func yieldInbound(data: Data, with codec: PisteCodec) async throws
    func resumeOpened() async
    func resumeClosed(error: Error?) async
    func resumeCompleted(data: Data, with codec: any PisteCodec) async throws
}

extension PisteChannel: AnyPisteChannel {
    func yieldInbound(data: Data, with codec: any PisteCodec) throws {
        let inbound: Inbound = try PisteServer.decode(data: data, with: codec)
        inboundContinuation.yield(inbound)
    }
    func resumeOpened() async {
        await openedContinuation.resume()
    }
    func resumeClosed(error: Error?) async {
        await onClosed(error: error)
    }
    func resumeCompleted(data: Data, with codec: any PisteCodec) async throws {
        await onCompleted(try codec.decode(data))
    }
}
