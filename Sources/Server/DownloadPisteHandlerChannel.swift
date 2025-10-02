//
//  DownloadPisteHandlerChannel.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

public struct DownloadPisteHandlerChannel<Service: PisteService>: Sendable {
    private let channel: PisteChannel<Service.Serverbound, Service.Clientbound>
    
    public var closed: Void { get async throws { try await channel.closed } }

    init(channel: PisteChannel<Service.Serverbound, Service.Clientbound>) {
        self.channel = channel
    }
    
    public func send(_ value: Service.Clientbound) async throws { try await channel.send(value) }
    public func close() async { await channel.close() }
}
