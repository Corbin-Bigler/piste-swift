//
//  BattleHandler.swift
//  SwiftNIOTutorial
//
//  Created by Corbin Bigler on 3/2/25.
//

import Foundation
import NIO
import NIOSSL
import Hardpack

final class PisteServerHandler: ChannelInboundHandler, @unchecked Sendable {
    public typealias InboundIn = EncodedPisteFrame
    public typealias OutboundOut = EncodedPisteFrame
    
    private let server: PisteServer
    init(server: PisteServer) {
        self.server = server
    }

    func channelActive(context: ChannelHandlerContext) {
        print("Client connected: \(context.remoteAddress?.description ?? "Unknown")")
    }

    func channelInactive(context: ChannelHandlerContext) {
        print("Client disconnected: \(context.remoteAddress?.description ?? "Unknown")")
    }
    
    private func write(context: ChannelHandlerContext, frame: EncodedPisteFrame) {
        context.writeAndFlush(wrapOutboundOut(frame), promise: nil)
    }

    private func processEncoded<T: PisteService>(_ service: T, encoded: EncodedPisteFrame) -> PisteFrame<T.ServerBound>? {
        return service.serverbound(encoded: encoded)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let encoded = unwrapInboundIn(data)
        let version = Int(encoded.version)
        guard let services = server.services[encoded.function], let handlers = server.handlers[encoded.function] else {
            write(context: context, frame: EncodedPisteFrame(function: encoded.function, version: encoded.version, error: PisteError.serviceNotAvailable))
            return
        }
        guard let service = services[version], let handler = handlers[version] else {
            let min = services.keys.min() ?? 0
            if version < min {
                write(context: context, frame: EncodedPisteFrame(function: encoded.function, version: encoded.version, error: PisteError.clientOutdated))
            } else {
                write(context: context, frame: EncodedPisteFrame(function: encoded.function, version: encoded.version, error: PisteError.serverOutdated))
            }
            return
        }
        
        let promise = context.eventLoop.makePromise(of: EncodedPisteFrame.self)
        promise.completeWithTask {
            return try await handler(encoded)
        }
        promise.futureResult.whenSuccess { response in
            self.write(context: context, frame: response)
        }
        promise.futureResult.whenFailure { error in
            if let error = error as? PisteError {
                let errorFrame = EncodedPisteFrame(
                    function: encoded.function,
                    version: encoded.version,
                    error: error
                )
                self.write(context: context, frame: errorFrame)
            } else {
                print("Unknown error: \(error) in service: \(service.function)")
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if let nioError = error as? NIOSSLError, nioError == .uncleanShutdown { return }

        print("Error caught in BattleHandler: \(error)")
        context.channel.close(promise: nil)
    }
}
