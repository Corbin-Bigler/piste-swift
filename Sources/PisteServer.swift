//
//  SudokuBattlesServer.swift
//  server
//
//  Created by Corbin Bigler on 3/9/25.
//

import Foundation
import NIO
import NIOSSL
import Hardpack

public final class PisteServer: @unchecked Sendable {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    
    private(set) var handlers: [PisteFunction: [Int : (EncodedPisteFrame) async throws -> EncodedPisteFrame]] = [:]
    private(set) var services: [PisteFunction: [Int : any PisteService.Type]] = [:]

    private let host: String
    private let port: Int
    private let sslContext: NIOSSLContext

    public init(host: String, port: Int, cert: String, key: String) throws {
        self.host = host
        self.port = port
                
        let cert = try NIOSSLCertificate.fromPEMFile(cert).map { NIOSSLCertificateSource.certificate($0) }
        let key = try NIOSSLPrivateKey(file: key, format: .pem)
        let tlsConfig = TLSConfiguration.makeServerConfiguration(
            certificateChain: cert,
            privateKey: .privateKey(key)
        )
        
        self.sslContext = try NIOSSLContext(configuration: tlsConfig)
    }

    private var serverBootstrap: ServerBootstrap {
        let sslContext = self.sslContext
        return ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                return channel.pipeline.addHandler(NIOSSLServerHandler(context: sslContext)).flatMap {
                    channel.pipeline.addHandler(BackPressureHandler()).flatMap {
                        channel.pipeline.addHandlers([
                            ByteToMessageHandler(PisteFrameDecoder()),
                            MessageToByteHandler(PisteFrameEncoder()),
                            PisteServerHandler(server: self),
                        ])
                    }
                }
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
    }

    public func run() throws {
        defer { shutdown() }
        do {
            let channel = try serverBootstrap.bind(host: host, port: port).wait()
            print("\(channel.localAddress!) is now open")
            try channel.closeFuture.wait()
        } catch let error {
            throw error
        }
    }

    public func shutdown() {
        do {
            try group.syncShutdownGracefully()
        } catch let error {
            print("Could not shutdown gracefully - forcing exit (\(error.localizedDescription))")
            exit(0)
        }
        print("Server closed")
    }
    
    public func registerService<Service: PisteService>(
        _ service: Service.Type,
        handler: @escaping (PisteFrame<Service.ServerBound>
    ) async throws -> Service.ClientBound) {
        if handlers[service.function] != nil || services[service.function] != nil {
            fatalError("Function \(service.function) already registered")
        }

        services[service.function, default: [:]][service.version] = service
        handlers[service.function, default: [:]][service.version] = { encoded in
            if encoded.function != service.function { fatalError() }

            let decoder = HardpackDecoder()
            guard let payload = try? decoder.decode(Service.ServerBound.self, from: encoded.payload) else {
                return EncodedPisteFrame(function: service.function, version: VarInt(service.version), error: PisteError.badFrame)
            }
            
            let frame = PisteFrame(function: service.function, version: Int(encoded.version), payload: payload)
            if frame.version != service.version {
                let error = frame.version < service.version ? PisteError.clientOutdated : PisteError.serverOutdated
                return EncodedPisteFrame(function: service.function, version: VarInt(service.version), error: error)
            }
            let response = try await handler(frame)
            let encoder = HardpackEncoder()
            return EncodedPisteFrame(function: service.function, version: VarInt(service.version), payload: try! encoder.encode(response))
        }
    }
}
