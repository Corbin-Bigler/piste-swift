//
//  PisteApp.swift
//  piste
//
//  Created by Corbin Bigler on 4/24/25.
//

import SwiftCBOR
import Foundation

public class PisteServer: @unchecked Sendable {
    private let decoder = CodableCBORDecoder()
    private let encoder = CodableCBOREncoder()
    
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

    private var write: (Data)->Void = {_ in}
    private var close: ()->Void = {}
    
    public init() {
        register(PisteVersionsHandler(server: self))
        register(PisteInformationHandler(server: self))
    }
    
    public func onWrite(_ callback: @escaping (Data)->Void) {
        self.write = callback
    }
    public func onClose(_ callback: @escaping ()->Void) {
        self.close = callback
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
    
    
    private func handle<Handler: TransientPisteHandler>(_ data: Data, for handler: Handler) {
        let channel = PisteChannel<Handler.Service>(write: write)
        guard let serverbound = decodePayload(data, channel: channel) else { return }
        
        Task {
            do {
                channel.respond(with: try await (self.transientHandlers[handler.id]![handler.version]! as! Handler).handle(inbound: serverbound))
            } catch {
                self.handleError(error, pisteChannel: channel)
            }
        }
    }
    private func handle<Handler: PersistentPisteHandler>(_ data: Data, for handler: Handler) {
        let channel = PisteChannel<Handler.Service>(write: write)
        guard let serverbound = decodePayload(data, channel: channel) else { return }

        do {
            try (self.persistentHandlers[handler.id]![handler.version]! as! Handler).handle(channel: channel, inbound: serverbound)
        } catch {
            handleError(error, pisteChannel: channel)
        }
    }
    private func handleError<Service>(_ error: Error, pisteChannel: PisteChannel<Service>) {
        if let pisteError = error as? any PisteError {
            pisteChannel.error(pisteError.id, message: pisteError.message)
        } else {
            print("Unknown error caught: \(error)")
            pisteChannel.error(PisteServerError.internalServerError.id, message: PisteServerError.internalServerError.message)
        }
    }
    private func decodePayload<Service>(_ data: Data, channel: PisteChannel<Service>) -> Service.Serverbound? {
        guard let payload = try? decoder.decode(PisteFrame<Service.Serverbound>.self, from: data).payload else {
            channel.error(PisteServerError.badPayload.id, message: PisteServerError.badPayload.message)
            return nil
        }
        return payload
    }

    public func handle(data: Data) {
        guard let headers = try? decoder.decode(PisteFrameHeader.self, from: data) else {
            if let data = try? encoder.encode(PisteErrorFrame(error: "bad-frame", message: "Invalid frame format")) { write(data) }
            return
        }
        
        if let handler = self.transientHandlers[headers.service]?[headers.version] {
            handle(data, for: handler)
        } else if let handler = self.persistentHandlers[headers.service]?[headers.version] {
            handle(data, for: handler)
        } else {
            let error = self.transientHandlers[headers.service] == nil &&
            self.persistentHandlers[headers.service] == nil
            ? PisteServerError.unsupportedService(service: headers.service)
            : PisteServerError.unsupportedVersion(service: headers.service, version: headers.version)
            if let data = try? encoder.encode(PisteErrorFrame(error: error.id, service: headers.service, version: headers.version, message: error.message)) { write(data) }
        }
    }
}
