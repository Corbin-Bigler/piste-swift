//
//  RPCOutboundStream.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/20/25.
//

import Combine

public protocol RPCOutboundStream {
    associatedtype Outbound: Sendable
    associatedtype Inbound: Sendable

    var onComplete: AsyncStream<RPCOutboundStreamCompletion<Inbound>> { get }

    func send(_ outbound: Outbound)
    func close(_ reason: RPCError)
}
public enum RPCOutboundStreamCompletion<Payload: Sendable>: Sendable {
    case external(RPCError)
    case `internal`(Swift.Error)
    case completed(Payload)
}
