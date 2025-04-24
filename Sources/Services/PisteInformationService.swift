//
//  PisteInformationService.swift
//  piste
//
//  Created by Corbin Bigler on 4/23/25.
//


public final class PisteInformationService: PisteService {
    public static let id = "piste-information"
    public static let version: Int = 0
    public static let persistent = false
    
    public typealias Clientbound = [String: [Int: ServiceInformation]]
    public struct ServiceInformation: Codable {
        public let id: String
        public let version: Int
        public let persistent: Bool
    }
}
struct PisteInformationHandler: PisteHandler {
    typealias Service = PisteInformationService
            
    static let title: String = "Piste Information Service"
    static let description: String = "Returns the information of services supported by server"
    
    func handle(context: PisteContext<Self>, serverbound: Empty) throws {
        context.respond(with: context.server.handlers.mapValues { $0.mapValues { .init(id: $0.id, version: $0.version, persistent: $0.persistent)} })
    }
}
