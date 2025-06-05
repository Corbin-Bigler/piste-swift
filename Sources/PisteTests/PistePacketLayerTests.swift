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
    func testMakeContentPacketsChunksCorrectly() async throws {
        let content = MockService.Response(message: String(repeating: "x", count: 100))
        let packets = try PisteFrame(serviceId: MockService.id, requestId: 42, payload: .content(content)).packets(maxSize: 64)

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

        do {
            _ = try PisteFrame(serviceId: HugeHeaderService.id, requestId: 1, payload: .content(HugeHeaderService.Response(data: "hi"))).packets(maxSize: 64)
            #expect(Bool(false), "Should have thrown due to small max packet size")
        } catch let error as PisteFrameError {
            #expect(error == .maximumPacketSizeTooSmall)
        } catch {
            #expect(Bool(false), "Unexpected error: \(String(describing: error))")
        }
    }

    @Test
    func testReassemblesChunksAndEmitsFrame() async throws {
        let layer = PistePacketAggregator()
        let content = MockService.Response(message: "TestChunkingData")
        let requestId: UInt64 = 999

        let packets = try PisteFrame(serviceId: MockService.id, requestId: requestId, payload: .content(content)).packets(maxSize: 64)
        var iterator = await layer.onFrame.makeAsyncIterator()

        for packet in packets {
            await layer.handle(data: packet)
        }

        if let frame = await iterator.next() {
            let decoded = try CodableCBORDecoder().decode(MockService.Response.self, from: frame.payload)
            #expect(decoded == content)
        } else {
            #expect(Bool(false), "Expected decoded content")
        }
    }

    @Test
    func testMakeStreamPacketContainsFinalPacketID() async throws {
        let action = PisteStreamAction.open
        let requestId: UInt64 = 42
        let packets = try PisteFrame(serviceId: MockService.id, requestId: requestId, payload: .stream(.init(action: action))).packets(maxSize: 128)

        let last = packets.last!
        let packetID = last[requestId.uleb128.count + UInt64(MockService.id.utf8.count).uleb128.count + MockService.id.utf8.count]
        #expect(packetID == PistePayloadType.stream.finalPacketId)
    }

    @Test
    func testMakeErrorPacketEmitsProperly() async throws {
        let packets = try PisteFrame(serviceId: MockService.id, requestId: 55, payload: .error(.init(code: "oops", message: "Something went wrong"))).packets(maxSize: 128)

        #expect(packets.count > 0)
    }
}
