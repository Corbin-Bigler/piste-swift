//
//  PisteResponse.swift
//  piste
//
//  Created by Corbin Bigler on 3/16/25.
//

public enum PisteResponse<T: Codable & Sendable> {
    case failure(String)
    case success(T)
}
