//
//  RPCStream.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/20/25.
//

import Combine

public enum RPCUploadCompletion<Inbound: Sendable>: Sendable {
    case remote(RPCError)
    case local(Swift.Error)
    case payload(Inbound)
}

public enum RPCStreamCompletion: Sendable {
    case remote(RPCError)
    case local(Swift.Error)
    case completed
}

public struct RPCServerDownloadStream<Outbound: Sendable>: Sendable {
    private let _onComplete: Promise<RPCStreamCompletion>
    public var onComplete: RPCStreamCompletion {
        get async { await _onComplete.value }
    }

    private let sendHandler: @Sendable (Outbound) -> Void
    private let closeHandler: @Sendable (RPCError) -> Void
    
    init(
        onComplete: Promise<RPCStreamCompletion>,
        sendHandler: @Sendable @escaping (Outbound) -> Void,
        closeHandler: @Sendable @escaping (RPCError) -> Void
    ) {
        self._onComplete = onComplete
        self.sendHandler = sendHandler
        self.closeHandler = closeHandler
    }
    
    public func send(_ value: Outbound) {
        sendHandler(value)
    }
    public func close(_ reason: RPCError) {
        closeHandler(reason)
    }
}
public struct RPCServerUploadStream<Inbound: Sendable, Outbound: Sendable>: Sendable {
    public let onValue: AsyncStream<Inbound>
    private let _onComplete: Promise<RPCStreamCompletion>
    public var onComplete: RPCStreamCompletion {
        get async { await _onComplete.value }
    }

    private let completeHandler: @Sendable (Outbound) -> Void
    private let closeHandler: @Sendable (RPCError) -> Void
    
    init(
        onValue: AsyncStream<Inbound>,
        onComplete: Promise<RPCStreamCompletion>,
        completeHandler: @Sendable @escaping (Outbound) -> Void,
        closeHandler: @Sendable @escaping (RPCError) -> Void
    ) {
        self.onValue = onValue
        self._onComplete = onComplete
        self.completeHandler = completeHandler
        self.closeHandler = closeHandler
    }
    
    public func complete(_ value: Outbound) {
        completeHandler(value)
    }
    public func close(_ reason: RPCError) {
        closeHandler(reason)
    }
}

public struct RPCServerChannelStream<Inbound: Sendable, Outbound: Sendable>: Sendable {
    public let onValue: AsyncStream<Inbound>
    private let _onComplete: Promise<RPCStreamCompletion>
    public var onComplete: RPCStreamCompletion {
        get async { await _onComplete.value }
    }

    private let sendHandler: @Sendable (Outbound) -> Void
    private let closeHandler: @Sendable (RPCError) -> Void
    
    init(
        onValue: AsyncStream<Inbound>,
        onComplete: Promise<RPCStreamCompletion>,
        sendHandler: @Sendable @escaping (Outbound) -> Void,
        closeHandler: @Sendable @escaping (RPCError) -> Void
    ) {
        self.onValue = onValue
        self._onComplete = onComplete
        self.sendHandler = sendHandler
        self.closeHandler = closeHandler
    }
    
    public func send(_ value: Outbound) {
        sendHandler(value)
    }
    public func close(_ reason: RPCError) {
        closeHandler(reason)
    }
}

public struct RPCClientDownloadStream<Inbound: Sendable>: Sendable {
    public let onValue: AsyncStream<Inbound>
    private let _onComplete: Promise<RPCStreamCompletion>
    public var onComplete: RPCStreamCompletion {
        get async { await _onComplete.value }
    }

    private let closeHandler: @Sendable (RPCError) -> Void
    private let openHandler: @Sendable () async throws -> Void
    
    init(
        onValue: AsyncStream<Inbound>,
        onComplete: Promise<RPCStreamCompletion>,
        closeHandler: @Sendable @escaping (RPCError) -> Void,
        openHandler: @Sendable @escaping () async throws -> Void
    ) {
        self.onValue = onValue
        self._onComplete = onComplete
        self.closeHandler = closeHandler
        self.openHandler = openHandler
    }

    public func close(_ reason: RPCError) {
        closeHandler(reason)
    }
    public func open() async throws {
        try await openHandler()
    }
}
public struct RPCClientUploadStream<Inbound: Sendable, Outbound: Sendable>: Sendable {
    private let _onComplete: Promise<RPCUploadCompletion<Inbound>>
    public var onComplete: RPCUploadCompletion<Inbound> {
        get async { await _onComplete.value }
    }

    private let sendHandler: @Sendable (Outbound) -> Void
    private let closeHandler: @Sendable (RPCError) -> Void
    private let openHandler: @Sendable () async throws -> Void
    
    init(
        onComplete: Promise<RPCUploadCompletion<Inbound>>,
        sendHandler: @Sendable @escaping (Outbound) -> Void,
        closeHandler: @Sendable @escaping (RPCError) -> Void,
        openHandler: @Sendable @escaping () async throws -> Void
    ) {
        self._onComplete = onComplete
        self.sendHandler = sendHandler
        self.closeHandler = closeHandler
        self.openHandler = openHandler
    }
    
    public func send(_ value: Outbound) {
        sendHandler(value)
    }
    public func close(_ reason: RPCError) {
        closeHandler(reason)
    }
    public func open() async throws {
        try await openHandler()
    }
}
public struct RPCClientChannelStream<Inbound: Sendable, Outbound: Sendable>: Sendable {
    public let onValue: AsyncStream<Inbound>
    private let _onComplete: Promise<RPCStreamCompletion>
    public var onComplete: RPCStreamCompletion {
        get async { await _onComplete.value }
    }

    private let sendHandler: @Sendable (Outbound) -> Void
    private let closeHandler: @Sendable (RPCError) -> Void
    private let openHandler: @Sendable () async throws -> Void
    
    init(
        onValue: AsyncStream<Inbound>,
        onComplete: Promise<RPCStreamCompletion>,
        sendHandler: @Sendable @escaping (Outbound) -> Void,
        closeHandler: @Sendable @escaping (RPCError) -> Void,
        openHandler: @Sendable @escaping () async throws -> Void
    ) {
        self.onValue = onValue
        self._onComplete = onComplete
        self.sendHandler = sendHandler
        self.closeHandler = closeHandler
        self.openHandler = openHandler
    }
    
    public func send(_ value: Outbound) {
        sendHandler(value)
    }
    public func close(_ reason: RPCError) {
        closeHandler(reason)
    }
    public func open() async throws {
        try await openHandler()
    }
}
