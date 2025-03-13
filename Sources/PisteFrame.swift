//
//  PisteFrame.swift
//  piste
//
//  Created by Corbin Bigler on 3/11/25.
//

import Foundation
import Hardpack

public struct PisteFrame<Payload: Codable & Sendable>: Codable, Sendable {
    public let function: PisteFunction
    public let version: Int
    public let payload: Payload
    
    public init(function: PisteFunction, version: Int, payload: Payload) {
        self.function = function
        self.version = version
        self.payload = payload
    }
}
