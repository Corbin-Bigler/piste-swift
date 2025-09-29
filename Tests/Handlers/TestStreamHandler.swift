//
//  TestStreamHandler.swift
//  Piste
//
//  Created by Corbin Bigler on 9/18/25.
//

import Piste

struct TestStreamHandler: StreamPisteHandler {
    static let service = TestStreamService.self
    static let prefix = "Echo: "

    func handle(channel: StreamPisteHandlerChannel<Service>) async throws {
        Task {
            for await request in channel.inbound {
                try? await channel.send(Self.prefix + request)
            }
        }
    }
}
