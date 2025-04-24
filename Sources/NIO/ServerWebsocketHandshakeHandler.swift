//
//  ServerWebsocketHandshakeHandler.swift
//  piste
//
//  Created by Corbin Bigler on 4/24/25.
//

import NIOCore
import NIOHTTP1

final class ServerWebsocketHandshakeHandler: ChannelInboundHandler, RemovableChannelHandler, Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    let path: String
    init(path: String) {
        self.path = path
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        
        if case .head(let head) = part {
            if head.uri != path {
                let responseHead = HTTPResponseHead(version: head.version, status: .notFound)
                context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
                context.write(wrapOutboundOut(.end(nil)), promise: nil)
                context.flush()
                context.close(promise: nil)
                return
            }
        }

        context.fireChannelRead(data)
    }
}
