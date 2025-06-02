//
//  RPCStream.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/17/25.
//

import Combine

public struct RPCStream<Outbound, Inbound>: RPCChannelStream, RPCInboundStream, RPCOutboundStream {
    let onValueSubject: PassthroughSubject<Inbound, Never>
    let onCloseSubject: PassthroughSubject<RPCStreamClosure, Never>
    let sendCallback: (Outbound) -> Void
    let closeCallback: (RPCError?) -> Void
    let openCallback: () async throws -> Void
    
    public var onValue: AnyPublisher<Inbound, Never> { onValueSubject.eraseToAnyPublisher() }
    public var onClose: AnyPublisher<RPCStreamClosure, Never> { onCloseSubject.eraseToAnyPublisher() }
    
    public init(
        onClose: PassthroughSubject<RPCStreamClosure, Never>,
        close: @escaping (RPCError?) -> Void,
        send: @escaping (Outbound) -> Void,
        open: @escaping () async throws -> Void
    ) where Inbound == Never {
        self.onValueSubject = .init()
        self.onCloseSubject = onClose
        self.closeCallback = close
        self.sendCallback = send
        self.openCallback = open
    }
    
    public init(
        onValue: PassthroughSubject<Inbound, Never>,
        onClose: PassthroughSubject<RPCStreamClosure, Never>,
        close: @escaping (RPCError?) -> Void,
        open: @escaping () async throws -> Void
    ) where Outbound == Never {
        self.onValueSubject = onValue
        self.onCloseSubject = onClose
        self.closeCallback = close
        self.sendCallback = {_ in}
        self.openCallback = open
    }

    public init(
        onValue: PassthroughSubject<Inbound, Never>,
        onClose: PassthroughSubject<RPCStreamClosure, Never>,
        close: @escaping (RPCError?) -> Void,
        send: @escaping (Outbound) -> Void,
        open: @escaping () async throws -> Void
    ) {
        self.onValueSubject = onValue
        self.onCloseSubject = onClose
        self.closeCallback = close
        self.sendCallback = send
        self.openCallback = open
    }
     
    public func send(_ outbound: Outbound) {
        sendCallback(outbound)
    }
    public func close(cause: RPCError?) {
        closeCallback(cause)
    }
    public func open() async throws {
        try await openCallback()
    }
}
