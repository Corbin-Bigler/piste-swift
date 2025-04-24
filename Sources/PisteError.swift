//
//  PisteError.swift
//  lion-simulator
//
//  Created by Corbin Bigler on 4/23/25.
//

import Foundation

public protocol PisteError: Error {
    var id: String { get }
    var message: String? { get }
}
public extension PisteError {
    var message: String? { nil }
}
