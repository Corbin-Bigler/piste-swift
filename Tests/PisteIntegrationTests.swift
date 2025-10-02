//
//  PisteIntegrationTests.swift
//  Piste
//
//  Created by Corbin Bigler on 10/2/25.
//

import Testing
import Foundation
@testable import Piste

final class PisteIntegrationTests {
    
    private struct EchoService: CallPisteService {
        typealias Serverbound = String
        typealias Clientbound = String
        
        static let id: PisteId = 0
    }
    private struct EchoHandler: CallPisteHandler {
        let service = EchoService.self
        
        func handle(request: String) async throws -> String {
            return "echo:\(request)"
        }
    }
    
    private func buildClient(handlers: [any PisteHandler]) async -> PisteClient {
        let server = PisteServer(codec: JsonPisteCodec(), handlers: handlers)
        let client = PisteClient(codec: JsonPisteCodec())
        
        await server.onOutbound { outbound in
            await client.handle(exchange: outbound.exchange, frame: outbound.frameData)
        }
        await client.onOutbound { outbound in
            await server.handle(exchange: outbound.exchange, frame: outbound.frameData)
        }
        
        return client
    }
    
    @Test func clientCallReturnsHandlerResponse() async throws {
        let handler = EchoHandler()
        let client = await buildClient(handlers: [handler])
        
        let response = try await client.call(handler.service, request: "hello world")
        #expect(response == "echo:hello world", "Client should receive server's handler response")
    }
    
    @Test func clientDownloadReceivesStreamedResponses() async throws {
        struct EchoService: DownloadPisteService {
            typealias Serverbound = String
            typealias Clientbound = String
            
            static let id: PisteId = 0
        }
        struct DownloadHandler: DownloadPisteHandler {
            let service = EchoService.self
            
            func handle(request: String, channel: Piste.DownloadPisteHandlerChannel<EchoService>) async throws {
                Task {
                    try await channel.send("chunk1-\(request)")
                    try await channel.send("chunk2-\(request)")
                    await channel.close()
                }
            }
        }
        
        let handler = DownloadHandler()
        let client = await buildClient(handlers: [handler])
        
        let downloadChannel = try await client.download(handler.service, request: "file123")
        
        var received: [String] = []
        for await value in downloadChannel.inbound {
            received.append(value)
        }
        
        #expect(received == ["chunk1-file123", "chunk2-file123"])
    }
    
    @Test func clientUploadSendsDataAndReceivesResponse() async throws {
        struct UploadService: UploadPisteService {
            typealias Serverbound = String
            typealias Clientbound = String
            
            static let id: PisteId = 0
        }
        actor UploadHandler: UploadPisteHandler {
            let service = UploadService.self
            var received: [String] = []
            
            func handle(channel: UploadPisteHandlerChannel<UploadService>) async throws {
                Task {
                    do {
                        for try await msg in channel.inbound {
                            self.received.append(msg)
                            if msg == "part2" {
                                try await channel.complete(response: "ack:\(msg)")
                            }
                        }
                    } catch { }
                }
            }
        }
        
        let handler = UploadHandler()
        let client = await buildClient(handlers: [handler])
        
        let uploadChannel = try await client.upload(handler.service)
        
        let completionTask = Task<String, Error> {
            await uploadChannel.completed
        }
        
        try await uploadChannel.send("part1")
        try await uploadChannel.send("part2")
        
        let response = try await completionTask.value
        let received = await handler.received
        #expect(received == ["part1", "part2"])
        #expect(response == "ack:part2")
    }
    
    @Test func clientAndServerExchangeMessagesOverStream() async throws {
        struct StreamService: StreamPisteService {
            typealias Serverbound = String
            typealias Clientbound = String
            
            static let id: PisteId = 0
        }
        actor StreamHandler: StreamPisteHandler {
            let service = StreamService.self
            var received: [String] = []
            
            func handle(channel: StreamPisteHandlerChannel<StreamService>) async throws {
                Task {
                    for try await msg in channel.inbound {
                        self.received.append(msg)
                        try? await channel.send("echo:\(msg)")
                    }
                }
            }
        }
        
        let handler = StreamHandler()
        let client = await buildClient(handlers: [handler])
        
        let streamChannel = try await client.stream(handler.service)
        var responses: [String] = []
        
        let reader = Task { @Sendable in
            for await resp in streamChannel.inbound {
                await MainActor.run { responses.append(resp) }
                let responses = await MainActor.run { responses }
                if responses.count == 3 {
                    await streamChannel.close()
                }
            }
            print("asdf")
        }
        
        try await streamChannel.send("one")
        try await streamChannel.send("two")
        try await streamChannel.send("three")
        
        _ = await reader.result
        
        let received = await handler.received
        #expect(received == ["one", "two", "three"])
        #expect(responses == ["echo:one", "echo:two", "echo:three"])
    }
}

