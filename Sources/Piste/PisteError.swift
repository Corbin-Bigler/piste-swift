//
//  PisteError.swift
//  piste-swift
//
//  Created by Corbin Bigler on 4/27/25.
//

public protocol PisteError: Error {
    var id: String { get }
    var message: String? { get }
}
public extension PisteError {
    var message: String? { nil }
}
