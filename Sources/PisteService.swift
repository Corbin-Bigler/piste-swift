//
//  PisteService.swift
//  piste
//
//  Created by Corbin Bigler on 3/12/25.
//

import Hardpack

public protocol PisteService: Sendable {
    associatedtype ServerBound: Codable, Sendable
    associatedtype ClientBound: Codable, Sendable
        
    static var function: PisteFunction { get }
    static var version: Int { get }
}

extension PisteService {
    static var function: PisteFunction { Self.function }
    static var version: Int { Self.version }
    
    func serverbound(encoded: EncodedPisteFrame) -> PisteFrame<ServerBound>? {
        let decoder = HardpackDecoder()
        guard let payload = try? decoder.decode(ServerBound.self, from: encoded.payload) else { return nil }
        return PisteFrame(function: encoded.function, version: Int(encoded.version), payload: payload)
    }
    func clientbound(encoded: EncodedPisteFrame) -> PisteFrame<ClientBound>? {
        let decoder = HardpackDecoder()
        guard let payload = try? decoder.decode(ClientBound.self, from: encoded.payload) else { return nil }
        return PisteFrame(function: encoded.function, version: Int(encoded.version), payload: payload)
    }
}



//    public func registerService(
//        _ service: Service.Type,
//        handler: @Sendable @escaping (PisteFrame<Service.ServerBound>) async -> PisteResponse<Service.ClientBound>
//    ) {

//    private(set) var handlers: [PisteFunction: [Int: @Sendable (EncodedPisteFrame) async throws -> EncodedPisteFrame]] = [:]
//    private(set) var services: [PisteFunction: [Int: any PisteService.Type]] = [:]
