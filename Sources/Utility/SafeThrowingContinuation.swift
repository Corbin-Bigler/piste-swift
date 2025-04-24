//
//  SafeThrowingContinuation.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 12/10/24.
//

import Foundation

final class SafeThrowingContinuation<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, Swift.Error>?
    private let lock = NSLock()
    private(set) var isResumed = false

    init(_ continuation: CheckedContinuation<T, Swift.Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        defer { lock.unlock() }
        guard !isResumed else { return }
        isResumed = true
        continuation?.resume(returning: value)
        continuation = nil
    }

    func resume() where T == () {
        resume(returning: ())
    }

    func resume(throwing error: Swift.Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !isResumed else { return }
        isResumed = true
        continuation?.resume(throwing: error)
        continuation = nil
    }
    
    enum Error: Swift.Error {
        case incorrectType
    }
}

protocol AnySafeThrowingContinuation {
    func resume(returning value: Any) throws
    func resume(throwing error: Error)
}
extension SafeThrowingContinuation: AnySafeThrowingContinuation {
    func resume(returning value: Any) throws {
        guard let value = value as? T else {
            throw Error.incorrectType
        }
        resume(returning: value)
    }
}

func withSafeThrowingContinuation<T>(
    isolation: isolated (any Actor)? = nil,
    function: String = #function,
    _ body: @escaping (SafeThrowingContinuation<T>) -> Void
) async throws -> T {
    try await withCheckedThrowingContinuation(isolation: isolation, function: function) { continuation in
        let safeContinuation = SafeThrowingContinuation(continuation)
        body(safeContinuation)
    }
}
