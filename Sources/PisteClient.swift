//
//  PisteClient.swift
//  piste
//
//  Created by Corbin Bigler on 4/23/25.
//

import NIO
import NIOHTTP1
import NIOWebSocket
import Foundation
import Combine

//final class WebSocketClientHandler: ChannelInboundHandler, Sendable {
//    typealias InboundIn = WebSocketFrame
//
//    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
//        let frame = self.unwrapInboundIn(data)
//        var data = frame.unmaskedData ?? ByteBuffer()
//        if let text = data.readString(length: data.readableBytes) {
//            print("Received: \(text)")
//        }
//    }
//
//    func handlerAdded(context: ChannelHandlerContext) {
//        print("WebSocket client handler added.")
//    }
//
//    func errorCaught(context: ChannelHandlerContext, error: Error) {
//        print("Error: \(error)")
//        context.close(promise: nil)
//    }
//}

public final class PisteClient {
    private let group: MultiThreadedEventLoopGroup = .singleton
    private let host: String
    private let port: Int
    private var channel: (any Channel)? = nil

    public let isConnected = PassthroughSubject<Bool, Never>()
    public let receivedText = PassthroughSubject<String, Never>()

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    public func connect() async throws {
        let upgradeResult: EventLoopFuture<UpgradeResult> = try await ClientBootstrap(group: self.group)
            .connect(host: host, port: port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    let upgrader = NIOTypedWebSocketClientUpgrader<UpgradeResult>(
                        upgradePipelineHandler: { channel, _ in
                            channel.eventLoop.makeCompletedFuture {
                                let asyncChannel = try NIOAsyncChannel<WebSocketFrame, WebSocketFrame>(
                                    wrappingChannelSynchronously: channel
                                )
                                return UpgradeResult.websocket(asyncChannel)
                            }
                        }
                    )

                    var headers = HTTPHeaders()
                    headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
                    headers.add(name: "Content-Length", value: "0")

                    let head = HTTPRequestHead(
                        version: .http1_1,
                        method: .GET,
                        uri: "/",
                        headers: headers
                    )

                    let upgradeConfig = NIOTypedHTTPClientUpgradeConfiguration(
                        upgradeRequestHead: head,
                        upgraders: [upgrader],
                        notUpgradingCompletionHandler: { channel in
                            channel.eventLoop.makeCompletedFuture {
                                UpgradeResult.notUpgraded
                            }
                        }
                    )

                    return try channel.pipeline.syncOperations
                        .configureUpgradableHTTPClientPipeline(
                            configuration: .init(upgradeConfiguration: upgradeConfig)
                        )
                }
            }

        try await handleUpgradeResult(upgradeResult)
    }

    public func disconnect() {
        Task {
            try? await channel?.close()
            isConnected.send(false)
        }
    }

    public func send(data: Data) async throws {
        guard let channel = channel else { throw WebSocketError.notConnected }
        let buffer = ByteBuffer(bytes: data)
        let frame = WebSocketFrame(fin: true, opcode: .binary, data: buffer)
        try await channel.write(frame)
    }

    private func handleUpgradeResult(_ future: EventLoopFuture<UpgradeResult>) async throws {
        switch try await future.get() {
        case .websocket(let wsChannel):
            self.channel = wsChannel.channel
            isConnected.send(true)
            Task {
                await listen(wsChannel)
            }
        case .notUpgraded:
            throw WebSocketError.upgradeFailed
        }
    }

    private func listen(_ channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>) async {
        do {
            for try await frame in channel.inbound {
                switch frame.opcode {
                case .text:
                    if let text = frame.data.getString(at: 0, length: frame.data.readableBytes) {
                        receivedText.send(text)
                    }
                case .pong:
                    print("Pong received.")
                case .connectionClose:
                    print("Connection closed by server.")
                    isConnected.send(false)
                    return
                default:
                    break
                }
            }
        } catch {
            print("Error while listening: \(error)")
            isConnected.send(false)
        }
    }

    enum WebSocketError: Error {
        case notConnected
        case upgradeFailed
    }

    enum UpgradeResult {
        case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
        case notUpgraded
    }
}
