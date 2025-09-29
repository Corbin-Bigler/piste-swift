//
//  PisteServer.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

import Foundation
import Logger

public actor PisteServer: Sendable {
    let logger: Logger
    let codec: PisteCodec
    
    public typealias Outbound = (exchange: PisteExchange, frame: Data)
    private var outbound: @Sendable (Outbound) async throws -> Void = {_ in}
    
    private let handlers: [PisteId: any PisteHandler]
    private var channels: [PisteExchange: AnyPisteChannel] = [:]
    
    public init(codec: PisteCodec, handlers: [any PisteHandler], logger: Logger = Logger.shared) {
        self.codec = codec
        self.logger = logger
        
        let reservedIds: Set<PisteId> = [PisteServiceInformationService.id]
        var handlersDictionary: [PisteId : any PisteHandler] = handlers.reduce(into: [:]) { dict, handler in
            guard !reservedIds.contains(handler.id) else {
                assertionFailure("Trying to register handler with reserved id: \(handler.id)")
                return
            }
            guard dict[handler.id] == nil else {
                assertionFailure("Handler for id: \(handler.id) already registered (this is a bug)")
                return
            }
            dict[handler.id] = handler
        }
        handlersDictionary[PisteServiceInformationService.id] = PisteServiceInformationHandler(otherHandlers: handlers)
        self.handlers = handlersDictionary
    }
    
    deinit { _cancelAll(channels: self.channels) }
    
    func cancelAll() {
        _cancelAll(channels: self.channels)
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
        case .request(let id, let payload):
            logger.info("Received request for service \(id) on exchange \(exchange)")
            guard let handler = handlers[id] else {
                await attemptSend(.error(.unsupportedService), exchange: exchange)
                return
            }
            await handleRequest(handler: handler, exchange: exchange, payload: payload)
        case .open(let id):
            logger.info("Received open request for service \(id) on exchange \(exchange)")
            guard let handler = handlers[id] else {
                await attemptSend(.error(.unsupportedService), exchange: exchange)
                return
            }
            await handleOpen(handler: handler, exchange: exchange)
        case .error(let error):
            logger.error("Received error frame on exchange \(exchange): \(error)")
            await attemptSend(.error(.invalidFrameType), exchange: exchange)
        case .payload(let payload):
            logger.debug("Received payload (\(payload.count) bytes) on exchange \(exchange)")
            await handlePayload(exchange: exchange, payload: payload)
        case .close:
            logger.info("Received close frame for exchange \(exchange)")
            guard let channel = channels[exchange] else {
                await attemptSend(.error(.channelClosed), exchange: exchange)
                return
            }
            removeChannel(exchange: exchange)
            await channel.resumeClosed(error: nil)
        case .opened:
            logger.error("Unexpected .opened frame on server for exchange \(exchange)")
            await attemptSend(.error(.invalidAction), exchange: exchange)
        }
    }
    
    private func handleRequest(handler: any PisteHandler, exchange: PisteExchange, payload: Data) async {
        do {
            if let callHandler = handler as? any CallPisteHandler {
                logger.debug("Handling call request for exchange \(exchange)")
                let response = try await callHandler.handleRequest(data: payload, with: codec)
                await attemptSend(.payload(response), exchange: exchange)
                logger.debug("Completed call request for exchange \(exchange)")
            } else if let downloadHandler = handler as? any DownloadPisteHandler {
                logger.debug("Handling download request for exchange \(exchange)")
                let channel = try await downloadHandler.handleRequest(
                    data: payload,
                    send: { [weak self] response in
                        guard let self, await channels[exchange] != nil else { throw PisteError.channelClosed }
                        try await send(.payload(response), exchange: exchange)
                    },
                    close: { [weak self] in
                        guard let self, await channels[exchange] != nil else { return }
                        await removeChannel(exchange: exchange)
                        await attemptSend(.close, exchange: exchange)
                    },
                    with: codec
                )
                
                channels[exchange] = channel
                await attemptSend(.opened, exchange: exchange)
                logger.debug("Opened download channel for exchange \(exchange)")
                await channel.resumeOpened()
            } else {
                throw PisteError.invalidFrameType
            }
        } catch {
            logger.error("Error handling request on exchange \(exchange): \(error)")
            let error = error as? PisteError ?? .unhandledError
            await attemptSend(.error(error), exchange: exchange)
        }
    }
        
    private func handlePayload(exchange: PisteExchange, payload: Data) async {
        logger.debug("Handling inbound payload on exchange \(exchange)")

        do {
            if let channel = channels[exchange] {
                try await channel.yieldInbound(data: payload, with: codec)
            } else {
                logger.error("No channel found for exchange \(exchange) when handling payload")
            }
        } catch {
            logger.error("Error handling payload on exchange \(exchange): \(error)")
            let error = error as? PisteError ?? .unhandledError
            await attemptSend(.error(error), exchange: exchange)
       }
    }
    
    private func handleOpen(handler: any PisteHandler, exchange: PisteExchange) async {
        logger.debug("Opening channel for exchange \(exchange)")
        do {
            if let uploadHandler = handler as? any UploadPisteHandler {
                let channel = try await uploadHandler.handleRequest(
                    send: { [weak self] response in
                        guard let self, await channels[exchange] != nil else { throw PisteError.channelClosed }
                        await removeChannel(exchange: exchange)
                        await attemptSend(.payload(response), exchange: exchange)
                    },
                    close: { [weak self] in
                        guard let self, await channels[exchange] != nil else { return }
                        await removeChannel(exchange: exchange)
                        await attemptSend(.close, exchange: exchange)
                    },
                    with: codec
                )
                
                channels[exchange] = channel
                await attemptSend(.opened, exchange: exchange)
            } else if let streamHandler = handler as? any StreamPisteHandler {
                let channel = try await streamHandler.handleRequest(
                    send: { [weak self] response in
                        guard let self, await channels[exchange] != nil else { throw PisteError.channelClosed }
                        try await send(.payload(response), exchange: exchange)
                    },
                    close: { [weak self] in
                        guard let self, await channels[exchange] != nil else { return }
                        await removeChannel(exchange: exchange)
                        await attemptSend(.close, exchange: exchange)
                    },
                    with: codec
                )
                
                channels[exchange] = channel
                await attemptSend(.opened, exchange: exchange)
            } else {
                throw PisteError.invalidFrameType
            }
            logger.debug("Channel opened for exchange \(exchange)")
        } catch {
            logger.error("Error opening channel on exchange \(exchange): \(error)")
            let error = error as? PisteError ?? .unhandledError
            await attemptSend(.error(error), exchange: exchange)
        }
    }

    private func attemptSend(_ frame: PisteFrame, exchange: PisteExchange) async {
        do {
            try await send(frame, exchange: exchange)
        } catch {
            logger.error("Failed attempting to sending frame \(frame) on exchange \(exchange) with error \(error)")
        }
    }
    private func send(_ frame: PisteFrame, exchange: PisteExchange) async throws {
        logger.debug("Sending frame \(frame) on exchange \(exchange)")
        try await outbound((exchange: exchange, frame: frame.data))
    }
    
    private func removeChannel(exchange: PisteExchange) {
        logger.debug("Removing channel for exchange \(exchange)")
        channels.removeValue(forKey: exchange)
    }
    
    private nonisolated func _cancelAll(
        channels: [PisteExchange: AnyPisteChannel]
    ) {
        logger.info("Cancelling all channels (\(channels.count)) on server")

        Task {
            for exchange in channels.keys {
                await channels[exchange]!.resumeClosed(error: PisteInternalError.cancelled)
                try? await outbound((exchange, PisteFrame.close.data))
            }
        }
    }
    
    static func decode<T>(data: Data, with codec: PisteCodec) throws -> T {
        if T.self == Void.self {
            guard data.count == 0 else { throw PisteError.decodingFailed }
            
            return Void() as! T
        } else {
            do {
                return try codec.decode(data)
            } catch {
                throw PisteError.decodingFailed
            }
        }
    }
}

