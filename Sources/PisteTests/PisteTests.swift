//
//  Piste.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/4/25.
//

@testable import Piste
import Testing
import Foundation
import Combine
import SwiftCBOR

struct PisteTests {
    static let testPrefix = String(describing: UUID())
    
    struct MockCallService: RPCCallService {
        static let id: String = "mock.call.service"
        struct Request: Codable, Equatable, Sendable {
            let message: String
        }
        struct Response: Codable, Equatable, Sendable {
            let message: String
        }
    }
    final class MockCallServiceHandler: PisteCallHandler {
        typealias Service = MockCallService
        
        let title: String = "Mock Service"
        let description: String = "Mock service description"
        let deprecated: Bool = false
        
        func handle(request: PisteTests.MockCallService.Request) async throws -> PisteTests.MockCallService.Response {
            return .init(message: "\(PisteTests.testPrefix)\(request.message)")
        }
    }
    
    @Test
    func callTests() async {
        do {
            let server = PisteServer()
            try await server.register(MockCallServiceHandler())
            
            let client = PisteClient()
            
            await withCheckedContinuation { continuation in
                Task {
                    for await data in await SignalableAsyncStream(client.onData, onStart: continuation.resume) {
                        await server.handle(data: data)
                    }
                }
            }
            await withCheckedContinuation { continuation in
                Task {
                    for await data in await SignalableAsyncStream(server.onData, onStart: continuation.resume) {
                        await client.handle(data: data)
                    }
                }
            }
            
            let message = "hello"
            let result = try await client.call(.init(message: message), for: MockCallService.self)
            #expect(result.message == "\(Self.testPrefix)\(message)")
        } catch {
            #expect(Bool(false), "\(error)")
        }
    }
    
    static let testDownloadRequest = UUID()
    static let testDownload = [UUID(), UUID(), UUID(), UUID()]
    struct MockDownloadService: RPCDownloadService {
        static let id: String = "mock.download.service"
        struct Request: Codable, Equatable, Sendable {
            let uuid: UUID
        }
        struct Response: Codable, Equatable, Sendable {
            let uuid: UUID
        }
    }
    final class MockDownloadServiceHandler: PisteDownloadHandler {
        typealias Service = MockDownloadService
        
        let title: String = "Mock Service"
        let description: String = "Mock service description"
        let deprecated: Bool = false
        
        func handle(request: PisteTests.MockDownloadService.Request, stream: any RPCOutboundStream) throws {
            if request.uuid == PisteTests.testDownloadRequest {
                for uuid in PisteTests.testDownload {
                    try stream.send(.init(uuid: uuid))
                }
            }
        }
    }

    @Test
    func downloadTests() async {
        do {
            let server = PisteServer()
            try await server.register(MockCallServiceHandler())
            
            let client = PisteClient()
            
            await withCheckedContinuation { continuation in
                Task {
                    for await data in await SignalableAsyncStream(client.onData, onStart: continuation.resume) {
                        await server.handle(data: data)
                    }
                }
            }
            await withCheckedContinuation { continuation in
                Task {
                    for await data in await SignalableAsyncStream(server.onData, onStart: continuation.resume) {
                        await client.handle(data: data)
                    }
                }
            }
            
            let message = "hello"
            let result = try await client.call(.init(message: message), for: MockCallService.self)
            #expect(result.message == "\(Self.testPrefix)\(message)")
        } catch {
            #expect(Bool(false), "\(error)")
        }
    }
}
