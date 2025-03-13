//
//  PisteError.swift
//  piste
//
//  Created by Corbin Bigler on 3/12/25.
//

public enum PisteError: Error {
    case clientOutdated
    case serverOutdated
    case serviceNotAvailable
    case badFrame
    case failure(String)
    
    var value: String {
        switch self {
        case .clientOutdated: return "piste-error-client-outdated"
        case .serverOutdated: return "piste-error-server-outdated"
        case .serviceNotAvailable: return "piste-service-not-available"
        case .badFrame: return "piste-error-bad-frame"
        case .failure(let message): return message
        }
    }
    
    init(value: String) {
        switch value {
        case "piste-error-client-outdated": self = .clientOutdated
        case "piste-error-server-outdated": self = .serverOutdated
        case "piste-service-not-available": self = .serviceNotAvailable
        case "piste-error-bad-frame": self = .badFrame
        default: self = .failure(value)
        }
    }
}
