//
//  PisteService.swift
//  lion-simulator
//
//  Created by Corbin Bigler on 4/23/25.
//

import Foundation

public protocol PisteService {
    associatedtype Serverbound: Codable = Empty
    associatedtype Clientbound: Codable = Empty
    
    static var version: Int { get }
    static var id: String { get }
    static var persistent: Bool { get }
}

extension PisteService {
    static func serverbound(_ serverbound: Serverbound) -> PisteFrame<Serverbound> {
        return PisteFrame(service: id, version: version, payload: serverbound)
    }
    static func clientbound(_ clientbound: Clientbound) -> PisteFrame<Clientbound> {
        return PisteFrame(service: id, version: version, payload: clientbound)
    }
    static func error(_ error: String, message: String? = nil) -> PisteErrorFrame {
        return PisteErrorFrame(error: error, service: id, version: version, message: message)
    }
}
