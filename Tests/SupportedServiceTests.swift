import Testing
import Foundation
@testable import Piste

final class SupportedServiceTests {
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
    
    @Test func testServicesService() async throws {
        let response = try await client.call(PisteServiceInformationService.self)
        
        #expect(Set(response.map(\.id)) == Set((handlers + [PisteServiceInformationHandler(otherHandlers: [])]).map(\.id)))
    }
    @Test func testCall() async throws {
        let request = UUID().uuidString
        let response = try await client.call(TestCallService.self, request: request)
        #expect(response == TestCallHandler.mutated(request: request))
    }
    @Test func testDownload() async throws {
        let request = UUID().uuidString
        let channel = try await client.download(TestDownloadService.self, request: request)
        var count = 0
        for await response in channel.inbound {
            count += 1
            
            if response != TestDownloadHandler.mutated(request: request, count: count) {
                #expect(Bool(false))
            }
            if count >= 20 {
                break
            }
        }
        
        await channel.close()
        #expect(true)
    }
    @Test func testUpload() async throws {
        let channel = try await client.upload(TestUploadService.self)
        
        Task {
            for index in 0..<TestUploadHandler.requests {
                try await channel.send("\(index)")
            }
        }
        
        let response = await channel.completed
        
        #expect(response == TestUploadHandler.finishedResponse)
    }
    @Test func testStream() async throws {
        let channel = try await client.stream(TestStreamService.self)
            
        let requests = [
            UUID(),
            UUID(),
            UUID()
        ].map(\.uuidString)
        var responses: [String] = []
        
        Task {
            for request in requests {
                try await channel.send(request)
            }
        }
        for await response in channel.inbound {
            responses.append(String(response.suffix(response.count - TestStreamHandler.prefix.count)))
            if responses.count == requests.count {
                break
            }
        }
        
        await channel.close()
        
        #expect(responses == requests)
    }
}
