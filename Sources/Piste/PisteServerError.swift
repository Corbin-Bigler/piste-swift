//
//  PisteServerError.swift
//  piste-swift
//
//  Created by Corbin Bigler on 4/27/25.
//

enum PisteServerError: PisteError {
    case unsupportedService(service: String)
    case internalServerError
    case badPayload
    case badFrame
    
    var id: String {
        switch self {
        case .unsupportedService(_): "unsupportedService"
        case .internalServerError: "internalServerError"
        case .badPayload: "badPayload"
        case .badFrame: "badFrame"
        }
    }
    var message: String {
        switch self {
        case .badFrame: "Invalid frame format"
        case .badPayload: "Invalid payload format"
        case .internalServerError: "An unknown internal server error occurred"
        case .unsupportedService(let service): "Unsupported service \"\(service)\""
        }
    }
}
