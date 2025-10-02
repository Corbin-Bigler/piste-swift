//
//  PisteServerTests.swift
//  Piste
//
//  Created by Corbin Bigler on 10/2/25.
//

import Testing
import Foundation
@testable import Piste

final class PisteServerTests {
    private struct CallSvc: CallPisteService {
        typealias Serverbound = String
        typealias Clientbound = String
        static let id: PisteId = 0
    }

    private struct DownloadSvc: DownloadPisteService {
        typealias Serverbound = String
        typealias Clientbound = String
        static let id: PisteId = 1
    }

    private struct UploadSvc: UploadPisteService {
        typealias Serverbound = String
        typealias Clientbound = String
        static let id: PisteId = 2
    }

    private struct StreamSvc: StreamPisteService {
        typealias Serverbound = String
        typealias Clientbound = String
        static let id: PisteId = 3
    }

    private struct FakeCallHandler: CallPisteHandler {
        typealias Service = CallSvc
        let service = Service.self
        let response: String
        func handle(request: String) async throws -> String { response }
    }

    private struct FakeDownloadHandler: DownloadPisteHandler {
        typealias Service = DownloadSvc
        let service = Service.self
        func handle(request: String, channel: DownloadPisteHandlerChannel<Service>) async throws {}
    }

    private actor FakeUploadHandler: UploadPisteHandler {
        typealias Service = UploadSvc
        let service = Service.self
        var capturedChannel: UploadPisteHandlerChannel<Service>?
        func handle(channel: UploadPisteHandlerChannel<Service>) async throws {
            capturedChannel = channel
        }
    }

    private actor FakeStreamHandler: StreamPisteHandler {
        typealias Service = StreamSvc
        let service = Service.self
        var capturedChannel: StreamPisteHandlerChannel<Service>?
        func handle(channel: StreamPisteHandlerChannel<Service>) async throws {
            capturedChannel = channel
        }
    }

    // MARK: - Helpers

    private func makeServer(with handlers: [any PisteHandler],
                            onOutbound: (@Sendable (PisteServer.Outbound) async -> Void)? = nil) async -> PisteServer {
        let server = PisteServer(codec: JsonPisteCodec(), handlers: handlers)
        if let onOutbound {
            await server.onOutbound { outbound in await onOutbound(outbound) }
        }
        return server
    }

    class UncheckedArray<T>: @unchecked Sendable {
        private(set) var value: [T] = []
        var count: Int { value.count }
        var isEmpty: Bool { value.isEmpty }
        subscript(_ index: Int) -> T {
            get { value[index] }
            set { value[index] = newValue }
        }

        func append(_ value: T) {
            self.value.append(value)
        }
    }

    @Test func duplicateHandlerIdsShouldFail_orBeIgnored() async throws {
        typealias Svc = CallSvc

        let handler1 = FakeCallHandler(response: "response1")
        let handler2 = FakeDownloadHandler()

        let sent = UncheckedArray<PisteServer.Outbound>()
        let server = await makeServer(with: [handler1, handler2]) { @Sendable outbound in
            sent.append(outbound)
        }

        let payload = try JsonPisteCodec().encode("ping")
        let frame = PisteFrame.requestCall(id: Svc.id, payload: payload)

        await server.handle(exchange: 1, frame: frame.data)

        #expect(sent.count == 1, "Server should respond to request")
        let resp = PisteFrame(data: sent[0].frameData)
        guard case let .payload(respPayload) = resp else {
            #expect(Bool(false), "Expected Payload frame")
            return
        }
        let decoded: String = try JsonPisteCodec().decode(respPayload)
        #expect(decoded == "response1")
    }

    @Test func invalidFrameDataShouldNotCrashAndSendNothing() async throws {
        typealias Svc = CallSvc

        let handler = FakeCallHandler(response: "ok")
        let sent = UncheckedArray<PisteServer.Outbound>()
        let server = await makeServer(with: [handler]) { @Sendable outbound in
            sent.append(outbound)
        }

        let invalid = Data([0x00, 0x01, 0x02])
        await server.handle(exchange: 42, frame: invalid)

        #expect(sent.isEmpty, "Server should not send anything on invalid input")
    }

    @Test func requestCallDispatchesToCorrectHandler() async throws {
        typealias Svc = CallSvc

        let handler = FakeCallHandler(response: "handler response")
        let sent = UncheckedArray<PisteServer.Outbound>()
        let server = await makeServer(with: [handler]) { outbound in
            sent.append(outbound)
        }

        let request = "ping"
        let payload = try JsonPisteCodec().encode(request)
        let frame = PisteFrame.requestCall(id: Svc.id, payload: payload)

        await server.handle(exchange: 1, frame: frame.data)

        #expect(sent.count == 1, "Should have sent one outbound frame")
        guard case let .payload(outPayload) = PisteFrame(data: sent[0].frameData) else {
            #expect(Bool(false), "Response should be a Payload frame")
            return
        }
        let decoded: String = try JsonPisteCodec().decode(outPayload)
        #expect(decoded == "handler response")
    }

    @Test func requestDownloadOpensChannelAndSendsOpen() async throws {
        let handler = FakeDownloadHandler()
        let sent = UncheckedArray<PisteServer.Outbound>()
        let server = await makeServer(with: [handler]) { outbound in
            sent.append(outbound)
        }

        let payload = try JsonPisteCodec().encode("download please")
        let frame = PisteFrame.requestDownload(id: FakeDownloadHandler.Service.id, payload: payload)

        await server.handle(exchange: 42, frame: frame.data)

        #expect(!sent.isEmpty, "Expected an outbound frame")
        let resp = PisteFrame(data: sent[0].frameData)
        #expect(resp == .open, "Expected an Open frame after RequestDownload")
    }

