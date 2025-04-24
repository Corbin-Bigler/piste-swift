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
struct PisteVersionsHandler: PisteHandler {
    typealias Service = PisteVersionsService
            
    static let title: String = "Piste Versions Service"
    static let description: String = "Returns the versions of services supported by server"
    
    let context: PisteContext<Service>
    
    func handle(serverbound: Empty) throws {
        context.respond(with: context.server.handlers.mapValues { Array($0.keys) })
    }
}
