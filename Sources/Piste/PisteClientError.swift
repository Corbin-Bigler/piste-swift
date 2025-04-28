//
//  PisteClientError.swift
//  piste-swift
//
//  Created by Corbin Bigler on 4/27/25.
//


public enum PisteClientError: PisteError {
    case internalClientError
    case cancelled
    case timeout
    case badResponse
    case servicesHandshake
    case unsupportedService
    case serverError(id: String, message: String?)
    
    public var id: String {
        switch self {
        case .internalClientError: "internalClientError"
        case .cancelled: "cancelled"
        case .timeout: "timeout"
        case .badResponse: "badResponse"
        case .servicesHandshake: "servicesHandshake"
        case .unsupportedService: "unsupportedService"
        case .serverError(let id, _): id
        }
    }
}
