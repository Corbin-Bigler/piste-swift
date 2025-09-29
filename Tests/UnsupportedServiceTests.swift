import Testing
import Foundation
@testable import Piste

final class UnsupportedServiceTests {
    let handlers: [any PisteHandler] = [
        TestCallHandler(),
        TestDownloadHandler(),
        TestUploadHandler(),
        TestStreamHandler()
    ]

    private var _client: PisteClient?
    private var client: PisteClient {
        get async {
            if let _client { return _client }
            
            let server = PisteServer(
                codec: JsonPisteCodec(),
                handlers: handlers
            )
            let client = PisteClient(codec: JsonPisteCodec())
            
            await server.onOutbound { exchange, data in
                let frame = PisteFrame(data: data)!
                if case .payload(let data) = frame {
                    print("Server Outbound:", String(data: data, encoding: .utf8)!)
                } else {
                    print("Server Outbound:", frame)
                }
                
                await client.handle(exchange: exchange, frame: data)
            }
            await client.onOutbound { exchange, data in
                let frame = PisteFrame(data: data)!
                if case .payload(let data) = frame {
                    print("Client Outbound:", String(data: data, encoding: .utf8)!)
                } else {
                    print("Client Outbound:", frame)
                }
                
                await server.handle(exchange: exchange, frame: data)
            }
            
            _client = client
            return _client!
        }
    }

    @Test func testCallUnsupportedService() async throws {
        struct UnknownCallService: CallPisteService {
            typealias Serverbound = String
            typealias Clientbound = String
            static let id: PisteId = 0xDEADBEEF
            static let title = "Unknown Call Service"
            static let description = "A call service not registered on server."
        }

        await #expect(throws: PisteError.unsupportedService)  {
            try await client.call(UnknownCallService.self, request: "ping")
        }
    }

    @Test func testDownloadUnsupportedService() async throws {
        struct UnknownDownloadService: DownloadPisteService {
            typealias Serverbound = String
            typealias Clientbound = String
            static let id: PisteId = 0xDEADBEEE
            static let title = "Unknown Download Service"
            static let description = "A download service not registered on server."
        }

        await #expect(throws: PisteError.unsupportedService)  {
            try await client.download(UnknownDownloadService.self, request: "ping")
        }
    }

    @Test func testUploadUnsupportedService() async throws {
        struct UnknownUploadService: UploadPisteService {
            typealias Serverbound = String
            typealias Clientbound = String
            static let id: PisteId = 0xDEADBEED
            static let title = "Unknown Upload Service"
            static let description = "An upload service not registered on server."
        }

        await #expect(throws: PisteError.unsupportedService)  {
            try await client.upload(UnknownUploadService.self)
        }
    }

    @Test func testStreamUnsupportedService() async throws {
        struct UnknownStreamService: StreamPisteService {
            typealias Serverbound = String
            typealias Clientbound = String
            static let id: PisteId = 0xDEADBED0
            static let title = "Unknown Stream Service"
            static let description = "A stream service not registered on server."
        }

        await #expect(throws: PisteError.unsupportedService)  {
            try await client.stream(UnknownStreamService.self)
        }
    }

    @Test func testUploadSendAfterCompletionThrowsChannelClosed() async throws {
        let channel = try await client.upload(TestUploadService.self)
        for i in 0..<TestUploadHandler.requests {
            try await channel.send("\(i)")
        }
        let _ = await channel.completed
        
        await #expect(throws: PisteError.channelClosed)  {
            try await channel.send("extra")
        }
    }

    @Test func testStreamSendAfterCloseThrowsChannelClosed() async throws {
        let channel = try await client.stream(TestStreamService.self)
        await channel.close()
        
        await #expect(throws: PisteError.channelClosed)  {
            try await channel.send("hello")
        }
    }

    @Test func testDownloadCloseEarlyStopsInbound() async throws {
        let channel = try await client.download(TestDownloadService.self, request: "early")
        await channel.close()
        _ = try await channel.closed
        var count = 0
        for await _ in channel.inbound {
            count += 1
        }
        #expect(count == 0)
    }
}