private extension StreamPisteHandler {
    func handleRequest(
        send: @Sendable @escaping (_ response: Data) async throws -> Void,
        close: @Sendable @escaping () async -> Void,
        with codec: PisteCodec
    ) async throws -> AnyPisteChannel {
        let channel = PisteChannel<Service.Serverbound, Service.Clientbound>(
            send: { try await send(try codec.encode($0)) },
            close: { await close() }
        )
        try await handle(channel: StreamPisteHandlerChannel(channel: channel))
        
        return channel
    }
}
private extension UploadPisteHandler {
    func handleRequest(
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
        data: Data,
        send: @Sendable @escaping (_ response: Data) async throws -> Void,
        close: @Sendable @escaping () async -> Void,
        with codec: PisteCodec
    ) async throws -> AnyPisteChannel {
        let request: Service.Serverbound = try PisteServer.decode(data: data, with: codec)
        let channel = PisteChannel<Service.Serverbound, Service.Clientbound>(
            send: { try await send(try codec.encode($0)) },
            close: close
        )
        
        try await handle(request: request, channel: DownloadPisteHandlerChannel(channel: channel))
        
        return channel
    }
}
private extension CallPisteHandler {
    func handleRequest(data: Data, with codec: PisteCodec) async throws -> Data {
        let request: Service.Serverbound = try PisteServer.decode(data: data, with: codec)
        let response = try await handle(request: request)
        
        return try codec.encode(response)
    }
}
