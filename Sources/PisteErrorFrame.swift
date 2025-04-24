//
//  PisteErrorFrame.swift
//  lion-simulator
//
//  Created by Corbin Bigler on 4/23/25.
//

struct PisteErrorFrame: Codable {
    let error: String
    let service: String?
    let version: Int?
    let message: String?
    
    init(error: String, service: String? = nil, version: Int? = nil, message: String? = nil) {
        self.error = error
        self.service = service
        self.version = version
        self.message = message
    }
}
