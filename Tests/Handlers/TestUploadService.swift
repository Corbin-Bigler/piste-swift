//
//  TestUploadService.swift
//  Piste
//
//  Created by Corbin Bigler on 9/18/25.
//

import Piste

struct TestUploadService: UploadPisteService {
    typealias Serverbound = String
    typealias Clientbound = String
    
    static let id: PisteId = 0xAAAAAA02
    
    static let title: String = "Test Upload Service"
    static let description: String = "Used for testing upload services"
}
