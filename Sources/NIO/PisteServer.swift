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
                if head.uri == self.path {
                    return channel.eventLoop.makeSucceededFuture([:])
                } else {
                    return channel.eventLoop.makeFailedFuture(NIOWebSocketUpgradeError.invalidUpgradeHeader)
                }
            },
            upgradePipelineHandler: { channel, req in
                Logger.info("Client upgraded successfully")
                return channel.pipeline.addHandler(ServerWebSocketHandler(server: self))
            }
        )

        
        let bootstrap = ServerBootstrap(group: self.group)
            .childChannelInitializer { channel in
                let pathFilterHandler = ServerWebsocketHandshakeHandler(path: self.path)
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
}
