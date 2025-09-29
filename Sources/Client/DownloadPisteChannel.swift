//
//  DownloadPisteChannel.swift
//  Piste
//
//  Created by Corbin Bigler on 9/25/25.
//

public struct DownloadPisteChannel<Service: PisteService>: Sendable {
    private let channel: PisteChannel<Service.Clientbound, Service.Serverbound>

    public var inbound: AsyncStream<Service.Clientbound> { channel.inbound }
    public var closed: Void { get async throws { try await channel.closed } }

    init(channel: PisteChannel<Service.Clientbound, Service.Serverbound>) {
        self.channel = channel
    }
    
    func close() async { await channel.close() }
}
