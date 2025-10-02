//
//  PisteServer.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

import Foundation
import Logger

public actor PisteServer: Sendable {
    let logger: Logger.Tagged
    let codec: PisteCodec
    
    private var outbound: @Sendable (Outbound) async throws -> Void = {_ in}
    
    private let handlers: [PisteId: any PisteHandler]
    private var channels: [PisteExchange: AnyPisteChannel] = [:]
    
    public init(codec: PisteCodec, handlers: [any PisteHandler], logger: Logger = Logger.shared) {
        self.codec = codec
        self.logger = logger.tagged(tag: "PisteServer")
        
        self.handlers = handlers.reduce(into: [:]) { dict, handler in
            guard dict[handler.id] == nil else {
                assertionFailure("Handler for id: \(handler.id) already registered (this is a bug)")
                return
            }
            dict[handler.id] = handler
        }
    }
    
    deinit {
        for (_, channel) in channels {
            Task {
                await channel.resumeClosed(error: PisteInternalError.cancelled)
            }
        }
    }
    
    func cancelAll() async {
        for (exchange, channel) in channels {
            await channel.resumeClosed(error: PisteInternalError.cancelled)
            try? await outbound(.init(exchange: exchange, frameData: PisteFrame.error(PisteError.channelClosed).data))
        }
        channels.removeAll()
    }
    
    func onOutbound(_ callback: @Sendable @escaping (Outbound) async throws -> Void) {
        self.outbound = callback
    }
        
    func handle(exchange: PisteExchange, frame: Data) async {
        guard let frame = PisteFrame(data: frame) else {
            logger.error("Failed to decode frame for exchange \(exchange)")
            return
        }
  
        do {
            switch frame {
            case .requestCall(let id, let payload): try await handleRequestCall(id: id, payload: payload, exchange: exchange)
            case .requestDownload(let id, let payload): try await handleRequestDownload(id: id, payload: payload, exchange: exchange)
            case .openUpload(let id): try await handleOpenUpload(id: id, exchange: exchange)
            case .openStream(let id): try await handleOpenStream(id: id, exchange: exchange)
            case .payload(let payload): try await handlePayload(payload: payload, exchange: exchange)
            case .close: try await handleClose(exchange: exchange)
            case .supportedServicesRequest: await handleSupportedServicesRequest(exchange: exchange)
            case .open, .error(_), .supportedServicesResponse(_): await handleUnsupported(frame: frame, exchange: exchange)
            }
        } catch let error as PisteError {
            await sendError(error, exchange: exchange)
        } catch {
            logger.error("Internal server error - exchange: \(exchange), error: \(error)")
            await sendError(.internalServerError, exchange: exchange)
        }
    }
    
    private func handleRequestCall(id: PisteId, payload: Data, exchange: PisteExchange) async throws {
        logger.info("Received Request Call frame - id: \(id), payload size: \(payload.count), exchange: \(exchange)")
        guard let handler = handlers[id] else { throw PisteError.unsupportedService }
        guard let callHandler = handler as? any CallPisteHandler else { throw PisteError.unsupportedFrameType }
        let response = try await callHandler.handleRequest(payload: payload, server: self)
        await sendCatching(.payload(response), exchange: exchange)
    }
    private func handleRequestDownload(id: PisteId, payload: Data, exchange: PisteExchange) async throws {
        logger.info("Received Request Download frame - id: \(id), payload size: \(payload.count), exchange: \(exchange)")
        guard let handler = handlers[id] else { throw PisteError.unsupportedService }
        guard let downloadHandler = handler as? any DownloadPisteHandler else { throw PisteError.unsupportedFrameType }
        let channel = try await downloadHandler.handleRequest(
            payload: payload,
            send: { [weak self] response in
                guard let self else { return }
                guard await channels[exchange] != nil else { throw PisteInternalError.channelClosed }
                await sendCatching(.payload(response), exchange: exchange)
            },
            close: { [weak self] in
                guard let self, await channels[exchange] != nil else { return }
                await removeChannel(exchange: exchange)
                await sendCatching(.close, exchange: exchange)
            },
            server: self
        )
        channels[exchange] = channel
        await sendCatching(.open, exchange: exchange)
    }
    private func handleOpenUpload(id: PisteId, exchange: PisteExchange) async throws {
        logger.info("Received Open Upload frame - id: \(id), exchange: \(exchange)")
        guard let handler = handlers[id] else { throw PisteError.unsupportedService }
        guard let uploadHandler = handler as? any UploadPisteHandler else { throw PisteError.unsupportedFrameType }
        let channel = try await uploadHandler.handleOpen(
            send: { [weak self] response in
                guard let self else { return }
                guard await channels[exchange] != nil else { throw PisteInternalError.channelClosed }
                await removeChannel(exchange: exchange)
                await sendCatching(.payload(response), exchange: exchange)
            },
            close: { [weak self] in
                guard let self, await channels[exchange] != nil else { return }
                await removeChannel(exchange: exchange)
                await sendCatching(.close, exchange: exchange)
            },
            with: codec
        )
        channels[exchange] = channel
        await sendCatching(.open, exchange: exchange)
    }
    private func handleOpenStream(id: PisteId, exchange: PisteExchange) async throws {
        logger.info("Received Open Stream frame - id: \(id), exchange: \(exchange)")
        guard let handler = handlers[id] else { throw PisteError.unsupportedService }
        guard let streamHandler = handler as? any StreamPisteHandler else { throw PisteError.unsupportedFrameType }
        let channel = try await streamHandler.handleOpen(
            send: { [weak self] response in
                guard let self else { return }
                guard await channels[exchange] != nil else { throw PisteInternalError.channelClosed }
                try await send(.payload(response), exchange: exchange)
            },
            close: { [weak self] in
                guard let self, await channels[exchange] != nil else { return }
                await removeChannel(exchange: exchange)
                await sendCatching(.close, exchange: exchange)
            },
            with: codec
        )
        channels[exchange] = channel
        await sendCatching(.open, exchange: exchange)
    }
    private func handlePayload(payload: Data, exchange: PisteExchange) async throws {
        logger.info("Received Payload frame - payload count: \(payload.count), exchange: \(exchange)")
        guard let channel = channels[exchange] else { throw PisteError.channelClosed }
        try await channel.sendInbound(payload: payload, server: self)
    }
    private func handleClose(exchange: PisteExchange) async throws {
        logger.info("Received Close frame - exchange: \(exchange)")
        if channels[exchange] == nil { throw PisteError.channelClosed }
        await removeChannel(exchange: exchange)
    }
    private func handleSupportedServicesRequest(exchange: PisteExchange) async {
        logger.info("Received Supported Services Request frame - exchange: \(exchange)")
        await sendCatching(
            .supportedServicesResponse(
                services: handlers.values.map { PisteSupportedService(id: $0.id, type: $0.service.type) }
            ),
            exchange: exchange
        )
    }
    private func handleUnsupported(frame: PisteFrame, exchange: PisteExchange) async {
        logger.info("Received Unsupported frame - type: \(frame.type) exchange: \(exchange)")
        await sendCatching(.error(.unsupportedFrameType), exchange: exchange)
    }
    
    func handleDecode<T>(payload: Data) throws -> T {
        do {
            return try codec.decode(payload)
        } catch {
            logger.error("Failed to decode - payload count: \(payload.count), error: \(error)")
            throw PisteError.decodingFailed
        }
    }
    
    private func removeChannel(exchange: PisteExchange) async {
        if let channel = channels[exchange] {
            await channel.resumeClosed(error: nil)
            channels.removeValue(forKey: exchange)
        }
    }

    private func sendError(_ error: PisteError, exchange: PisteExchange) async {
        await sendCatching(.error(error), exchange: exchange)
    }
    private func sendCatching(_ frame: PisteFrame, exchange: PisteExchange) async {
        do {
            try await send(frame, exchange: exchange)
        } catch {
            logger.error("Caught Sending - frame: \(frame), exchange: \(exchange), error: \(error)")
        }
    }
    private func send(_ frame: PisteFrame, exchange: PisteExchange) async throws {
        logger.debug("Sending - frame: \(frame), exchange: \(exchange)")
        try await outbound(.init(exchange: exchange, frameData: frame.data))
    }
            
    public struct Outbound: Sendable {
        public let exchange: PisteExchange
        public let frameData: Data
    }
}

