//
//  PisteErrorPayload.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/7/25.
//

struct PisteErrorPayload: Codable, Sendable, RPCError {
    let code: String
    let message: String?
}
