//
//  PisteContentPayload.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/7/25.
//

struct PisteContentPayload<Content: Codable & Sendable>: Codable, Sendable {
    let id: String
    let request: Int
    let content: Content
}
