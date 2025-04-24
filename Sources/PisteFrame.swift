//
//  PisteFrame.swift
//  lion-simulator
//
//  Created by Corbin Bigler on 4/23/25.
//

import Foundation

struct PisteFrame<Payload: Codable & Sendable>: Codable, Sendable {
    let service: String
    let version: Int
    let payload: Payload
}
