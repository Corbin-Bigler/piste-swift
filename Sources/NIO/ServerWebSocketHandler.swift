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
    private var handlers: [String: [Int : any PisteHandler]] = [:]
    
    init(server: PisteServer) {
        self.server = server
    }

    private func write(context: ChannelHandlerContext, error: PisteErrorFrame) {
        if let data = try? CodableCBOREncoder().encode(error) {
            var buffer = context.channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            context.writeAndFlush(NIOAny(WebSocketFrame(fin: true, opcode: .binary, data: buffer)), promise: nil)
        }
    }
    private func handle<Handler: PisteHandler>(_ data: Data, context: ChannelHandlerContext, for handler: Handler.Type) {
        
        let context = PisteContext<Handler.Service>(context: context, server: server)
        guard let serverbound = try? decoder.decode(PisteFrame<Handler.Service.Serverbound>.self, from: data).payload else {
            context.error(PisteServerError.badPayload.id, message: PisteServerError.badPayload.message)
            return
        }
        
        if handlers[handler.id]?[handler.version] == nil {
            handlers[handler.id, default: [:]][handler.version] = handler.init(context: context)
        }
        
        do {
            try (handlers[handler.id]![handler.version]! as! Handler).handle(serverbound: serverbound)
        } catch {
            if let pisteError = error as? any PisteError {
                context.error(pisteError.id, message: pisteError.message)
            } else {
                Logger.error("Unknown error caught: \(error)")
                context.error(PisteServerError.internalServerError.id, message: PisteServerError.internalServerError.message)
            }
        }
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
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
            guard let serviceVersions = server.handlers[headers.service] else {
                let error = PisteServerError.unsupportedService(service: headers.service)
                write(
                    context: context,
                    error: PisteErrorFrame(error: error.id, service: headers.service, version: headers.version, message: error.message)
                )
                return
            }
            guard let handler = serviceVersions[headers.version] else {
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

