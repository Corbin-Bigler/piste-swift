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

public class PisteChannel<Service: PisteService>: @unchecked Sendable {
    private let context: ChannelHandlerContext
    
    init(context: ChannelHandlerContext) {
        self.context = context
    }
    
    private func write<Frame: Codable & Sendable>(frame: Frame) {
        context.eventLoop.execute {
            do {
                let data = try CodableCBOREncoder().encode(frame)
                var buffer = self.context.channel.allocator.buffer(capacity: data.count)
                buffer.writeBytes(data)
                
                self.context.writeAndFlush(NIOAny(WebSocketFrame(fin: true, opcode: .binary, data: buffer)), promise: nil)
            } catch {
                Logger.fault(error)
            }
        }
    }
    
    public func respond(with payload: Service.Clientbound) {
        context.eventLoop.execute {
            self.write(frame: Service.clientbound(payload))
        }
    }
    
    public func respond() where Service.Clientbound == Empty {
        respond(with: Empty())
    }

    public func error(_ error: String, message: String? = nil) {
        context.eventLoop.execute {
            self.write(frame: Service.error(error, message: message))
        }
    }
}
