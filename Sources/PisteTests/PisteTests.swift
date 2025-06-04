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
    static let testPrefix = "4234798"
    
    struct MockService: RPCCallService {
        static let id: String = "mock.service"
        struct Request: Codable, Equatable, Sendable {
            let message: String
        }
        struct Response: Codable, Equatable, Sendable {
            let message: String
        }
    }
    final class MockServiceHandler: PisteCallHandler {
        typealias Service = MockService
        
        let title: String = "Mock Service"
        let description: String = "Mock service description"
        let deprecated: Bool = false
        
        func handle(request: PisteTests.MockService.Request) async throws -> PisteTests.MockService.Response {
            return .init(message: "\(PisteTests.testPrefix)\(request.message)")
        }
    }
    
    @Test
    func testSetMaximumPacketSizeDoesNotCrash() async {
        do {
            let server = PisteServer()
            try await server.register(MockServiceHandler())
            
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
            let result = try await client.call(.init(message: message), for: MockService.self)
            
            #expect(result.message == "\(Self.testPrefix)\(message)")
        } catch {
            #expect(Bool(false), "\(error)")
        }
    }
}