private extension StreamPisteHandler {
    func handleOpen(
        send: @Sendable @escaping (_ response: Data) async throws -> Void,
        close: @Sendable @escaping () async -> Void,
        with codec: PisteCodec
    ) async throws -> AnyPisteChannel {
        let channel = PisteChannel<Service.Serverbound, Service.Clientbound>(
            send: {
                try await send(try codec.encode($0))
            },
            close: { await close() }
        )
        try await handle(channel: StreamPisteHandlerChannel(channel: channel))
        
        return channel
    }
}
private extension UploadPisteHandler {
    func handleOpen(
        send: @Sendable @escaping (_ response: Data) async throws -> Void,
        close: @Sendable @escaping () async -> Void,
        with codec: PisteCodec
    ) async throws -> AnyPisteChannel {
        let channel = PisteChannel<Service.Serverbound, Service.Clientbound>(
            send: { try await send(try codec.encode($0)) },
            close: { await close() }
        )
        try await handle(channel: UploadPisteHandlerChannel(channel: channel))
        
        return channel
    }
}
private extension DownloadPisteHandler {
    func handleRequest(
        payload: Data,
        send: @Sendable @escaping (_ response: Data) async throws -> Void,
        close: @Sendable @escaping () async -> Void,
        server: PisteServer
    ) async throws -> AnyPisteChannel {
        let request: Service.Serverbound = try await server.handleDecode(payload: payload)
        let channel = PisteChannel<Service.Serverbound, Service.Clientbound>(
            send: { try await send(try server.codec.encode($0)) },
            close: close
        )
        
        try await handle(request: request, channel: DownloadPisteHandlerChannel(channel: channel))
        
        return channel
    }
}
private extension CallPisteHandler {
    func handleRequest(payload: Data, server: PisteServer) async throws -> Data {
        let request: Service.Serverbound = try await server.handleDecode(payload: payload)
        let response = try await handle(request: request)
        
        return try server.codec.encode(response)
    }
}
