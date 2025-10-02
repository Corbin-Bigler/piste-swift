//
//  PisteChannel.swift
//  Piste
//
//  Created by Corbin Bigler on 9/18/25.
//

actor PisteChannel<Inbound: Sendable, Outbound: Sendable> {
    private let sendClosure: @Sendable (_ value: Outbound) async throws -> Void
    private let closeClosure: @Sendable () async -> Void
    
    nonisolated let inbound: AsyncStream<Inbound>
    let inboundContinuation: AsyncStream<Inbound>.Continuation
    
    private let closedValue: AsyncValue<Void, Error>
    private let closedContinuation: AsyncValue<Void, Error>.Continuation
    var closed: Void { get async throws { try await closedValue.get() } }
    func resumeClosed(error: Error?) async {
        await onClosed(error: error)
    }

    private let completedValue: AsyncValue<Inbound, Never>
    private let completedContinuation: AsyncValue<Inbound, Never>.Continuation
    var completed: Inbound { get async { await completedValue.get() } }
    func resumeCompleted(inbound: Inbound) async {
        await onCompleted(inbound)
    }

    init(
        send: @escaping @Sendable (_ value: Outbound) async throws -> Void = {_ in},
        close: @escaping @Sendable () async -> Void
    ) {
        var inboundContinuation: AsyncStream<Inbound>.Continuation!
        self.inbound = AsyncStream { inboundContinuation = $0 }
        self.inboundContinuation = inboundContinuation

        var closedContinuation: AsyncValue<Void, Error>.Continuation!
        self.closedValue = AsyncValue { closedContinuation = $0 }
        self.closedContinuation = closedContinuation

        var completedContinuation: AsyncValue<Inbound, Never>.Continuation!
        self.completedValue = AsyncValue { completedContinuation = $0 }
        self.completedContinuation = completedContinuation

        self.sendClosure = send
        self.closeClosure = close
    }

    func send(_ value: Outbound) async throws {
        try await self.sendClosure(value)
    }
    
    func close() async {
        await closeClosure()
    }
    
    private func onClosed(error: Error?) async {
        if let error {
            await closedContinuation.resume(throwing: error)
        } else {
            await closedContinuation.resume()
        }
        inboundContinuation.finish()
    }
    private func onCompleted(_ value: Inbound) async {
        await closedContinuation.resume()
        await completedContinuation.resume(returning: value)
        inboundContinuation.finish()
    }
}
