//
//  TestDownloadService.swift
//  Piste
//
//  Created by Corbin Bigler on 9/18/25.
//

import Piste

struct TestDownloadService: DownloadPisteService {
    typealias Serverbound = String
    typealias Clientbound = String
    
    static let id: PisteId = 0xAAAAAA01
    
    static let title: String = "Test Download Service"
    static let description: String = "Used for testing download services"
}
