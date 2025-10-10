//
//  PisteClient.swift
//  Piste
//
//  Created by Corbin Bigler on 9/24/25.
//

import Foundation
import Logger

public actor PisteClient: Sendable {
    let logger: Logger.Tagged
    let codec: PisteCodec
    
    private var channels: [PisteExchange: (channel: AnyPisteChannel, upload: Bool)] = [:]
    private var outbound: @Sendable (Outbound) async throws -> Void = { _ in }
    
    private var payloadRequests: [PisteExchange: AsyncValue<Data, any Error>.Continuation] = [:]
    private var openRequests: [PisteExchange: AsyncValue<Void, any Error>.Continuation] = [:]
    private var exchange: PisteExchange = 0
    
    private var supportedServices: AsyncValue<[PisteId: PisteServiceType], any Error>? = nil
    private var supportedServicesContinuation: AsyncValue<[PisteId: PisteServiceType], any Error>.Continuation? = nil

    public init(codec: PisteCodec, logger: Logger.Tagged = Logger.shared.tagged(tag: "PisteClient")) {
        self.logger = logger
        self.codec = codec
    }
    
    deinit {
        for (channel, _) in channels.values {
            Task { await channel.resumeClosed(error: PisteInternalError.cancelled) }
        }
        channels.removeAll()
        
        for request in payloadRequests.values {
            Task { await request.resume(throwing: PisteInternalError.cancelled) }
        }
        payloadRequests.removeAll()
        
        for request in openRequests.values {
            Task { await request.resume(throwing: PisteInternalError.cancelled) }
        }
        openRequests.removeAll()
    }
          
    func cancelAll() async {
        logger.info("Canceling all channels and requests")

        for (exchange, (channel, _)) in channels {
            await channel.resumeClosed(error: PisteInternalError.cancelled)
            try? await send(.close, exchange: exchange)
        }
        channels.removeAll()
        
        for request in payloadRequests.values {
            await request.resume(throwing: PisteInternalError.cancelled)
        }
        for request in openRequests.values {
            await request.resume(throwing: PisteInternalError.cancelled)
        }
        payloadRequests.removeAll()
        openRequests.removeAll()
    }
    func onOutbound(_ callback: @Sendable @escaping (Outbound) async throws -> Void) {
        self.outbound = callback
    }
    
    func handle(exchange: PisteExchange, frame: Data) async {
        guard let frame = PisteFrame(data: frame) else {
            logger.error("Failed to decode frame for exchange \(exchange)")
            return
        }
        
        switch frame {
        case .payload(let payload): await handlePayload(payload: payload, exchange: exchange)
        case .supportedServicesResponse(let services): await handleSupportedServicesResponse(services: services, exchange: exchange)
        case .error(let error): await handleError(error: error, exchange: exchange)
        case .close: await handleClose(exchange: exchange)
        case .open: await handleOpen(exchange: exchange)
        case .supportedServicesRequest, .requestCall(_, _), .requestDownload(_, _), .openUpload(_), .openStream(_): return
        }
    }
    private func handlePayload(payload: Data, exchange: PisteExchange) async {
        logger.info("Received Payload frame - payload count: \(payload.count), exchange: \(exchange)")
        
        if let payloadRequest = payloadRequests[exchange] {
            await payloadRequest.resume(returning: payload)
            return
        }

        if let (channel, upload) = channels[exchange] {
            do {
                if (upload) {
                    try await channel.resumeCompleted(payload: payload, with: codec)
                    removeChannel(exchange: exchange)
                } else {
                    try await channel.sendInbound(payload: payload, with: codec)
                }
            } catch {
                try? await send(.close, exchange: exchange)
                await channel.resumeClosed(error: error)
            }
        }
    }

    private func handleClose(exchange: PisteExchange) async {
        logger.info("Received Close frame - exchange: \(exchange)")
        
        if let (channel, _) = channels[exchange] {
            channels.removeValue(forKey: exchange)
            await channel.resumeClosed(error: nil)
        }
    }

    private func handleOpen(exchange: PisteExchange) async {
        logger.info("Received Open frame - exchange: \(exchange)")
        await openRequests[exchange]?.resume()
    }

    private func handleError(error: PisteError, exchange: PisteExchange) async {
        logger.info("Received Error frame - error: \(error) exchange: \(exchange)")
        
        if let payloadContinuation = payloadRequests[exchange] {
            payloadRequests.removeValue(forKey: exchange)
            await payloadContinuation.resume(throwing: error)
            return
        }
        
        if let openContinuation = openRequests[exchange] {
            openRequests.removeValue(forKey: exchange)
            await openContinuation.resume(throwing: error)
            return
        }
        
        logger.error("Unhandled error - error: \(error), exchange: \(exchange)")
    }

    private func handleSupportedServicesResponse(services: [PisteSupportedService], exchange: PisteExchange) async {
        logger.info("Received Supported Services Response frame - services: \(services) exchange: \(exchange)")

        let supportedServicesMap = Dictionary(uniqueKeysWithValues: services.map { ($0.id, $0.type) })
        
        if let supportedServicesContinuation = self.supportedServicesContinuation {
            await supportedServicesContinuation.resume(returning: supportedServicesMap)
            self.supportedServicesContinuation = nil
        } else if supportedServices == nil {
            self.supportedServices = AsyncValue(value: supportedServicesMap)
        }
    }

    func call<Service: CallPisteService>(_ service: Service.Type, request: Service.Serverbound) async throws -> Service.Clientbound {
        try await isSupported(service: service)
        let exchange = nextExchange()
        let payload = try codec.encode(request)
        
        var continuation: AsyncValue<Data, any Error>.Continuation!
        let value = AsyncValue<Data, any Error> { continuation = $0 }
        payloadRequests[exchange] = continuation

        do {
            try await send(.requestCall(id: service.id, payload: payload), exchange: exchange)
        } catch {
            payloadRequests.removeValue(forKey: exchange)
            await continuation.resume(throwing: error)
        }
        
        let responseData = try await value.get()
        payloadRequests.removeValue(forKey: exchange)

        
        let result: Service.Clientbound = try codec.decode(responseData)
        return result
    }
    func download<Service: DownloadPisteService>(_ service: Service.Type, request: Service.Serverbound) async throws -> DownloadPisteChannel<Service> {
        try await isSupported(service: service)
        let payload = try codec.encode(request)
        let exchange = nextExchange()
                
        let channel = PisteChannel<Service.Clientbound, Service.Serverbound>(
            close: { [weak self] in
                guard let self, let (channel, _) = await channels[exchange] else { return }
                await removeChannel(exchange: exchange)
                await channel.resumeClosed(error: nil)
                try? await send(.close, exchange: exchange)
            }
        )
        channels[exchange] = (channel, false)
        
        try await requestOpen(frame: .requestDownload(id: service.id, payload: payload), exchange: exchange)
        
        return DownloadPisteChannel(channel: channel)
    }
    
    func upload<Service: UploadPisteService>(_ service: Service.Type) async throws -> UploadPisteChannel<Service> {
        return UploadPisteChannel(channel: try await openOutboundChannel(service, upload: true))
    }
    func stream<Service: StreamPisteService>(_ service: Service.Type) async throws -> StreamPisteChannel<Service> {
        return StreamPisteChannel(channel: try await openOutboundChannel(service, upload: false))
    }
    
    private func openOutboundChannel<Service: PisteService>(_ service: Service.Type, upload: Bool) async throws -> PisteChannel<Service.Clientbound, Service.Serverbound> {
        try await isSupported(service: service)
        let exchange = nextExchange()

        let channel = PisteChannel<Service.Clientbound, Service.Serverbound>(
            close: { [weak self] in
                guard let self, let (channel, _) = await channels[exchange] else { return }
                await removeChannel(exchange: exchange)
                await channel.resumeClosed(error: nil)
                try? await send(.close, exchange: exchange)
            },
            send: { [weak self] outbound in
                guard let self, await channels[exchange] != nil else { throw PisteError.channelClosed }
                try await send(.payload(try codec.encode(outbound)), exchange: exchange)
            },
        )
        
        channels[exchange] = (channel, upload)
        try await requestOpen(frame: upload ? .openUpload(id: service.id) : .openStream(id: service.id), exchange: exchange)
        
        return channel
    }

    private func requestOpen(frame: PisteFrame, exchange: PisteExchange) async throws {
        var continuation: AsyncValue<Void, any Error>.Continuation!
        let value = AsyncValue<Void, any Error> { continuation = $0 }
        openRequests[exchange] = continuation

        do {
            try await send(frame, exchange: exchange)
        } catch {
            openRequests.removeValue(forKey: exchange)
            removeChannel(exchange: exchange)
            await continuation.resume(throwing: error)
        }
        
        try await value.get()
        openRequests.removeValue(forKey: exchange)
    }
    
    private func removeChannel(exchange: PisteExchange) {
        channels.removeValue(forKey: exchange)
    }

    private func isSupported(service: any PisteService.Type) async throws {
        guard let type = try await getSupportedServices()[service.id] else { throw PisteInternalError.unsupportedService }
        if type != service.type { throw PisteInternalError.incorrectServiceType }
    }

    private func getSupportedServices() async throws -> [PisteId: PisteServiceType] {
        if let supportedServices {
            return try await supportedServices.get()
        } else {
            var continuation: AsyncValue<[PisteId: PisteServiceType], any Error>.Continuation!
            let supportedServices = AsyncValue<[PisteId: PisteServiceType], any Error> { continuation = $0 }
            self.supportedServices = supportedServices
            self.supportedServicesContinuation = continuation
            logger.info("Fetching new service information")
            try await send(.supportedServicesRequest, exchange: nextExchange())
            return try await supportedServices.get()
        }
    }
    private func nextExchange() -> PisteExchange {
        let current = exchange
        exchange &+= 1
        return current
    }

    private func send(_ frame: PisteFrame, exchange: PisteExchange) async throws {
        logger.debug("Sending - frame: \(frame), exchange: \(exchange)")
        try await outbound(.init(exchange: exchange, frameData: frame.data))
    }
            
    public struct Outbound {
        public let exchange: PisteExchange
        public let frameData: Data
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
