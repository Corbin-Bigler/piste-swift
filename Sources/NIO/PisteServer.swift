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
    private static let path = "/"
    
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    private let host: String
    private let port: Int
    private let cert: Data
    private let key: Data
    
    let builder: (PisteConnection) -> Void

    public init(host: String, port: Int, cert: Data, key: Data, app: @Sendable @escaping (PisteConnection) -> Void) {
        self.host = host
        self.port = port
        self.cert = cert
        self.key = key
        self.builder = { connection in
            connection.register(PisteVersionsHandler(connection: connection))
            connection.register(PisteInformationHandler(connection: connection))
            app(connection)
        }
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
                if head.uri == Self.path {
                    return channel.eventLoop.makeSucceededFuture([:])
                } else {
                    return channel.eventLoop.makeFailedFuture(NIOWebSocketUpgradeError.invalidUpgradeHeader)
                }
            },
            upgradePipelineHandler: { channel, req in
                let handler = ServerWebSocketHandler(server: self)
                return channel.pipeline.addHandler(handler)
            }
        )

        let bootstrap = ServerBootstrap(group: self.group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let sslHandler = NIOSSLServerHandler(context: sslContext)
                let pathFilterHandler = ServerWebsocketHandshakeHandler(path: Self.path)
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
        Logger.info("Server listening on wss://\(self.host):\(self.port)\(Self.path)")

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
