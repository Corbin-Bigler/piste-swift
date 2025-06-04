//
//  PisteServer.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/7/25.
//

@preconcurrency import Combine
import Foundation
import Logger
import SwiftCBOR

final actor PisteServer {
    private let packetLayer: PistePacketLayer
    private let logger: Logger
    
    var handlers: [String : any PisteHandler] = [:]
    var streams: [String : [UInt64 : Any]] = [:]

    private var maximumPacketSize: Int
    public func setMaximumPacketSize(_ value: Int) async {
        self.maximumPacketSize = value
        await packetLayer.setMaximumPacketSize(value)
    }
    
    private let _onData = PassthroughSubject<Data, Never>()
    public var onData: AsyncStream<Data> {
        AsyncStream { continuation in
            let cancellable = self._onData.sink { continuation.yield($0) }
            continuation.onTermination = { continuation in
                cancellable.cancel()
            }
        }
    }
    
    init(maximumPacketSize: Int = 1400, logger: Logger = Logger.shared) {
        self.maximumPacketSize = maximumPacketSize
        self.packetLayer = PistePacketLayer(maximumPacketSize: maximumPacketSize)
        self.logger = logger
                
        Task {
            for await data in await packetLayer.onFrame {
                if let handler = await handlers[data.serviceId] {
                    if let callHandler = handler as? any PisteCallHandler {
                        Task.detached {
                            let response = try await callHandler.decodeAndHandle(from: data.frame)
                            try await self.send(payload: response, requestId: data.requestId, serviceId: data.serviceId)
                        }
                    } else if let callHandler = handler as? any PisteDownloadHandler {
                        
                    }
                }
            }
        }
    }
    
    private func decodeRequest<Service: RPCService>(_ data: Data, for service: Service) throws -> Service.Request {
        return try CodableCBORDecoder().decode(Service.Request.self, from: data)
    }

    public func register<Handler: PisteCallHandler>(_ handler: Handler) throws { try _register(handler) }
    public func register<Handler: PisteDownloadHandler>(_ handler: Handler) throws { try _register(handler) }
    public func register<Handler: PisteUploadHandler>(_ handler: Handler) throws { try _register(handler) }
    public func register<Handler: PisteChannelHandler>(_ handler: Handler) throws { try _register(handler) }
    private func _register<Handler: PisteHandler>(_ handler: Handler) throws {
        if handlers.keys.contains(handler.id) { throw PisteServerError.serviceAlreadyRegistered }
        handlers[handler.id] = handler
    }
    
    public func handle(data: Data) async {
        await packetLayer.handle(data: data)
    }
    
    private func send<Payload: Encodable & Sendable>(payload: Payload, requestId: UInt64, serviceId: String) async throws {
        let packets = try await packetLayer.makePayloadPackets(payload: payload, requestId: requestId, serviceId: serviceId)
        send(packets: packets)
    }
    private func send(action: PisteStreamAction, requestId: UInt64, serviceId: String) async throws {
        let packets = try await packetLayer.makeStreamPackets(action: action, requestId: requestId, serviceId: serviceId)
        send(packets: packets)
    }
    private func send(code: String, message: String?, requestId: UInt64, serviceId: String) async throws {
        let packets = try await packetLayer.makeErrorPackets(code: code, message: message, requestId: requestId, serviceId: serviceId)
        send(packets: packets)
    }
    private func send(packets: [Data]) {
        for packet in packets { _onData.send(packet) }
    }
}

enum PisteServerError: Error {
    case serviceAlreadyRegistered
}

private extension PisteCallHandler {
    func decodeAndHandle(from data: Data) async throws -> Service.Response {
        try await handle(request: try CodableCBORDecoder().decode(Service.Request.self, from: data))
    }
}
