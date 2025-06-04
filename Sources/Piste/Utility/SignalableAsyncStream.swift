//
//  AsyncStream.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/4/25.
//

import Foundation

struct SignalableAsyncStream<Element>: AsyncSequence {
    let stream: AsyncStream<Element>
    let onStart: @Sendable () -> Void
    
    init(_ stream: AsyncStream<Element>, onStart: @Sendable @escaping () -> Void) {
        self.stream = stream
        self.onStart = onStart
    }

    func makeAsyncIterator() -> AsyncIterator {
        .init(iterator: stream.makeAsyncIterator(), onStart: onStart)
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: AsyncStream<Element>.AsyncIterator
        let onStart: @Sendable () -> Void
        private let signalState = SignalState()

        mutating func next() async -> Element? {
            await signalState.trySignal(onStart)
            return await iterator.next()
        }
    }

    private actor SignalState {
        private var hasSignaled = false

        func trySignal(_ onStart: @Sendable () -> Void) {
            guard !hasSignaled else { return }
            hasSignaled = true
            onStart()
        }
    }
}
