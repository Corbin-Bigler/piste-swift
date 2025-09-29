//
//  PisteCodec.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

import Foundation

public protocol PisteCodec: Sendable {
    nonisolated func encode<T>(_ value: T) throws -> Data
    nonisolated func decode<T>(_ data: Data) throws -> T
}
