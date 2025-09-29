//
//  TestCallHandler.swift
//  Piste
//
//  Created by Corbin Bigler on 9/25/25.
//

import Piste

struct TestCallHandler: CallPisteHandler {
    static let service = TestCallService.self
    
    static func mutated(request: String) -> String {
        "Echo: \(request)"
    }
            
    func handle(request: String) async throws -> String {
        return Self.mutated(request: request)
    }
}
