//
//  TestCallService.swift
//  Piste
//
//  Created by Corbin Bigler on 9/25/25.
//

import Piste

struct TestCallService: CallPisteService {
    typealias Serverbound = String
    typealias Clientbound = String
    
    static let id: PisteId = 0xAAAAAA00
    
    static let title: String = "Test Call Servie"
    static let description: String = "Used for testing call services"
}
