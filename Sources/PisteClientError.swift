//
//  PisteClientError.swift
//  test-client
//
//  Created by Corbin Bigler on 4/24/25.
//

enum PisteClientError: Error {
    case disconnected
    case timeout
    case badResponse
    case versionsHandshake
    case unsupportedService
    case unsupportedVersion
    case error(id: String, message: String?)
    
    var id: String {
        switch self {
        case .disconnected: "disconnected"
        case .timeout: "timeout"
        case .badResponse: "badResponse"
        case .versionsHandshake: "versionsHandshake"
        case .unsupportedService: "unsupportedService"
        case .unsupportedVersion: "unsupportedVersion"
        case .error(let id, _): id
        }
    }
}
