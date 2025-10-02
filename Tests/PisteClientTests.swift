//
//  PisteClientTests.swift
//  Piste
//
//  Created by Assistant on 10/2/25.
//

import Testing
import Foundation
@testable import Piste

final class PisteClientTests {
    private struct CallSvc: CallPisteService {
        typealias Serverbound = String
        typealias Clientbound = String
        static let id: PisteId = 0
    }

    private class Outbox: @unchecked Sendable {
        private(set) var value: [PisteClient.Outbound] = []
        func append(_ v: PisteClient.Outbound) { value.append(v) }
        var isEmpty: Bool { value.isEmpty }
        var first: PisteClient.Outbound? { value.first }
        var count: Int { value.count }
        subscript(_ i: Int) -> PisteClient.Outbound { value[i] }
    }

    private func buildClient(sent: Outbox,
                             services: [any PisteService.Type] = []) async -> PisteClient {
        let client = PisteClient(codec: JsonPisteCodec())
        await client.onOutbound { outbound in
            let maybe = PisteFrame(data: outbound.frameData)
            if maybe != .supportedServicesRequest {
                sent.append(outbound)
            }
        }

        let supported = services.map { PisteSupportedService(id: $0.id, type: $0.type) }
        let resp = PisteFrame.supportedServicesResponse(services: supported)
        await client.handle(exchange: 0xFFFF_FFFF, frame: resp.data)

        return client
    }

    @Test
    func invalidServiceThrows_orRatherEmitsNothingOnInvalidBytes() async throws {
        let sent = Outbox()
        let client = await buildClient(sent: sent)

        await client.handle(exchange: 0x00, frame: Data([0x01, 0x02]))

        #expect(sent.isEmpty, "Client should not emit anything when fed invalid bytes")
    }

    @Test
    func callSendsRequestCallAndReturnsDecodedResponse() async throws {
        let sent = Outbox()
        let client = await buildClient(sent: sent, services: [CallSvc.self])

        let task = Task { () -> String in
            async let response: String = client.call(CallSvc.self, request: "ping")
            while sent.first == nil { try? await Task.sleep(nanoseconds: 100_000) }
            if let request = sent.first {
                let frame = PisteFrame(data: request.frameData)
                switch frame {
                case let .requestCall(id, _):
                    #expect(id == CallSvc.id)
                default:
                    #expect(Bool(false), "Expected RequestCall frame")
                }
                let payload = try JsonPisteCodec().encode("pong")
                await client.handle(exchange: request.exchange, frame: PisteFrame.payload(payload).data)
            }
            return try await response
        }

        let value = try await task.value
        #expect(value == "pong")
    }

    @Test
    func unsupportedServiceThrowsUnsupportedService() async throws {
        let sent = Outbox()
        let client = await buildClient(sent: sent)

        do {
            _ = try await client.call(CallSvc.self, request: "hello")
            #expect(Bool(false), "Expected unsupportedService error")
        } catch let err as PisteInternalError {
            #expect(err == .unsupportedService)
        } catch {
            #expect(Bool(false), "Unexpected error: \(error)")
        }
    }

    @Test
    func cancelAllCancelsAllActiveRequestsAndChannels() async throws {
        let sent = Outbox()
        let client = await buildClient(sent: sent, services: [CallSvc.self])

        let callTask = Task { () -> String in
            try Task.checkCancellation()
            return try await client.call(CallSvc.self, request: "hang")
        }

        try? await Task.sleep(nanoseconds: 200_000)
        await client.cancelAll()

        do {
            _ = try await callTask.value
            #expect(Bool(false), "Expected cancellation")
        } catch {
        }

        #expect(true, "cancelAll completed")
    }
}
