//
//  PisteServiceInformationService.swift
//  Piste
//
//  Created by Corbin Bigler on 9/18/25.
//

struct PisteServiceInformationService: CallPisteService {
    typealias Serverbound = Void
    typealias Clientbound = [ServiceInformation]
    
    static let id: PisteId = 0xFFFFFFFF
    
    static let title: String = "Piste Service Information"
    static let description: String = "Responds with information about the currently supported services"
    
    struct ServiceInformation: Codable {
        let id: PisteId
        let title: String
        let description: String
    }
}
