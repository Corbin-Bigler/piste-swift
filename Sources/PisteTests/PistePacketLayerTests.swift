//
//  PisteTests.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/4/25.
//

@testable import Piste
import Testing
import Foundation
import Combine
import SwiftCBOR

struct PistePacketLayerTests {
    struct MockService: RPCService {
        static let id: String = "mock.service"
        typealias Request = PisteEmpty
        struct Response: Codable, Equatable, Sendable {
            let message: String
        }
    }

    @Test
    func testSetMaximumPacketSizeDoesNotCrash() async {
        let layer = PistePacketLayer(maximumPacketSize: 128)
        await layer.setMaximumPacketSize(512)
        // no assertion needed: just verifying no crash
        #expect(true)
    }

    @Test
    func testMakePayloadPacketsChunksCorrectly() async throws {
        let layer = PistePacketLayer(maximumPacketSize: 64)

        let payload = MockService.Response(message: String(repeating: "x", count: 100))
        let packets = try await layer.makePayloadPackets(payload: payload, requestId: 42, serviceId: MockService.id.self)

        #expect(packets.count > 1)
    }

    @Test
    func testThrowsWhenHeaderTooBig() async {
        struct HugeHeaderService: RPCService {
            static let id: String = String(repeating: "x", count: 200)
            typealias Request = PisteEmpty
            struct Response: Codable, Sendable {
                let data: String
            }
        }

        let layer = PistePacketLayer(maximumPacketSize: 16)

        do {
            _ = try await layer.makePayloadPackets(
                payload: HugeHeaderService.Response(data: "hi"),
                requestId: 1,
                serviceId: HugeHeaderService.id
            )
            #expect(Bool(false), "Should have thrown due to small max packet size")
        } catch let error as PisteClientError {
            #expect(error == .maximumPacketSizeTooSmall)
        } catch {
            #expect(Bool(false), "Unexpected error: \(String(describing: error))")
        }
    }

    @Test
    func testReassemblesChunksAndEmitsFrame() async throws {
        let layer = PistePacketLayer(maximumPacketSize: 64)
        let payload = MockService.Response(message: "TestChunkingData")
        let requestId: UInt64 = 999

        let packets = try await layer.makePayloadPackets(payload: payload, requestId: requestId, serviceId: MockService.id)
        var iterator = await layer.onFrame.makeAsyncIterator()

        for packet in packets {
            await layer.handle(data: packet)
        }

        if let data = await iterator.next() {
            let decoded = try CodableCBORDecoder().decode(MockService.Response.self, from: data.frame)
            #expect(decoded == payload)
        } else {
            #expect(Bool(false), "Expected decoded payload")
        }
    }

    @Test
    func testMakeStreamPacketContainsFinalPacketID() async throws {
        let layer = PistePacketLayer(maximumPacketSize: 128)
        let action = PisteStreamAction.open
        let packets = try await layer.makeStreamPackets(action: action, requestId: 42, serviceId: MockService.id)

        let last = packets.last!
        let packetID = last[UInt64(42).uleb128.count + UInt64(MockService.id.utf8.count).uleb128.count + MockService.id.utf8.count]
        #expect(packetID == PisteFrameType.stream.finalPacketId)
    }

    @Test
    func testMakeErrorPacketEmitsProperly() async throws {
        let layer = PistePacketLayer(maximumPacketSize: 128)
        let packets = try await layer.makeErrorPackets(code: "oops", message: "Something went wrong", requestId: 55, serviceId: MockService.id)

        #expect(packets.count > 0)
    }
}
