//
//  PisteVersionsService.swift
//  piste
//
//  Created by Corbin Bigler on 4/23/25.
//

public final class PisteVersionsService: TransientPisteService {
    public static let id = "piste-versions"
    public static let version: Int = 0
    
    public typealias Clientbound = [String: [Int]]
}
struct PisteVersionsHandler: TransientPisteHandler {
    typealias Service = PisteVersionsService
            
    static let title: String = "Piste Versions Service"
    static let description: String = "Returns the versions of services supported by server"
    
    private let connection: PisteConnection
    init(connection: PisteConnection) {
        self.connection = connection
    }
    
    func handle(inbound: Empty) async throws -> Service.Clientbound {
        return connection.handlers.mapValues { Array($0.keys) }
    }
}
