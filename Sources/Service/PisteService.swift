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
    nonisolated static var type: PisteServiceType { get }
}
