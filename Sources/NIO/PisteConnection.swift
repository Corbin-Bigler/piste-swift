//
//  PisteApp.swift
//  piste
//
//  Created by Corbin Bigler on 4/24/25.
//

import NIOCore

public class PisteConnection: @unchecked Sendable {
    private(set) var handlers: [String: [Int : any PisteHandler]] = [:]
    
    private let context: ChannelHandlerContext
    init(context: ChannelHandlerContext) {
        self.context = context
    }

    public func register(_ handler: any PisteHandler) {
        guard handlers[handler.id]?[handler.version] == nil else {
            fatalError("Trying to reregister handler: \(handler.id)-\(handler.version)")
        }
        handlers[handler.id, default: [:]][handler.version] = handler
    }
}
