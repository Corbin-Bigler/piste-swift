//
//  PisteStreamFrame.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/7/25.
//

struct PisteStreamFrame: Codable, Sendable {
    let id: String
    let request: Int
    let action: PisteStreamAction
}
