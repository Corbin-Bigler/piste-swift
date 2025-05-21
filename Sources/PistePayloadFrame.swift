//
//  PistePayloadFrame.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/7/25.
//

struct PistePayloadFrame<Payload: Codable & Sendable>: Codable, Sendable {
    let id: String
    let request: Int
    let payload: Payload
}
