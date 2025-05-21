//
//  RPCOutboundStream.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/20/25.
//

import Combine

public protocol RPCOutboundStream<Outbound> {
    associatedtype Outbound
    
    var onClose: AnyPublisher<RPCStreamClosure, Never> { get }
    
    func send(_ outbound: Outbound)
    func close(cause: RPCError?)
    func open() async throws
}
