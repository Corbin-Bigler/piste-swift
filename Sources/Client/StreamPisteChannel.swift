//
//  StreamPisteChannel.swift
//  Piste
//
//  Created by Corbin Bigler on 9/25/25.
//

public struct StreamPisteChannel<Service: PisteService>: Sendable {
    private let channel: PisteChannel<Service.Clientbound, Service.Serverbound>

    public var inbound: AsyncStream<Service.Clientbound> { channel.inbound }
    public var closed: Void { get async throws { try await channel.closed } }

    init(channel: PisteChannel<Service.Clientbound, Service.Serverbound>) {
        self.channel = channel
    }
    
    func send(_ value: Service.Serverbound) async throws { try await channel.send(value) }
    func close() async { await channel.close() }
}
