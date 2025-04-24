//
//  PisteClientError.swift
//  test-client
//
//  Created by Corbin Bigler on 4/24/25.
//

enum PisteServerError: PisteError {
    case unsupportedService(service: String)
    case unsupportedVersion(service: String, version: Int)
    case internalServerError
    case badPayload
    
    var id: String {
        switch self {
        case .unsupportedService(_): "unsupportedService"
        case .unsupportedVersion(_, _): "unsupportedVersion"
        case .internalServerError: "internalServerError"
        case .badPayload: "badPayload"
        }
    }
    var message: String {
        switch self {
        case .badPayload: "Invalid payload format"
        case .internalServerError: "An unknown internal server error occurred"
        case .unsupportedService(let service): "Unsupported service \"\(service)\""
        case .unsupportedVersion(service: let service, version: let version): "Unsupported version \"\(version)\" for service \"\(service)\""
        }
    }
}
