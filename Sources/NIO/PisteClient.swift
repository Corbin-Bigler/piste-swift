//
//  PisteClient.swift
//  test-client
//
//  Created by Corbin Bigler on 4/24/25.
//

import Foundation
@preconcurrency import NIO
@preconcurrency import NIOHTTP1
@preconcurrency import NIOWebSocket
@preconcurrency import NIOSSL
@preconcurrency import Combine
import SwiftCBOR

public enum PersistentServiceResponse<Clientbound> {
    case response(Clientbound)
    case error(id: String, message: String?)
}

public final class PisteClient: @unchecked Sendable {
    private static let websocketHandshakeTimeout = 10.0
    private static let defaultVersions = [
        PisteVersionsService.id: [PisteVersionsService.version],
        PisteInformationService.id: [PisteInformationService.version]
    ]
    private let group = MultiThreadedEventLoopGroup.singleton
    
    private let host: String
    private let port: Int
    private let path: String
    private let secure: Bool
    
    private var channel: (any Channel)?
    
    private(set) var versions: [String: [Int]] = defaultVersions
    
    private(set) var requests: [String: [Int: AnySafeThrowingContinuation]] = [:]
    private(set) var requestServices: [String: [Int: any TransientPisteService.Type]] = [:]
    private(set) var subjects: [String: [Int: Any]] = [:]
    private(set) var subjectServices: [String: [Int: any PersistentPisteService.Type]] = [:]
    
    public let isConnected = PassthroughSubject<Bool, Never>()

    public init(host: String, port: Int, path: String, secure: Bool = true) {
        self.host = host
        self.port = port
        self.path = path
        self.secure = secure
    }
    
    private func _send<Service: PisteService>(_ outbound: Service.Serverbound, for service: Service.Type) async throws {
        guard let channel, channel.isActive else { throw PisteClientError.disconnected }
        
        let data = try CodableCBOREncoder().encode(service.serverbound(outbound))
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        
        try await channel.writeAndFlush(WebSocketFrame(fin: true, opcode: .binary, maskKey: .random(), data: buffer))
    }
    
    private func onDisconnect() {
        self.channel = nil
        self.versions = Self.defaultVersions
        self.requestServices = [:]
        self.subjectServices = [:]
        self.requests = [:]
        self.subjects = [:]
    }

    public func connect() async throws {
        return try await withSafeThrowingContinuation { continuation in
            let sslContext: NIOSSLContext
            do {
                var config = TLSConfiguration.makeClientConfiguration()
                config.certificateVerification = self.secure ? .fullVerification : .none
                sslContext = try NIOSSLContext(configuration: config)
            } catch {
                continuation.resume(throwing: error)
                return
            }

            let bootstrap = ClientBootstrap(group: self.group)
                .channelInitializer { channel in
                    let websocketUpgrader = NIOWebSocketClientUpgrader(
                        upgradePipelineHandler: { channel, _ in
                            return channel.pipeline.addHandler(ClientWebSocketHandler(client: self)).map {
                                Task {
                                    do {
                                        self.versions = try await self.request(for: PisteVersionsService.self)
                                        continuation.resume()
                                    } catch {
                                        continuation.resume(throwing: PisteClientError.versionsHandshake)
                                    }
                                }
                            }
                        }
                    )

                    let handshakeHandler = ClientWebsocketHandshakeHandler(
                        host: self.host,
                        port: self.port,
                        path: self.path
                    )

                    
                    do {
                        let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: self.host)
                        return channel.pipeline.addHandler(sslHandler).flatMap {
                                channel.pipeline.addHTTPClientHandlers(
                                    withClientUpgrade: (
                                        upgraders: [websocketUpgrader],
                                        completionHandler: { context in
                                            _ = context.pipeline.removeHandler(handshakeHandler)
                                        }
                                    )
                                ).flatMap {
                                    channel.pipeline.addHandler(handshakeHandler)
                                }
                            }
                    } catch {
                        continuation.resume(throwing: error)
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }
            
            Task {
                try await Task.sleep(for: .seconds(Self.websocketHandshakeTimeout))
                continuation.resume(throwing: PisteClientError.timeout)
            }

            bootstrap.connect(host: self.host, port: self.port).whenComplete { result in
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success(let channel):
                    self.channel = channel
                    self.isConnected.send(true)

                    channel.closeFuture.whenComplete { _ in
                        self.isConnected.send(false)
                        self.channel = nil
                    }
                }
            }
        }
    }
    
    public func disconnect() {
        self.channel?.close(promise: nil)
    }
    
    public func request<Service: TransientPisteService>(_ serverbound: Service.Serverbound, for service: Service.Type) async throws -> Service.Clientbound {
        guard let serviceVersions = versions[service.id] else { throw PisteClientError.unsupportedService }
        guard serviceVersions.contains(service.version) else { throw PisteClientError.unsupportedVersion }
        
        return try await withSafeThrowingContinuation { continuation in
            self.group.next().execute {
                self.requestServices[Service.id, default: [:]][Service.version] = Service.self
                self.requests[Service.id, default: [:]][Service.version] = continuation
                
                Task {
                    do { try await self._send(serverbound, for: service) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }
    }
    public func request<Service: TransientPisteService>(for service: Service.Type) async throws -> Service.Clientbound where Service.Serverbound == Empty {
        return try await self.request(Empty(), for: service)
    }
    
    public func publisher<Service: PersistentPisteService>(service: Service.Type) -> PassthroughSubject<PersistentServiceResponse<Service.Clientbound>, Never> {
        let subject = PassthroughSubject<PersistentServiceResponse<Service.Clientbound>, Never>()
        group.next().execute {
            self.subjectServices[Service.id, default: [:]][Service.version] = Service.self
            self.subjects[Service.id, default: [:]][Service.version] = subject
        }
        return subject
    }
    
    public func send<Service: PersistentPisteService>(_ serverbound: Service.Serverbound, for service: Service.Type) async throws {
        try await _send(serverbound, for: service)
    }
}

