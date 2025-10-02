//
//  AsyncClosureQueue.swift
//  Piste
//
//  Created by Corbin Bigler on 10/2/25.
//

import Foundation

actor AsyncClosureQueue<T: Sendable> {
    private let closure: @Sendable (T) async throws -> Void
    init(closure: @escaping @Sendable (T) async throws -> Void) {
        self.closure = closure
    }
    func invoke(_ value: T) async throws {
        try await closure(value)
    }
}
