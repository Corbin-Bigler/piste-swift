//
//  PisteServiceInformationHandler.swift
//  Piste
//
//  Created by Corbin Bigler on 9/18/25.
//

struct PisteServiceInformationHandler: CallPisteHandler {
    static let service = PisteServiceInformationService.self
        
    let otherHandlers: [any PisteHandler]
    
    func handle(request: Void) async throws -> [PisteServiceInformationService.ServiceInformation] {
        return otherHandlers.map { $0.serviceInformation } + [self.serviceInformation]
    }
}

private extension PisteHandler {
    var serviceInformation: PisteServiceInformationService.ServiceInformation {
        .init(id: Service.id, title: Service.title, description: Service.description)
    }
}
