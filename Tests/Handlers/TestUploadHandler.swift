//
//  TestUploadHandler.swift
//  Piste
//
//  Created by Corbin Bigler on 9/18/25.
//

import Piste

struct TestUploadHandler: UploadPisteHandler {
    static let service = TestUploadService.self
    static let requests = 5
    static let finishedResponse = "Finished Upload"

    func handle(channel: UploadPisteHandlerChannel<Service>) async throws {
        Task {
            var count = 0
            for await _ in channel.inbound {
                count += 1
                if count >= Self.requests {
                    try await channel.complete(response: Self.finishedResponse)
                    return
                }
            }
        }
    }
}
