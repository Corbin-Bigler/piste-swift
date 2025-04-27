//
//  PisteInformationService.swift
//  piste
//
//  Created by Corbin Bigler on 4/23/25.
//

public final class PisteInformationService: TransientPisteService {
    public static let id = "piste-information"
    public static let version: Int = 0
    
    public typealias Clientbound = [String: [Int: ServiceInformation]]
    public struct ServiceInformation: Codable, Sendable {
        public let id: String
        public let version: Int
        public let persistent: Bool
    }
}
struct PisteInformationHandler: TransientPisteHandler {
    typealias Service = PisteInformationService
    
    static let title: String = "Piste Information Service"
    static let description: String = "Returns the information of services supported by server"
    
    private let server: PisteServer
    init(server: PisteServer) {
        self.server = server
    }
    
    func handle(inbound: Empty) async throws -> Service.Clientbound{
        return server.handlers.mapValues { $0.mapValues { .init(id: $0.id, version: $0.version, persistent: $0.persistent)} }
    }
}
