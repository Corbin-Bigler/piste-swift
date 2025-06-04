//
//  PisteServicesHandler.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/7/25.
//

enum PisteServicesService: RPCCallService {
    typealias Request = PisteEmpty
    typealias Response = [String: ServiceInformation]
    
    static let id: String = "services"
    
    struct ServiceInformation: Codable, Sendable {
        let title: String
        let description: String
    }
}
final class PisteServicesHandler: PisteCallHandler {
    typealias Service = PisteServicesService
    
    let title: String = "Piste Services Service"
    let description: String = "Provides information about supported services"
    let deprecated: Bool = false
    
    private let server: PisteServer
    init(server: PisteServer) {
        self.server = server
    }
    
    func handle(request: PisteEmpty) async throws -> [String : PisteServicesService.ServiceInformation] {
        return await server.handlers.mapValues { .init(title: $0.title, description: $0.description) }
    }
}
