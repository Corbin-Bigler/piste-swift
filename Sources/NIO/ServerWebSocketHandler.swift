//
//  ServerWebSocketHandler.swift
//  piste
//
//  Created by Corbin Bigler on 4/24/25.
//

import Foundation
import NIOCore
import NIOWebSocket
import SwiftCBOR
import SwiftLogger

final class ServerWebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias InboundOut = WebSocketFrame
    
    private let decoder = CodableCBORDecoder()
    
    private let server: PisteServer
    private var connection: PisteConnection?
    
    init(server: PisteServer) {
        self.server = server
    }
    
    func handlerAdded(context: ChannelHandlerContext) {
        let connection = PisteConnection(context: context)
        
        self.server.builder(connection)
        self.connection = connection
    }
    
    private func write(context: ChannelHandlerContext, error: PisteErrorFrame) {
        if let data = try? CodableCBOREncoder().encode(error) {
            var buffer = context.channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            context.writeAndFlush(NIOAny(WebSocketFrame(fin: true, opcode: .binary, data: buffer)), promise: nil)
        }
    }
    private func handle<Handler: TransientPisteHandler>(_ data: Data, context: ChannelHandlerContext, for handler: Handler) {
        guard let connection,
              let (channel, serverbound): (PisteChannel<Handler.Service>, Handler.Service.Serverbound) = decodePayload(data, context: context)
        else { return }
        
        _ = context.eventLoop.makeFutureWithTask {
            do {
                channel.respond(with: try await (connection.transientHandlers[handler.id]![handler.version]! as! Handler).handle(inbound: serverbound))
            } catch {
                self.handleError(error, pisteChannel: channel)
            }
        }
    }
    private func handle<Handler: PersistentPisteHandler>(_ data: Data, context: ChannelHandlerContext, for handler: Handler) {
        guard let connection,
              let (channel, serverbound): (PisteChannel<Handler.Service>, Handler.Service.Serverbound) = decodePayload(data, context: context)
        else { return }
        
        do {
            try (connection.persistentHandlers[handler.id]![handler.version]! as! Handler).handle(channel: channel, inbound: serverbound)
        } catch {
            handleError(error, pisteChannel: channel)
        }
    }
    
    private func handleError<Service>(_ error: Error, pisteChannel: PisteChannel<Service>) {
        if let pisteError = error as? any PisteError {
            pisteChannel.error(pisteError.id, message: pisteError.message)
        } else {
            Logger.error("Unknown error caught: \(error)")
            pisteChannel.error(PisteServerError.internalServerError.id, message: PisteServerError.internalServerError.message)
        }
    }
    private func decodePayload<Service>(_ data: Data, context: ChannelHandlerContext) -> (PisteChannel<Service>, Service.Serverbound)? {
        let channel = PisteChannel<Service>(context: context)
        guard let payload = try? decoder.decode(PisteFrame<Service.Serverbound>.self, from: data).payload else {
            channel.error(PisteServerError.badPayload.id, message: PisteServerError.badPayload.message)
            return nil
        }
        return (channel, payload)
    }
    
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard let connection else { return }
        let frame = unwrapInboundIn(data)
        
        guard frame.opcode == .binary else { return }
        
        var buffer = frame.unmaskedData
        guard let data = buffer.readBytes(length: buffer.readableBytes).map({ Data($0) }) else { return }
        
        guard let headers = try? decoder.decode(PisteFrameHeader.self, from: data) else {
            write(context: context, error: .init(error: "bad-frame", message: "Invalid frame format"))
            return
        }
        
        if let handler = connection.transientHandlers[headers.service]?[headers.version] {
            handle(data, context: context, for: handler)
        } else if let handler = connection.persistentHandlers[headers.service]?[headers.version] {
            handle(data, context: context, for: handler)
        } else {
            let error = connection.transientHandlers[headers.service] == nil &&
            connection.persistentHandlers[headers.service] == nil
            ? PisteServerError.unsupportedService(service: headers.service)
            : PisteServerError.unsupportedVersion(service: headers.service, version: headers.version)
            write(context: context, error: .init(error: error.id, service: headers.service, version: headers.version, message: error.message))
        }
    }
}

