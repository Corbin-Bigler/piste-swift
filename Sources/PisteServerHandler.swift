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

    func processHandler<Handler: PisteServiceHandler>(_ handler: Handler, inbound: EncodedPisteFrame) async -> EncodedPisteFrame {
        if inbound.function != handler.function { fatalError() }

        let decoder = HardpackDecoder()
        guard let payload = try? decoder.decode(Handler.Service.ServerBound.self, from: inbound.payload) else {
            return EncodedPisteFrame(function: handler.function, version: VarInt(handler.version), error: PisteError.badFrame)
        }

        let frame = PisteFrame(function: handler.function, version: Int(handler.version), payload: payload)
        if frame.version != handler.version {
            let error = frame.version < handler.version ? PisteError.clientOutdated : PisteError.serverOutdated
            return EncodedPisteFrame(function: handler.function, version: VarInt(handler.version), error: error)
        }
        
        let response = await handler.handle(inbound: frame)
        switch response {
        case .success(let response):
            let encoder = HardpackEncoder()
            return EncodedPisteFrame(function: handler.function, version: VarInt(handler.version), payload: try! encoder.encode(response))
        case .failure(let error):
            return EncodedPisteFrame(function: handler.function, version: VarInt(handler.version), error: .failure(error))
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let encoded = unwrapInboundIn(data)
        print("Received frame: \(encoded)")
        
        let version = Int(encoded.version)
        guard let handlers = server.handlers[encoded.function] else {
            write(context: context, frame: EncodedPisteFrame(function: encoded.function, version: encoded.version, error: PisteError.serviceNotAvailable))
            return
        }
        
        guard let handler = handlers[version] else {
            let min = handlers.keys.min() ?? 0
            if version < min {
                write(context: context, frame: EncodedPisteFrame(function: encoded.function, version: encoded.version, error: PisteError.clientOutdated))
            } else {
                write(context: context, frame: EncodedPisteFrame(function: encoded.function, version: encoded.version, error: PisteError.serverOutdated))
            }
            return
        }
        
        let promise = context.eventLoop.makePromise(of: EncodedPisteFrame.self)
        promise.completeWithTask {
            return await self.processHandler(handler, inbound: encoded)
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
                print("Unknown error: \(error) in service: \(handler.function)")
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        if let nioError = error as? NIOSSLError, nioError == .uncleanShutdown { return }

        print("Error caught in BattleHandler: \(error)")
        context.channel.close(promise: nil)
    }
}
