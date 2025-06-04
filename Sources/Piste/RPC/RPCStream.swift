//
//  RPCStream.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/17/25.
//

import Combine

public struct RPCStream<Outbound: Sendable, Inbound: Sendable>: RPCClientStream, RPCInboundStream, RPCOutboundStream {
    private let _onValue: (AsyncStream<Inbound>)?
    public var onValue: AsyncStream<Inbound> { _onValue! }
    private let _onClose: (AsyncStream<RPCInboundStreamClosure>)?
    public var onClose: AsyncStream<RPCInboundStreamClosure> { _onClose! }
    private let _onComplete: (AsyncStream<RPCOutboundStreamCompletion<Inbound>>)?
    public var onComplete: AsyncStream<RPCOutboundStreamCompletion<Inbound>> { _onComplete! }

    private let sendCallback: ((Outbound) -> Void)?
    private let openCallback: () async throws -> Void
    private let closeCallback: (RPCError) -> Void
    
    init(
        onValue: AsyncStream<Inbound>,
        onClose: AsyncStream<RPCInboundStreamClosure>,
        sendCallback: @escaping (Outbound) -> Void,
        openCallback: @escaping () async throws -> Void,
        closeCallback: @escaping (RPCError) -> Void
    ) {
        self._onValue = onValue
        self._onClose = onClose
        self._onComplete = nil
        self.sendCallback = sendCallback
        self.openCallback = openCallback
        self.closeCallback = closeCallback
    }
    init(
        onComplete: AsyncStream<RPCOutboundStreamCompletion<Inbound>>,
        sendCallback: @escaping (Outbound) -> Void,
        openCallback: @escaping () async throws -> Void,
        closeCallback: @escaping (RPCError) -> Void
    ) {
        self._onValue = nil
        self._onClose = nil
        self._onComplete = onComplete
        self.sendCallback = sendCallback
        self.openCallback = openCallback
        self.closeCallback = closeCallback
    }

    public func finish(_ outbound: Outbound) {
        sendCallback?(outbound)
    }
    public func send(_ outbound: Outbound) {
        sendCallback?(outbound)
    }
    public func open() async throws {
        try await openCallback()
    }
    public func close(_ reason: RPCError) {
        closeCallback(reason)
    }
}
