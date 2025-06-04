//
//  RPCInboundStream.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/17/25.
//

import Combine

public protocol RPCInboundStream {
    associatedtype Inbound: Sendable
    associatedtype Outbound: Sendable

    var onValue: AsyncStream<Inbound> { get }
    var onClose: AsyncStream<RPCInboundStreamClosure> { get }
    
    func finish(_ outbound: Outbound)
    func close(_ reason: RPCError)
}
public enum RPCInboundStreamClosure: Sendable {
    case external(RPCError)
    case `internal`(Swift.Error)
    case completed
}
