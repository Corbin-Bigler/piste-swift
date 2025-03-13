//
//  PisteClientHandler.swift
//  piste
//
//  Created by Corbin Bigler on 3/11/25.
//

import Foundation
import NIO
import NIOSSL

final class PisteClientHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = EncodedPisteFrame
    typealias OutboundOut = EncodedPisteFrame

    private var context: ChannelHandlerContext?

    func write(frame: EncodedPisteFrame) {
        guard let context = self.context else { return }
        context.eventLoop.execute {
            context.writeAndFlush(self.wrapOutboundOut(frame), promise: nil)
        }
    }
    
    func channelActive(context: ChannelHandlerContext) {
        print("Connected to server")
        self.context = context
    }
    func channelInactive(context: ChannelHandlerContext) {
        print("Disconnected from server")
        self.context = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = self.unwrapInboundIn(data)
        print("Received frame: \(frame)")
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Error: \(error)")
        context.close(promise: nil)
    }
}
