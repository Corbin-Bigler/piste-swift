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
    private func handle<Handler: PisteHandler>(_ data: Data, context: ChannelHandlerContext, for handler: Handler) {
        guard let connection else { return }
        let pisteChannel = PisteChannel<Handler.Service>(context: context)
        guard let serverbound = try? decoder.decode(PisteFrame<Handler.Service.Serverbound>.self, from: data).payload else {
            pisteChannel.error(PisteServerError.badPayload.id, message: PisteServerError.badPayload.message)
            return
        }

        do {
            try (connection.handlers[handler.id]![handler.version]! as! Handler).handle(channel: pisteChannel, inbound: serverbound)
        } catch {
            if let pisteError = error as? any PisteError {
                pisteChannel.error(pisteError.id, message: pisteError.message)
            } else {
                Logger.error("Unknown error caught: \(error)")
                pisteChannel.error(PisteServerError.internalServerError.id, message: PisteServerError.internalServerError.message)
            }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard let connection else { return }
        let frame = unwrapInboundIn(data)

        if frame.opcode == .binary {
            var buffer = frame.unmaskedData
            guard let data = buffer.readBytes(length: buffer.readableBytes).flatMap({ Data($0) }) else {
                return
            }
            guard let headers = try? decoder.decode(PisteFrameHeader.self, from: data) else {
                write(context: context, error: PisteErrorFrame(error: "bad-frame", message: "Invalid frame format"))
                return
            }
            guard let handlerVersions = connection.handlers[headers.service] else {
                let error = PisteServerError.unsupportedService(service: headers.service)
                write(
                    context: context,
                    error: PisteErrorFrame(error: error.id, service: headers.service, version: headers.version, message: error.message)
                )
                return
            }
            guard let handler = handlerVersions[headers.version] else {
                let error = PisteServerError.unsupportedVersion(service: headers.service, version: headers.version)
                write(
                    context: context,
                    error: PisteErrorFrame(error: error.id, service: headers.service, version: headers.version, message: error.message)
                )
                return
            }

            handle(data, context: context, for: handler)
        }
    }
}

