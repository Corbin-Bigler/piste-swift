//
//  PisteHandler.swift
//  lion-simulator
//
//  Created by Corbin Bigler on 4/23/25.
//

public protocol PisteHandler: Sendable {
    associatedtype Service: PisteService
    
    static var title: String { get }
    static var description: String { get }
    
    func handle(channel: PisteChannel<Service>, inbound: Service.Serverbound) throws
}
extension PisteHandler {
    var version: Int { Service.version }
    var id: String { Service.id }
    var persistent: Bool { Service.persistent }
}
