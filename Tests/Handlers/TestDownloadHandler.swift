//
//  TestDownloadHandler.swift
//  Piste
//
//  Created by Corbin Bigler on 9/18/25.
//

import Piste

struct TestDownloadHandler: DownloadPisteHandler {
    static let service = TestDownloadService.self
    static func mutated(request: String, count: Int) -> String {
        "Echo: \(request)"
    }
    func handle(request: String, channel: DownloadPisteHandlerChannel<TestDownloadService>) async throws {
        Task {
            await channel.opened
            
            var count = 0
            while true {
                count += 1
                try await channel.send(Self.mutated(request: request, count: count))
            }
            
            await channel.close()
        }
    }
}
