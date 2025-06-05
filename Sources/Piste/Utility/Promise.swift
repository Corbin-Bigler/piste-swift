//
//  Promise.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/4/25.
//

final actor Promise<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var result: Value?

    public var value: Value {
        get async {
            if let result = result {
                return result
            }

            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
    }

    public func resume(_ value: Value) {
        guard result == nil else { return }
        result = value
        continuation?.resume(returning: value)
    }
}
