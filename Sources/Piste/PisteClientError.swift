//
//  PisteClientError.swift
//  piste-swift
//
//  Created by Corbin Bigler on 4/27/25.
//


enum PisteClientError: Error {
    case cancelled
    case timeout
    case badResponse
    case servicesHandshake
    case unsupportedService
    case error(id: String, message: String?)
}
