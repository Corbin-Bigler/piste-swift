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
    private let cert: Data
    private let key: Data
    
    private(set) var handlers: [String: [Int : any PisteHandler.Type]] = [:]

    public init(host: String, port: Int, path: String, cert: Data, key: Data) {
        self.host = host
        self.port = port
        self.path = path
        self.cert = cert
        self.key = key

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
        // Load certificate and key
        let cert = try NIOSSLCertificate.fromPEMBytes([UInt8](self.cert))
        let key = try NIOSSLPrivateKey(bytes: [UInt8](self.key), format: .pem)
        
        let tlsConfiguration = TLSConfiguration.makeServerConfiguration(
            certificateChain: cert.map { .certificate($0) },
            privateKey: .privateKey(key)
        )
        
        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
        
        let webSocketUpgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { channel, head in
                if head.uri == self.path {
                    return channel.eventLoop.makeSucceededFuture([:])
                } else {
                    return channel.eventLoop.makeFailedFuture(NIOWebSocketUpgradeError.invalidUpgradeHeader)
                }
            },
            upgradePipelineHandler: { channel, req in
                return channel.pipeline.addHandler(ServerWebSocketHandler(server: self))
            }
        )

        let bootstrap = ServerBootstrap(group: self.group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let sslHandler = NIOSSLServerHandler(context: sslContext)
                let pathFilterHandler = ServerWebsocketHandshakeHandler(path: self.path)
                return channel.pipeline.addHandler(sslHandler).flatMap {
                    channel.pipeline.configureHTTPServerPipeline(
                        withServerUpgrade: (
                            upgraders: [webSocketUpgrader],
                            completionHandler: { context in
                                _ = channel.pipeline.removeHandler(pathFilterHandler)
                            }
                        )
                    )
                    .flatMap {
                        channel.pipeline.addHandler(pathFilterHandler)
                    }
                }
            }

        let channel = try await bootstrap.bind(host: host, port: port).get()
        Logger.info("Server listening on wss://\(self.host):\(self.port)\(self.path)")

        try await channel.closeFuture.get()
    }
}

final class DebugHandler: ChannelInboundHandler {
    typealias InboundIn = Any
    typealias InboundOut = Any

    private let label: String

    init(label: String = "[Debug]") {
        self.label = label
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        print("\(label) Channel read: \(data)")
        context.fireChannelRead(data)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        print("\(label) Event: \(event)")
        context.fireUserInboundEventTriggered(event)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("\(label) Error: \(error)")
        context.fireErrorCaught(error)
    }

    func channelActive(context: ChannelHandlerContext) {
        print("\(label) Channel active")
        context.fireChannelActive()
    }

    func channelInactive(context: ChannelHandlerContext) {
        print("\(label) Channel inactive")
        context.fireChannelInactive()
    }
}
