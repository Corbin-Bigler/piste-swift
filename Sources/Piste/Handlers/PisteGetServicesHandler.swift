//
//  PisteGetServicesHandler.swift
//  piste-swift
//
//  Created by Corbin Bigler on 4/27/25.
//

import SwiftProtobuf

struct PisteGetServicesHandler: CallPisteHandler {
    typealias Service = PisteGetServicesService
    
    let title: String = "Piste Services Service"
    let description: String = "Returns the services supported by server"
    
    private let server: PisteChannelServer
    init(server: PisteChannelServer) {
        self.server = server
    }

    func handle(request: Google_Protobuf_Empty) async throws -> PisteGetServicesResponse {
        var response = PisteGetServicesResponse()
        response.services = Array(server.handlers.keys)
        return response
    }
}
