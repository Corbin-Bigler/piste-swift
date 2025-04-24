//
//  PisteError.swift
//  lion-simulator
//
//  Created by Corbin Bigler on 4/23/25.
//

import Foundation

public protocol PisteError: Error, RawRepresentable where RawValue == String {
    var message: String? { get }
}
public extension PisteError {
    var message: String? { nil }
}
