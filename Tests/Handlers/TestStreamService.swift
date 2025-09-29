//
//  TestStreamService.swift
//  Piste
//
//  Created by Corbin Bigler on 9/18/25.
//

import Piste

struct TestStreamService: StreamPisteService {
    typealias Serverbound = String
    typealias Clientbound = String
    
    static let id: PisteId = 0xAAAAAA03
    
    static let title: String = "Test Stream Service"
    static let description: String = "Used for testing stream services"
}
