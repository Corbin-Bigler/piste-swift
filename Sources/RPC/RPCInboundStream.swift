//
//  RPCInboundStream.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/17/25.
//

import Combine

public protocol RPCInboundStream<Inbound> {
    associatedtype Inbound
    
    var onValue: AnyPublisher<Inbound, Never> { get }
    var onClose: AnyPublisher<RPCStreamClosure, Never> { get }
    
    func close(cause: RPCError?)
    func open() async throws
}
