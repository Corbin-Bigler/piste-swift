//
//  UploadPisteHandlerChannel.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

public struct UploadPisteHandlerChannel<Service: PisteService>: Sendable {
    private let channel: PisteChannel<Service.Serverbound, Service.Clientbound>

    public var inbound: AsyncStream<Service.Serverbound> { channel.inbound }
    public var closed: Void { get async throws { try await channel.closed } }

    init(channel: PisteChannel<Service.Serverbound, Service.Clientbound>) {
        self.channel = channel
    }

    public func close() async { await channel.close() }
    public func complete(response: Service.Clientbound) async throws { try await channel.send(response) }
}
