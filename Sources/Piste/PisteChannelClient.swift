//
//  PisteChannelClient.swift
//  piste-swift
//
//  Created by Corbin Bigler on 4/27/25.
//

import Foundation
import Logger
import SwiftProtobuf
@preconcurrency import Combine

public final class PisteChannelClient: @unchecked Sendable {
    private(set) var services: Set<String>?

    private let queue = DispatchQueue(label: "piste.channelClient")
    private let logger: Logger

    private var cancellables: [AnyCancellable] = []
    private var calls: [String: AnySafeThrowingContinuation] = [:]
    private var callServices: [String: any CallPisteService.Type] = [:]
    private var uploads: [String: AnySafeThrowingContinuation] = [:]
    private var uploadServices: [String: any UploadPisteService.Type] = [:]
    private var downloads: [String: Any] = [:]
    private var downloadServices: [String: any DownloadPisteService.Type] = [:]
    private var streams: [String: Any] = [:]
    private var streamServices: [String: any StreamingPisteService.Type] = [:]
    
    private var onRequest: (Data) -> () = { _ in }

    public init(logger: Logger = Logger.shared) {
        self.logger = logger
    }
    
    private func getServices() async throws -> Set<String> {
        if services == nil {
            do {
                let response = try await call(.init(), for: PisteGetServicesService.self)
                services = Set(response.services)
            } catch {
                logger.error("Error during services handshake: \(error)")
                throw PisteClientError.servicesHandshake
            }
        }
        
        return services!
    }
    
    public func onRequest(_ callback: @escaping (Data) -> ()) {
        queue.sync { self.onRequest = callback }
    }
    
    private func terminate<Service: DownloadPisteService>(service: Service.Type, error: Error? = PisteClientError.cancelled) {
        guard let download = downloads[service.path] as? PassthroughSubject<Service.Response, Error> else { return }
        download.send(completion: error.flatMap { .failure($0) } ?? .finished)
    }
    private func terminate<Service: StreamingPisteService>(service: Service.Type, error: Error? = PisteClientError.cancelled) {
        guard let stream = streams[service.path] as? PassthroughSubject<Service.Response, Error> else { return }
        stream.send(completion: error.flatMap { .failure($0) } ?? .finished)
    }
    public func terminated() {
        queue.async {
            for call in self.calls.values { call.resume(throwing: PisteClientError.cancelled) }
            self.calls = [:]
            self.callServices = [:]
            
            for upload in self.uploads.values { upload.resume(throwing: PisteClientError.cancelled) }
            self.uploads = [:]
            self.uploadServices = [:]
            
            for downloadService in self.downloadServices.values { self.terminate(service: downloadService) }
            self.downloads = [:]
            self.downloadServices = [:]
            
            for streamService in self.streamServices.values { self.terminate(service: streamService) }
            self.streams = [:]
            self.streamServices = [:]
            
            self.services = nil
        }
    }

    private func handle<Service: CallPisteService>(payload: Google_Protobuf_Any, for service: Service.Type) {
        guard let call = queue.sync(execute: { calls[service.path] as? SafeThrowingContinuation<Service.Response> }) else { return }
        do {
            let response = try Service.Response(unpackingAny: payload)
            call.resume(returning: response)
        } catch {
            logger.error("Unable to decode server response: \(error)")
            call.resume(throwing: error)
        }
    }
    private func handle<Service: DownloadPisteService>(payload: Google_Protobuf_Any, for service: Service.Type) {
        guard let subject = queue.sync(execute: { downloads[service.path] as? PassthroughSubject<Service.Response, Error> }) else { return }
        do {
            let response = try Service.Response(unpackingAny: payload)
            subject.send(response)
        } catch {
            logger.error("Unable to decode server response: \(error)")
            subject.send(completion: .failure(error))
        }
    }
    public func handle(_ data: Data) {
        print(try? PisteFrame(serializedBytes: data))
        print(try? PisteFrame(serializedBytes: data).hasPayload)
        print(try? PisteFrame(serializedBytes: data).unknownFields.data.isEmpty)
        if let frame = try? PisteFrame(serializedBytes: data), frame.hasPayload, frame.unknownFields.data.isEmpty {
            if let service = callServices[frame.path] {
                handle(payload: frame.payload, for: service)
            } else if let service = downloadServices[frame.path] {
                handle(payload: frame.payload, for: service)
            }
        } else if let error = try? PisteErrorFrame(serializedBytes: data), error.unknownFields.data.isEmpty {
            if error.hasPath {
                let clientError = PisteClientError.error(id: error.error, message: error.hasMessage ? error.message : nil)
                if let call = calls[error.path] {
                    call.resume(throwing: clientError)
                } else if let downloadService = downloadServices[error.path] {
                    terminate(service: downloadService, error: clientError)
                }
            } else {
                logger.error("Unexpected error: \(error)")
            }
        } else if let close = try? PisteCloseFrame(serializedBytes: data), close.unknownFields.data.isEmpty {
            if let downloadService = downloadServices[close.path] {
                terminate(service: downloadService, error: nil)
            }
        } else {
            logger.error("Unable to decode server frame: \(data.hexString)")
        }
    }
    
    private func send(path: String, payload: SwiftProtobuf.Message) throws {
        var frame = PisteFrame()
        frame.path = path
        frame.payload = try Google_Protobuf_Any(message: payload)

        let data: Data = try frame.serializedBytes()
        onRequest(data)
    }
    private func close(path: String) throws {
        guard self.downloadServices[path] != nil || self.uploadServices[path] != nil else { return }
        var frame = PisteCloseFrame()
        frame.path = path
        onRequest(try frame.serializedBytes())
    }
    public func call<Service: CallPisteService>(_ request: Service.Request, for service: Service.Type) async throws -> Service.Response {
        if service != PisteGetServicesService.self {
            let services = try await getServices()
            guard services.contains(service.path) else {
                throw PisteClientError.unsupportedService
            }
        }
        return try await withSafeThrowingContinuation { continuation in
            do {
                self.queue.async {
                    self.calls[service.path] = continuation
                    self.callServices[service.path] = Service.self
                }
                try self.send(path: service.path, payload: request)
            } catch {
                self.queue.async {
                    self.calls.removeValue(forKey: service.path)
                    self.callServices.removeValue(forKey: service.path)
                }
                continuation.resume(throwing: error)
            }
        }
    }
    public func download<Service: DownloadPisteService>(_ request: Service.Request, for service: Service.Type) async throws -> PassthroughSubject<Service.Response, Error> {
        guard try await getServices().contains(service.path) else { throw PisteClientError.unsupportedService }

        let subject = PassthroughSubject<Service.Response, Error>()
        do {
            self.queue.async {
                self.downloads[service.path] = subject
                self.downloadServices[service.path] = Service.self
            }
            try self.send(path: service.path, payload: request)
        } catch {
            self.queue.async {
                self.downloads.removeValue(forKey: service.path)
                self.downloadServices.removeValue(forKey: service.path)
            }
            throw error
        }
        
        subject
            .sink(
                receiveCompletion: { _ in
                    try? self.close(path: service.path)
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
        return subject
    }
}
