//
//  RPCError.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/7/25.
//

public protocol RPCError: Error {
    var code: String { get }
    var message: String? { get }
}
public extension RPCError {
    var message: String? { nil }
}
