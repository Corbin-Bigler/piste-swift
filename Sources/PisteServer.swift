//
//  PisteServer.swift
//  piste
//
//  Created by Corbin Bigler on 4/23/25.
//

import SwiftLogger
import Foundation
import SwiftCBOR
@preconcurrency import NIO
@preconcurrency import NIOHTTP1
@preconcurrency import NIOWebSocket
@preconcurrency import NIOSSL

public class PisteServer: @unchecked Sendable {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    private let host: String
    private let port: Int
    private let path: String
    
    private(set) var handlers: [String: [Int : any PisteHandler.Type]] = [:]

    public init(host: String, port: Int, path: String) {
        self.host = host
        self.port = port
        self.path = path
        
        self.register(handler: PisteVersionsHandler.self)
        self.register(handler: PisteInformationHandler.self)
    }
    
    public func register(handler: any PisteHandler.Type) {
        guard handlers[handler.id]?[handler.version] == nil else {
            fatalError("Trying to reregister handler: \(handler.id)-\(handler.version)")
        }
        handlers[handler.id, default: [:]][handler.version] = handler
    }

    public func run() async throws {
        let webSocketUpgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { channel, head in
                if head.uri == "/echo" {
                    return channel.eventLoop.makeSucceededFuture([:])
                } else {
                    return channel.eventLoop.makeFailedFuture(NIOWebSocketUpgradeError.invalidUpgradeHeader)
                }
            },
            upgradePipelineHandler: { channel, req in
                channel.pipeline.addHandler(WebSocketHandler(server: self))
            }
        )

        
        let bootstrap = ServerBootstrap(group: self.group)
            .childChannelInitializer { channel in
                let pathFilterHandler = WebSocketPathFilterHandler(path: self.path)
                return channel.pipeline.configureHTTPServerPipeline(
                    withServerUpgrade: (
                        upgraders: [webSocketUpgrader],
                        completionHandler: { context in
                            _ = channel.pipeline.removeHandler(pathFilterHandler)
                        }
                    )
                ).flatMap {
                    channel.pipeline.addHandler(pathFilterHandler)
                }
            }
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
        
        let channel = try await bootstrap.bind(host: "127.0.0.1", port: 8888).get()
        Logger.info("Server started and listening on \(channel.localAddress!)")

        try await channel.closeFuture.get()
    }
    
    private final class WebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
        typealias InboundIn = WebSocketFrame
        typealias InboundOut = WebSocketFrame
        
        private let decoder = CodableCBORDecoder()
        
        private let server: PisteServer
        private var handlers: [String: [Int : any PisteHandler]] = [:]
        
        init(server: PisteServer) {
            self.server = server
        }

        private func write(context: ChannelHandlerContext, error: PisteErrorFrame) {
            if let data = try? CodableCBOREncoder().encode(error) {
                var buffer = context.channel.allocator.buffer(capacity: data.count)
                buffer.writeBytes(data)
                context.writeAndFlush(NIOAny(WebSocketFrame(fin: true, opcode: .binary, data: buffer)), promise: nil)
            }
        }
        private func handle<Handler: PisteHandler>(_ data: Data, context: ChannelHandlerContext, for handler: Handler.Type) {
            guard let serverbound = try? decoder.decode(PisteFrame<Handler.Service.Serverbound>.self, from: data).payload else {
                write(context: context, error: PisteErrorFrame(error: "bad-payload", message: "Invalid payload format"))
                return
            }
            
            if handlers[handler.id]?[handler.version] == nil {
                handlers[handler.id, default: [:]][handler.version] = handler.init()
            }
            
            let context = PisteContext<Handler>(context: context, server: server)
            do {
                try (handlers[handler.id]![handler.version]! as! Handler).handle(context: context, serverbound: serverbound)
            } catch {
                if let pisteError = error as? any PisteError {
                    context.error(pisteError.rawValue, message: pisteError.message)
                } else {
                    
                }
            }
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let frame = unwrapInboundIn(data)

            if frame.opcode == .binary {
                var buffer = frame.unmaskedData
                guard let data = buffer.readBytes(length: buffer.readableBytes).flatMap({ Data($0) }) else {
                    return
                }
                guard let headers = try? decoder.decode(PisteFrameHeader.self, from: data) else {
                    write(context: context, error: PisteErrorFrame(error: "bad-frame", message: "Invalid frame format"))
                    return
                }
                guard let handlerType = server.handlers[headers.service]?[headers.version] else {
                    write(
                        context: context,
                        error: PisteErrorFrame(
                            error: "unknown-service",
                            service: headers.service,
                            version: headers.version,
                            message: "Could not find service \"\(headers.service)\" with version \(headers.version)"
                        )
                    )
                    return
                }
                      

                
                handle(data, context: context, for: handlerType)
            }
        }
    }
    
    private final class WebSocketPathFilterHandler: ChannelInboundHandler, RemovableChannelHandler, Sendable {
        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart
        
        let path: String
        init(path: String) {
            self.path = path
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let part = unwrapInboundIn(data)
            
            if case .head(let head) = part {
                if head.uri != path {
                    let responseHead = HTTPResponseHead(version: head.version, status: .notFound)
                    context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
                    context.write(wrapOutboundOut(.end(nil)), promise: nil)
                    context.flush()
                    context.close(promise: nil)
                    return
                }
            }

            context.fireChannelRead(data)
        }
    }
}
