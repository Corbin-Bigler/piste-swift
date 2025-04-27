//
//  PisteClient.swift
//  test-client
//
//  Created by Corbin Bigler on 4/24/25.
//

import Foundation
import SwiftCBOR
@preconcurrency import Combine

public final class PisteClient: @unchecked Sendable {
    private static let defaultVersions = [
        PisteVersionsService.id: [PisteVersionsService.version],
        PisteInformationService.id: [PisteInformationService.version]
    ]

    private(set) var versions: [String: [Int]] = defaultVersions
    
    private let decoder = CodableCBORDecoder()
    private let encoder = CodableCBOREncoder()

    private let queue = DispatchQueue(label: "com.thysmesi.piste.client")
    private var requests: [String: [Int: AnySafeThrowingContinuation]] = [:]
    private var requestServices: [String: [Int: any TransientPisteService.Type]] = [:]
    private var subjects: [String: [Int: Any]] = [:]
    private var subjectServices: [String: [Int: any PersistentPisteService.Type]] = [:]
    private var send: ((Data) -> Void)?
    
    public init() {}
    
    public func onData(_ data: Data) {
        queue.async { [self] in
            guard let headers = try? decoder.decode(PisteFrameHeader.self, from: data) else { return }
      
            if let transientService = requestServices[headers.service]?[headers.version] {
                handle(data, headers: headers, for: transientService)
            } else if let persistentServices = subjectServices[headers.service]?[headers.version] {
                handle(data, headers: headers, for: persistentServices)
            }
        }
    }
    public func onConnect(send: @escaping (Data) -> Void) async throws {
        self.send = send
        self.versions = try await request(for: PisteVersionsService.self)
    }
    public func onDisconnect() {
        self.send = nil
        self.versions = Self.defaultVersions
        self.requestServices = [:]
        self.subjectServices = [:]
        for versions in requests.values {
            for request in versions {
                request.value.resume(throwing: PisteClientError.disconnected)
            }
        }
        self.requests = [:]
        self.subjects = [:]
    }
    
    public func request<Service: TransientPisteService>(_ serverbound: Service.Serverbound, for service: Service.Type) async throws -> Service.Clientbound {
        guard let serviceVersions = queue.sync(execute: {versions[service.id]}) else { throw PisteClientError.unsupportedService }
        guard serviceVersions.contains(service.version) else { throw PisteClientError.unsupportedVersion }
        
        return try await withSafeThrowingContinuation { continuation in
            self.queue.async {
                self.requestServices[Service.id, default: [:]][Service.version] = Service.self
                self.requests[Service.id, default: [:]][Service.version] = continuation
                
                Task {
                    do { try await self._send(serverbound, for: service) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }
    }
    public func request<Service: TransientPisteService>(for service: Service.Type) async throws -> Service.Clientbound where Service.Serverbound == Empty {
        return try await self.request(Empty(), for: service)
    }
    
    public func publisher<Service: PersistentPisteService>(service: Service.Type) -> PassthroughSubject<PersistentServiceResponse<Service.Clientbound>, Never> {
        let subject = PassthroughSubject<PersistentServiceResponse<Service.Clientbound>, Never>()
        self.queue.async {
            self.subjectServices[Service.id, default: [:]][Service.version] = Service.self
            self.subjects[Service.id, default: [:]][Service.version] = subject
        }
        return subject
    }
    
    public func send<Service: PersistentPisteService>(_ serverbound: Service.Serverbound, for service: Service.Type) async throws {
        try await _send(serverbound, for: service)
    }
    
    private func _send<Service: PisteService>(_ outbound: Service.Serverbound, for service: Service.Type) async throws {
        guard let send else { throw PisteClientError.disconnected }
        send(try encoder.encode(service.serverbound(outbound)))
    }
    
    private func handle<Service: TransientPisteService>(_ data: Data, headers: PisteFrameHeader, for service: Service.Type) {
        do {
            let clientbound = try decoder.decode(PisteFrame<Service.Clientbound>.self, from: data).payload
            guard let request = requests[headers.service]?[headers.version] else { return }
            try! request.resume(returning: clientbound)
        } catch {
            if let error = try? decoder.decode(PisteErrorFrame.self, from: data) {
                guard let request = requests[headers.service]?[headers.version] else { return }
                request.resume(throwing: PisteClientError.error(id: error.error, message: error.message))
            } else {
                print(error)
            }
        }
    }
    private func handle<Service: PersistentPisteService>(_ data: Data, headers: PisteFrameHeader, for service: Service.Type) {
        do {
            let clientbound = try decoder.decode(PisteFrame<Service.Clientbound>.self, from: data).payload
            guard let subject = subjects[headers.service]?[headers.version] as? PassthroughSubject<PersistentServiceResponse<Service.Clientbound>, Never> else { return }
            subject.send(.response(clientbound))
        } catch {
            if let error = try? decoder.decode(PisteErrorFrame.self, from: data) {
                guard let subject = subjects[headers.service]?[headers.version] as? PassthroughSubject<PersistentServiceResponse<Service.Clientbound>, Never> else { return }
                subject.send(.error(id: error.error, message: error.message))
            } else {
                print(error)
            }
        }
    }
}
