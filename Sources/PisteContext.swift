//
//  PisteContext.swift
//  piste
//
//  Created by Corbin Bigler on 4/23/25.
//

import SwiftLogger
import NIOCore
import NIOWebSocket
import SwiftCBOR

public struct PisteContext<Handler: PisteHandler> {
    private let context: ChannelHandlerContext
    let server: PisteServer
    
    init(context: ChannelHandlerContext, server: PisteServer) {
        self.context = context
        self.server = server
    }
    
    private func write<Frame: Codable>(frame: Frame) {
        do {
            let data = try CodableCBOREncoder().encode(frame)
            var buffer = context.channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            context.writeAndFlush(NIOAny(WebSocketFrame(fin: true, opcode: .binary, data: buffer)), promise: nil)
        } catch {
            Logger.fault(error)
        }
    }
    
    public func close() {
        _ = context.close()
    }
    public func respond(with payload: Handler.Service.Clientbound) {
        write(frame: Handler.Service.clientbound(payload))
    }
    public func error(_ error: String, message: String? = nil) {
        write(frame: Handler.Service.error(error, message: message))
    }
}
