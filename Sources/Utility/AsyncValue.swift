//
//  AsyncValue.swift
//  Piste
//
//  Created by Corbin Bigler on 9/26/25.
//

actor AsyncValue<T: Sendable, E: Error> {
    private var stored: Result<T, E>?
    private var waiting: [CheckedContinuation<T, any Error>] = []

    init(build: (AsyncValue<T, E>.Continuation) -> Void) {
        build(Continuation(asyncValue: self))
    }
    
    func get() async throws -> T {
        if let value = stored {
            return try value.get()
        }

        return try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
        }
    }
    
    func get() async -> T where E == Never {
        if let value = stored {
            return value.get()
        }

        return try! await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
        }
    }

    private func resume(returning value: T) {
        guard stored == nil else {
            assertionFailure("AsyncValue resumed more than once")
            return
        }
        
        stored = .success(value)
        for cont in waiting {
            cont.resume(returning: value)
        }
        waiting.removeAll()
    }
    private func resume(throwing error: E) {
        guard stored == nil else {
            assertionFailure("AsyncValue resumed more than once")
            return
        }
        
        for cont in waiting {
            cont.resume(throwing: error)
        }
        waiting.removeAll()
    }
    
    struct Continuation: Sendable {
        fileprivate let asyncValue: AsyncValue<T, E>
        
        func resume(returning value: T) async {
            await asyncValue.resume(returning: value)
        }
        func resume() async where T == Void {
            await asyncValue.resume(returning: ())
        }
        func resume(throwing error: E) async {
            await asyncValue.resume(throwing: error)
        }
    }
}
