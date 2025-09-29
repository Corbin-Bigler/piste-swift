//
//  PisteService.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

import Foundation

public protocol PisteService {
    associatedtype Serverbound: Sendable
    associatedtype Clientbound: Sendable
    
    nonisolated static var id: PisteId { get }
    
    nonisolated static var title: String { get }
    nonisolated static var description: String { get }
}
public extension PisteService {
    nonisolated var id: PisteId { Self.id }
    nonisolated var title: String { Self.title }
    nonisolated var description: String { Self.description }
}
