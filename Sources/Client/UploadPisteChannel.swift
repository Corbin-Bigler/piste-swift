//
//  UploadPisteChannel.swift
//  Piste
//
//  Created by Corbin Bigler on 9/25/25.
//

public struct UploadPisteChannel<Service: PisteService>: Sendable {
    private let channel: PisteChannel<Service.Clientbound, Service.Serverbound>
    
    public var opened: Void { get async { await channel.opened } }
    public var closed: Void { get async throws { try await channel.closed } }
    public var completed: Service.Clientbound { get async { await channel.completed } }

    init(channel: PisteChannel<Service.Clientbound, Service.Serverbound>) {
        self.channel = channel
    }
    
    public func send(_ value: Service.Serverbound) async throws { try await channel.send(value) }
    func close() async { await channel.close() }
}
