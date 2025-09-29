//
//  PisteClient.swift
//  Piste
//
//  Created by Corbin Bigler on 9/24/25.
//

import Foundation
import Logger

public actor PisteClient: Sendable {
    let logger: Logger
    let codec: PisteCodec
    
    public typealias Outbound = (exchange: PisteExchange, frame: Data)
    var outbound: @Sendable (Outbound) async throws -> Void = { _ in }
    
    private var channels: [PisteExchange: (channel: AnyPisteChannel, upload: Bool)] = [:]
    
    private var payloadRequests: [PisteExchange: CheckedContinuation<Data, any Error>] = [:]
    private var openRequests: [PisteExchange: CheckedContinuation<Void, any Error>] = [:]
    private var exchange: PisteExchange = 0
    private var storedServiceInformation: [PisteServiceInformationService.ServiceInformation]? = nil
    
    public init(codec: PisteCodec, logger: Logger = Logger.shared) {
        self.logger = logger
        self.codec = codec
    }
    
    deinit {
        _cancelAll(channels: self.channels, payloadRequests: self.payloadRequests, openRequests: self.openRequests)
    }
          
    func cancelAll() {
        _cancelAll(channels: self.channels, payloadRequests: self.payloadRequests, openRequests: self.openRequests)
    }
    func onOutbound(_ callback: @Sendable @escaping (Outbound) async throws -> Void) {
        self.outbound = callback
    }
    
    func getServiceInformation() async throws -> [PisteServiceInformationService.ServiceInformation] {
        if let storedServiceInformation { return storedServiceInformation }
        logger.info("Fetching new service information from PisteServiceInformationService")
        storedServiceInformation = try await call(PisteServiceInformationService.self)
        return storedServiceInformation!
    }

    func handle(exchange: PisteExchange, frame: Data) async {
        guard let frame = PisteFrame(data: frame) else {
            logger.error("Failed to decode frame for exchange \(exchange)")
            return
        }
        
        switch frame {
        case .error(let error):
            logger.error("Received error on exchange \(exchange): \(error)")
            if let payloadRequest = payloadRequests[exchange] {
                payloadRequest.resume(throwing: error)
                payloadRequests.removeValue(forKey: exchange)
            }
            if let openRequest = openRequests[exchange] {
                openRequest.resume(throwing: error)
                openRequests.removeValue(forKey: exchange)
            }
        case .close:
            logger.info("Received close frame for exchange \(exchange)")
            if let channel = channels[exchange]?.channel {
                await channel.resumeClosed(error: nil)
                removeChannel(exchange: exchange)
            }
        case .opened:
            logger.info("Exchange \(exchange) successfully opened")
            if let openRequest = openRequests[exchange] {
                openRequest.resume()
                openRequests.removeValue(forKey: exchange)
            }
        case .payload(let payload):
            logger.debug("Received payload (\(payload.count) bytes) on exchange \(exchange)")
            if let payloadRequest = payloadRequests[exchange] {
                payloadRequest.resume(returning: payload)
                payloadRequests.removeValue(forKey: exchange)
            }
            if let (channel, upload) = channels[exchange] {
                do {
                    if upload {
                        try await channel.resumeCompleted(data: payload, with: codec)
                        removeChannel(exchange: exchange)
                    } else {
                        try await channel.yieldInbound(data: payload, with: codec)
                    }
                } catch {
                    let error = error as? PisteError ?? .unhandledError
                    await channel.resumeClosed(error: error)
                }
            }
        default:
            logger.debug("Unhandled frame type for exchange \(exchange)")
            return
        }
    }
    
    func call<Service: CallPisteService>(_ service: Service.Type, request: Service.Serverbound) async throws -> Service.Clientbound {
        logger.info("Calling service \(Service.id) with exchange \(exchange + 1)")

        guard try await isSupported(service: service) else {
            throw PisteError.unsupportedService
        }
                
        let payload = try codec.encode(request)
        let exchange = getExchange()
        
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            payloadRequests[exchange] = continuation
            Task {
                do {
                    try await send(.request(id: service.id, payload: payload), exchange: exchange)
                } catch {
                    logger.error("Failed to send frame on exchange \(exchange): \(error)")
                    payloadRequests.removeValue(forKey: exchange)
                    continuation.resume(throwing: error)
                }
            }
        }
        
        let result: Service.Clientbound = try codec.decode(data)
        logger.debug("Decoded response for service \(Service.id) on exchange \(exchange)")
        return result
    }
    func download<Service: DownloadPisteService>(_ service: Service.Type, request: Service.Serverbound) async throws -> DownloadPisteChannel<Service> {
        logger.info("Opening download channel for service \(Service.id) on exchange \(exchange + 1)")
        
        guard try await isSupported(service: service) else {
            throw PisteError.unsupportedService
        }
        
        let payload = try codec.encode(request)
        let exchange = getExchange()
        
        try await withCheckedThrowingContinuation { continuation in
            openRequests[exchange] = continuation
            Task {
                do {
                    try await send(.request(id: service.id, payload: payload), exchange: exchange)
                } catch {
                    logger.error("Failed to send frame on exchange \(exchange): \(error)")
                    openRequests.removeValue(forKey: exchange)
                    continuation.resume(throwing: error)
                }
            }
        }
        
        let channel = PisteChannel<Service.Clientbound, Service.Serverbound>(
            close: { [weak self] in
                guard let self else { return }
                self.logger.info("Closing channel for exchange \(exchange)")
                
                await removeChannel(exchange: exchange)
                try? await send(.close, exchange: exchange)
            }
        )
        channels[exchange] = (channel, false)
        
        return DownloadPisteChannel(channel: channel)
    }
    
    private func openOutboundChannel<Service: PisteService>(_ service: Service.Type, upload: Bool) async throws -> PisteChannel<Service.Clientbound, Service.Serverbound> {
        guard try await isSupported(service: service) else {
            throw PisteError.unsupportedService
        }
        
        let exchange = getExchange()

        try await withCheckedThrowingContinuation { continuation in
            openRequests[exchange] = continuation
            Task {
                do {
                    try await send(.open(id: service.id), exchange: exchange)
                } catch {
                    logger.error("Failed to send frame on exchange \(exchange): \(error)")
                    openRequests.removeValue(forKey: exchange)
                    continuation.resume(throwing: error)
                }
            }
        }

        let channel = PisteChannel<Service.Clientbound, Service.Serverbound>(
            send: { [weak self] outbound in
                guard let self, await channels[exchange] != nil else { throw PisteError.channelClosed }
                try await send(.payload(try codec.encode(outbound)), exchange: exchange)
            },
            close: { [weak self] in
                guard let self, await channels[exchange] != nil else { return }
                self.logger.info("Closing channel for exchange \(exchange)")
                
                await removeChannel(exchange: exchange)
                try? await send(.close, exchange: exchange)
            },
        )
        channels[exchange] = (channel, upload)
        
        return channel
    }
    func upload<Service: UploadPisteService>(_ service: Service.Type) async throws -> UploadPisteChannel<Service> {
        logger.info("Opening upload channel for service \(Service.id) on exchange \(exchange + 1)")
        return UploadPisteChannel(channel: try await openOutboundChannel(service, upload: true))
    }
    func stream<Service: StreamPisteService>(_ service: Service.Type) async throws -> StreamPisteChannel<Service> {
        logger.info("Opening stream channel for service \(Service.id) on exchange \(exchange + 1)")
        return StreamPisteChannel(channel: try await openOutboundChannel(service, upload: false))
    }
    
    private func isSupported<Service: PisteService>(service: Service.Type) async throws -> Bool {
        if Service.id == PisteServiceInformationService.id { return true }
        return try await getServiceInformation().map(\.id).contains(service.id)
    }
    private func send(_ frame: PisteFrame, exchange: PisteExchange) async throws {
        logger.debug("Sending frame \(frame) on exchange \(exchange)")
        try await outbound((exchange: exchange, frame: frame.data))
    }
    private func getExchange() -> PisteExchange {
        exchange += 1
        return exchange
    }
    private func removeChannel(exchange: PisteExchange) {
        logger.debug("Removing channel for exchange \(exchange)")
        channels.removeValue(forKey: exchange)
    }
    
    private nonisolated func _cancelAll(
        channels: [PisteExchange: (channel: AnyPisteChannel, upload: Bool)],
        payloadRequests: [PisteExchange: CheckedContinuation<Data, any Error>],
        openRequests: [PisteExchange: CheckedContinuation<Void, any Error>]
    ) {
        logger.fault("Canceling all channels and requests")

        Task {
            for exchange in channels.keys {
                await channels[exchange]!.channel.resumeClosed(error: PisteInternalError.cancelled)
                try? await outbound((exchange, PisteFrame.close.data))
            }
        }
        
        for continuation in payloadRequests.values {
            continuation.resume(throwing: PisteInternalError.cancelled)
        }
        for continuation in openRequests.values {
            continuation.resume(throwing: PisteInternalError.cancelled)
        }
    }
}

extension PisteClient {
    func call<Service: CallPisteService>(_ service: Service.Type) async throws -> Service.Clientbound where Service.Serverbound == Void {
        try await call(service, request: ())
    }
    func download<Service: DownloadPisteService>(_ service: Service.Type) async throws -> DownloadPisteChannel<Service> where Service.Serverbound == Void {
        try await download(service, request: ())
    }
}
