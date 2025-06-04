//
//  RPCStreamClosure.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/20/25.
//

public enum RPCStreamClosure: Error {
    case inbound(RPCError)
    case `internal`(Error)
    case finished
}

