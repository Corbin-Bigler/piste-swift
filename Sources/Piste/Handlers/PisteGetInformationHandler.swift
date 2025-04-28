//
//  PisteGetInformationHandler.swift
//  piste-swift
//
//  Created by Corbin Bigler on 4/27/25.
//

import SwiftProtobuf

struct PisteGetInformationHandler: CallPisteHandler {
    typealias Service = PisteGetInformationService
    
    let title: String = "Piste Information Service"
    let description: String = "Returns the information of services supported by server"
    
    private let server: PisteChannelServer
    init(server: PisteChannelServer) {
        self.server = server
    }
    
    func handle(request: Google_Protobuf_Empty) async throws -> PisteGetInformationResponse {
        var information: [String : PisteServiceInformation] = [:]
        for handler in server.handlers.values {
            var serviceInfo = PisteServiceInformation()
            serviceInfo.title = handler.title
            serviceInfo.description_p = handler.description
            information[handler.path] = serviceInfo
        }

        var response = PisteGetInformationResponse()
        response.information = information
        return response
    }
}
