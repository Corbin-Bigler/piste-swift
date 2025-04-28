//
//  PisteServerError.swift
//  piste-swift
//
//  Created by Corbin Bigler on 4/27/25.
//

public enum PisteServerError: PisteError {
    case clientError(id: String, message: String?)
    case unsupportedService(service: String)
    case internalServerError
    case badPayload
    case badFrame
    
    public var id: String {
        switch self {
        case .unsupportedService(_): "unsupportedService"
        case .internalServerError: "internalServerError"
        case .badPayload: "badPayload"
        case .badFrame: "badFrame"
        case .clientError(id: let id, message: _): id
        }
    }
    public var message: String? {
        switch self {
        case .badFrame: "Invalid frame format"
        case .badPayload: "Invalid payload format"
        case .internalServerError: "An unknown internal server error occurred"
        case .unsupportedService(let service): "Unsupported service \"\(service)\""
        case .clientError(id: _, message: let message): message
        }
    }
}
