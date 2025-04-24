//
//  PisteContext.swift
//  piste
//
//  Created by Corbin Bigler on 4/23/25.
//

import SwiftLogger
@preconcurrency import NIOCore
import NIOWebSocket
@preconcurrency import SwiftCBOR

public struct PisteContext<Service: PisteService>: @unchecked Sendable {
    private let context: ChannelHandlerContext
    let server: PisteServer
    
    init(context: ChannelHandlerContext, server: PisteServer) {
        self.context = context
        self.server = server
    }
    
    private func write<Frame: Codable & Sendable>(frame: Frame) {
        context.eventLoop.execute {
            do {
                let data = try CodableCBOREncoder().encode(frame)
                var buffer = context.channel.allocator.buffer(capacity: data.count)
                buffer.writeBytes(data)
                
                context.writeAndFlush(NIOAny(WebSocketFrame(fin: true, opcode: .binary, data: buffer)), promise: nil)
            } catch {
                Logger.fault(error)
            }
        }
    }
    
    public func close() {
        context.eventLoop.execute {
            _ = context.close()
        }
    }
    public func respond(with payload: Service.Clientbound) {
        context.eventLoop.execute {
            write(frame: Service.clientbound(payload))
        }
    }
    public func error(_ error: String, message: String? = nil) {
        context.eventLoop.execute {
            write(frame: Service.error(error, message: message))
        }
    }
}
