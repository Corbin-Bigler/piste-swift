//
//  PisteApp.swift
//  piste
//
//  Created by Corbin Bigler on 4/24/25.
//

import NIOCore

public class PisteConnection: @unchecked Sendable {
    private(set) var transientHandlers: [String: [Int : any TransientPisteHandler]] = [:]
    private(set) var persistentHandlers: [String: [Int : any PersistentPisteHandler]] = [:]
    var handlers: [String: [Int: any PisteHandler]] {
        var allHandlers: [String: [Int: any PisteHandler]] = [:]

        for (key, versions) in transientHandlers {
            allHandlers[key, default: [:]].merge(versions) { (_, new) in new }
        }

        for (key, versions) in persistentHandlers {
            allHandlers[key, default: [:]].merge(versions) { (_, new) in new }
        }

        return allHandlers
    }

    private let context: ChannelHandlerContext
    init(context: ChannelHandlerContext) {
        self.context = context
    }

    public func register(_ handler: any TransientPisteHandler) {
        guard handlers[handler.id]?[handler.version] == nil else {
            fatalError("Trying to reregister handler: \(handler.id)-\(handler.version)")
        }
        transientHandlers[handler.id, default: [:]][handler.version] = handler
    }
    public func register(_ handler: any PersistentPisteHandler) {
        guard handlers[handler.id]?[handler.version] == nil else {
            fatalError("Trying to reregister handler: \(handler.id)-\(handler.version)")
        }
        persistentHandlers[handler.id, default: [:]][handler.version] = handler
    }
}
