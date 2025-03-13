//
//  PisteClient.swift
//  SudokuBattles
//
//  Created by Corbin Bigler on 3/11/25.
//

import Foundation
import NIO
import NIOSSL

public final class PisteClient: @unchecked Sendable {
    private var group: MultiThreadedEventLoopGroup!
    private let host: String
    private let port: Int
    private let sslContext: NIOSSLContext
    private var handler: PisteClientHandler?

    public init(host: String, port: Int) throws {
        self.host = host
        self.port = port

        // Create TLS configuration without manually loading cert
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = .none

        self.sslContext = try NIOSSLContext(configuration: tlsConfig)
    }

    private func clientBootstrap(handler: PisteClientHandler) -> ClientBootstrap {
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        return ClientBootstrap(group: group)
            .channelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .channelInitializer { channel in
                let sslHandler = try! NIOSSLClientHandler(context: self.sslContext, serverHostname: nil)  //self.host)
                return channel.pipeline.addHandler(sslHandler).flatMap {
                    channel.pipeline.addHandler(BackPressureHandler()).flatMap {
                        channel.pipeline.addHandlers([
                            ByteToMessageHandler(PisteFrameDecoder()),
                            MessageToByteHandler(PisteFrameEncoder()),
                            handler,
                        ])
                    }
                }
            }
    }

    public func run() async throws {
        do {
            let handler = PisteClientHandler()
            let channel = try await clientBootstrap(handler: handler).connect(host: host, port: port).get()
            self.handler = handler
            print("Connected to \(host):\(port)")
            Task {
                do {
                    try await channel.closeFuture.get()
                } catch {
                    print(error)
                }
                self.handler = nil
            }
        } catch {
            throw error
        }
    }

    public func send(frame: EncodedPisteFrame) {
        guard let handler else { return }
        handler.write(frame: frame)
    }

    public func shutdown() {
        do {
            try group.syncShutdownGracefully()
        } catch let error {
            print("Could not shutdown gracefully - forcing exit (\(error.localizedDescription))")
            exit(0)
        }
        print("Client closed")
    }
}
