//
//  ClientWebsocketHandshakeHandler.swift
//  test-client
//
//  Created by Corbin Bigler on 4/24/25.
//

import NIOCore
import NIOHTTP1

final class ClientWebsocketHandshakeHandler: ChannelInboundHandler, RemovableChannelHandler, Sendable {
    typealias InboundIn = HTTPClientResponsePart
    typealias InboundOut = HTTPClientRequestPart
    
    private let host: String
    private let port: Int
    private let path: String
    
    init(host: String, port: Int, path: String) {
        self.host = host
        self.port = port
        self.path = path
    }
    
    func channelActive(context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Host", value: "\(host):\(path)")
        
        let reqHead = HTTPRequestHead(
            version: .http1_1,
            method: .GET,
            uri: path,
            headers: headers
        )
        
        context.write(NIOAny(HTTPClientRequestPart.head(reqHead)), promise: nil)
        context.writeAndFlush(NIOAny(HTTPClientRequestPart.end(nil)), promise: nil)
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {}
}
