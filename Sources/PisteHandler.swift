//
//  PisteHandler.swift
//  lion-simulator
//
//  Created by Corbin Bigler on 4/23/25.
//

public protocol PisteHandler {
    associatedtype Service: PisteService
    
    static var title: String { get }
    static var description: String { get }

    init()

    func handle(context: PisteContext<Self>, serverbound: Service.Serverbound) throws
}
extension PisteHandler {
    static var version: Int { Service.version }
    static var id: String { Service.id }
    static var persistent: Bool { Service.persistent }
}