    @Test func requestDownloadWithWrongHandlerTypeSendsUnsupportedFrameType() async throws {
        let callHandler = FakeCallHandler(response: "call response")
        let sent = UncheckedArray<PisteServer.Outbound>()
        let server = await makeServer(with: [callHandler]) { outbound in
            sent.append(outbound)
        }

        let payload = try JsonPisteCodec().encode("bad request")
        let frame = PisteFrame.requestDownload(id: callHandler.id, payload: payload)

        await server.handle(exchange: 42, frame: frame.data)

        #expect(!sent.isEmpty, "Should respond with an Error frame")
        guard case let .error(err) = PisteFrame(data: sent[0].frameData) else {
            #expect(Bool(false), "Expected Error frame")
            return
        }
        #expect(err == .unsupportedFrameType)
    }

    @Test func openUploadOpensChannelAndSendsOpen() async throws {
        let handler = FakeUploadHandler()
        let sent = UncheckedArray<PisteServer.Outbound>()
        let server = await makeServer(with: [handler]) { outbound in
            sent.append(outbound)
        }

        await server.handle(exchange: 42, frame: PisteFrame.openUpload(id: handler.id).data)

        #expect(sent.count == 1, "Expected an outbound frame")
        #expect(PisteFrame(data: sent[0].frameData) == .open)
    }

    @Test func openStreamOpensChannelAndSendsOpen() async throws {
        let handler = FakeStreamHandler()
        let sent = UncheckedArray<PisteServer.Outbound>()
        let server = await makeServer(with: [handler]) { outbound in
            sent.append(outbound)
        }

        await server.handle(exchange: 42, frame: PisteFrame.openStream(id: handler.id).data)

        #expect(sent.count == 1, "Expected an outbound frame")
        #expect(PisteFrame(data: sent[0].frameData) == .open)
    }

    @Test func payloadIsRoutedToHandlerChannel() async throws {
        let handler = FakeUploadHandler()
        let sent = UncheckedArray<PisteServer.Outbound>()
        let server = await makeServer(with: [handler]) { outbound in
            sent.append(outbound)
        }

        await server.handle(exchange: 42, frame: PisteFrame.openUpload(id: handler.id).data)
        let channel = await handler.capturedChannel
        #expect(channel != nil, "Handler should have received a channel")
        guard let channel else { return }

        let payload = try JsonPisteCodec().encode("hello inbound")
        let payloadFrame = PisteFrame.payload(payload)

        let pump = Task { await server.handle(exchange: 42, frame: payloadFrame.data) }
        _ = await pump.result

        var first: String?
        for try await msg in channel.inbound {
            first = msg
            break
        }
        #expect(first == "hello inbound")
    }

    @Test func closeFrameClosesHandlerChannel() async throws {
        let handler = FakeUploadHandler()
        let server = await makeServer(with: [handler])

        await server.handle(exchange: 42, frame: PisteFrame.openUpload(id: handler.id).data)
        let channel = await handler.capturedChannel
        #expect(channel != nil, "Handler should have received a channel")
        guard let channel else { return }

        let t = Task { await server.handle(exchange: 42, frame: PisteFrame.close.data) }
        _ = await t.result

        var collected: [String] = []
        for try await msg in channel.inbound {
            collected.append(msg)
        }
        #expect(collected.isEmpty, "No inbound messages expected after close")
    }

    @Test func supportedServicesRequestReturnsAllRegisteredServices() async throws {
        let h1 = FakeCallHandler(response: "h1")
        let h2 = FakeDownloadHandler()

        let sent = UncheckedArray<PisteServer.Outbound>()
        let server = await makeServer(with: [h1, h2]) { outbound in
            sent.append(outbound)
        }

        await server.handle(exchange: 42, frame: PisteFrame.supportedServicesRequest.data)

        #expect(sent.count == 1, "Expected a single outbound frame")

        guard case let .supportedServicesResponse(services) = PisteFrame(data: sent[0].frameData) else {
            #expect(Bool(false), "Expected SupportedServicesResponse")
            return
        }
        let ids = services.map(\.id)
        #expect(ids.contains(h1.id))
        #expect(ids.contains(h2.id))
    }

    @Test func unsupportedFrameReturnsUnsupportedFrameTypeError() async throws {
        let handler = FakeCallHandler(response: "resp")
        let sent = UncheckedArray<PisteServer.Outbound>()
        let server = await makeServer(with: [handler]) { outbound in
            sent.append(outbound)
        }

        await server.handle(exchange: 42, frame: PisteFrame.error(.internalServerError).data)

        #expect(sent.count == 1, "Expected error response")
        guard sent.count == 1 else { return }
        guard case let .error(err) = PisteFrame(data: sent[0].frameData) else {
            #expect(Bool(false), "Expected Error frame")
            return
        }
        #expect(err == .unsupportedFrameType)
    }

    @Test func multipleSendsOnSameChannelAreSerialized() async throws {
        let handler = FakeStreamHandler()
        let sent = UncheckedArray<String>()
        let server = await makeServer(with: [handler]) { outbound in
            if case let .payload(bytes) = PisteFrame(data: outbound.frameData) {
                if let str: String = try? JsonPisteCodec().decode(bytes) {
                    print("RECEIVED: \(str)")
                    sent.append(str)
                }
            }
        }

        await server.handle(exchange: 42, frame: PisteFrame.openStream(id: handler.id).data)
        let channel = await handler.capturedChannel
        #expect(channel != nil, "Expected stream channel")
        guard let channel else { return }

        for n in 0..<10 {
            try await channel.send("msg-\(n)")
        }

        #expect(sent.value == (0..<10).map { "msg-\($0)" }, "Messages should be serialized in order")
    }
}
