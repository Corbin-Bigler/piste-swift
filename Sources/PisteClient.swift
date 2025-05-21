//
//  PisteClient.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/7/25.
//

import Foundation
@preconcurrency import Combine
import Logger
import SwiftCBOR

public class PisteClient: @unchecked Sendable {
    private static let openStreamTimeout: TimeInterval = 5
    private static let callTimeout: TimeInterval = 60
    
    private let queue = DispatchQueue(label: "com.thysmesi.piste.client")
    private let encoder = CodableCBOREncoder()
    private let decoder = CodableCBORDecoder()
    private let logger: Logger
    private let _onData = PassthroughSubject<Data, Never>()
    public var onData: AnyPublisher<Data, Never> { _onData.eraseToAnyPublisher() }
    
    private var increments: [String: Int] = [:]
    private var callContinuations: [String: [Int: AnySafeThrowingContinuation]] = [:]
    private var openStreamContinuations: [String: [Int: SafeThrowingContinuation<Void>]] = [:]
    private var inboundStreams: [String: [Int: any AnyInboundStream]] = [:]
    private var outboundCancellables: [String: [Int: AnyCancellable]] = [:]
    private var services: [String: any RPCService.Type] = [:]
    
    public init(logger: Logger = Logger.shared) {
        self.logger = logger
    }
    
    public func cancelAll() {
        queue.sync {
            for callContinuations in callContinuations.values {
                for callContinuation in callContinuations.values {
                    callContinuation.resume(throwing: Error.cancelled)
                }
            }
            callContinuations = [:]
            for openStreamContinuations in openStreamContinuations.values {
                for openStreamContinuation in openStreamContinuations.values {
                    openStreamContinuation.resume(throwing: Error.cancelled)
                }
            }
            openStreamContinuations = [:]
            for (id, inboundStreams) in inboundStreams {
                for request in inboundStreams.keys {
                    if let service = services[id] {
                        handleCloseStream(request: request, inbound: .internal(Error.cancelled), for: service)
                    }
                }
            }
            inboundStreams = [:]
            outboundCancellables = [:]
            services = [:]
        }
    }
    
    public func handle(data: Data) {
        queue.sync {
            guard let headers = try? decoder.decode(PistePayloadHeaders.self, from: data), let service = services[headers.id] else {
                logger.error("Received invalid frame format from server: \(data.base64EncodedString())")
                return
            }
            
            if let errorFrame = try? decoder.decode(PisteErrorFrame.self, from: data) {
                logger.error("Received Error Frame: \(errorFrame)")
                if (errorFrame.id != nil && errorFrame.request != nil) {
                    if let callContinuation = callContinuations[headers.id]?[headers.request] {
                        callContinuation.resume(throwing: errorFrame)
                        callContinuations[headers.id]?.removeValue(forKey: headers.request)
                        return
                    }
                    handleCloseStream(request: headers.request, inbound: .inbound(errorFrame), for: service)
                }
            } else if let streamFrame = try? decoder.decode(PisteStreamFrame.self, from: data) {
                logger.debug("Received Stream Frame: \(streamFrame)")
                if streamFrame.action == .open {
                    openStreamContinuations[streamFrame.id]?[streamFrame.request]?.resume()
                } else if streamFrame.action == .close {
                    handleCloseStream(request: headers.request, inbound: .finished, for: service)
                }
            } else if let service = services[headers.id] {
                handlePayload(data: data, for: service)
            } else {
                logger.error("Received Unrecognized Payload Frame: \(data.base64EncodedString())")
            }
        }
    }
    
    public func call<Service: RPCCallService>(_ request: Service.Request, for service: Service.Type) async throws -> Service.Response {
        queue.sync {
            services[service.id] = service
        }
        let requestId = getIncrement(for: service.id)
        return try await withSafeThrowingContinuation { [self] continuation in
            queue.async {
                self.callContinuations[service.id, default: [:]][requestId] = continuation
            }
            
            send(payload: request, request: requestId, for: service)
            Task {
                try await Task.sleep(for: .seconds(Self.callTimeout))
                if !continuation.isResumed {
                    continuation.resume(throwing: Error.timeout)
                }
            }
        }
    }
    public func download<Service: RPCDownloadService>(_ request: Service.Request, for service: Service.Type) -> any RPCInboundStream<Service.Response> {
        queue.sync {
            services[service.id] = service
        }
        let requestId = getIncrement(for: service.id)
        
        let stream = RPCStream(
            onValue: PassthroughSubject<Service.Response, Never>(),
            onClose: PassthroughSubject<RPCStreamClosure, Never>(),
            close: { [weak self] cause in
                self?.queue.sync {
                    self?.handleOutboundCloseStream(request: requestId, outbound: cause, for: service)
                }
            },
            open: { [weak self] in
                try await self?.openStream(id: service.id, request: requestId) {
                    self?.send(payload: request, request: requestId, for: service)
                }
            }
        )
        
        queue.sync {
            inboundStreams[service.id, default: [:]][requestId] = stream
        }
        return stream
    }
    public func upload<Service: RPCDownloadService>(for service: Service.Type) -> any RPCOutboundStream<Service.Request> {
        queue.sync {
            services[service.id] = service
        }
        let request = getIncrement(for: service.id)
        
        let stream = RPCStream(
            onClose: PassthroughSubject<RPCStreamClosure, Never>(),
            close: { [weak self] cause in
                self?.queue.sync {
                    self?.handleOutboundCloseStream(request: request, outbound: cause, for: service)
                }
            },
            send: { [weak self] (value: Service.Request) in
                self?.send(payload: value, request: request, for: service)
            },
            open: { [weak self] in
                try await self?.openStream(id: service.id, request: request) {
                    self?.send(stream: PisteStreamFrame(id: service.id, request: request, action: .open))
                }
            }
        )
        
        return stream
    }
    public func channel<Service: RPCChannelService>(for service: Service.Type) -> any RPCChannelStream<Service.Request, Service.Response> {
        queue.sync {
            services[service.id] = service
        }
        let request = getIncrement(for: service.id)
        
        let stream = RPCStream(
            onValue: PassthroughSubject<Service.Response, Never>(),
            onClose: PassthroughSubject<RPCStreamClosure, Never>(),
            close: { [weak self] cause in
                self?.handleOutboundCloseStream(request: request, outbound: cause, for: service)
            },
            send: { [weak self] (value: Service.Request) in
                self?.send(payload: value, request: request, for: service)
            },
            open: { [weak self] in
                try await self?.openStream(id: service.id, request: request) {
                    self?.send(stream: PisteStreamFrame(id: service.id, request: request, action: .open))
                }
            }
        )
        queue.sync {
            inboundStreams[service.id, default: [:]][request] = stream
        }
        return stream
    }
    
    private func handlePayload<Service: RPCService>(data: Data, for service: Service.Type) {
        do {
            let payloadFrame = try decoder.decode(PistePayloadFrame<Service.Response>.self, from: data)
            logger.debug("Received Payload Frame: \(payloadFrame)")
            if let inboundStream = inboundStreams[payloadFrame.id]?[payloadFrame.request] as? any AnyInboundStream<Service.Response> {
                inboundStream.onValueSubject.send(payloadFrame.payload)
            }
            
            if let callContinuation = callContinuations[service.id]?[payloadFrame.request] as? SafeThrowingContinuation<Service.Response> {
                callContinuation.resume(returning: payloadFrame.payload)
                callContinuations[service.id]?.removeValue(forKey: payloadFrame.request)
            }
        } catch {
            logger.fault("Failed to decode payload for service: \(service.id), error: \(error), data: \(data.base64EncodedString())")
        }
    }
    
    private func send<Service: RPCService>(payload: Service.Request, request: Int, for service: Service.Type) {
        let payloadFrame = PistePayloadFrame(id: service.id, request: request, payload: payload)
        do {
            let data = try encoder.encode(payloadFrame)
            logger.debug("Sending Payload: \(payloadFrame)")
            _onData.send(data)
        } catch {
            logger.fault("Failed to encode payload frame: \(payloadFrame)")
        }
    }
    private func send(error: RPCError, id: String, request: Int) {
        let errorFrame = PisteErrorFrame(code: error.code, message: error.message, id: id, request: request)
        do {
            let data = try encoder.encode(errorFrame)
            logger.debug("Sending Error: \(errorFrame)")
            _onData.send(data)
        } catch {
            logger.fault("Failed to encode error frame: \(errorFrame)")
        }
    }
    private func send(stream: PisteStreamFrame) {
        do {
            let data = try encoder.encode(stream)
            logger.debug("Sending Stream Action: \(stream)")
            _onData.send(data)
        } catch {
            logger.fault("Failed to encode stream frame: \(stream)")
        }
    }
    private func getIncrement(for id: String) -> Int {
        queue.sync {
            if increments[id] == nil { increments[id] = -1 }
            increments[id]! += 1
            return increments[id]!
        }
    }
    private func handleClientError(id: String, request: Int, error: Swift.Error) {
        if let error = error as? RPCError {
            send(error: error, id: id, request: request)
        } else {
            Logger.fault("Received unknown client error: \(error), sending: \(Error.internalClientError.code)")
            send(error: Error.internalClientError, id: id, request: request)
        }
    }
    private func handleCloseStream<Service: RPCService>(request: Int, inbound: RPCStreamClosure, for service: Service.Type) {
        if let stream = inboundStreams[service.id]?[request] as? any AnyInboundStream<Service.Response> {
            logger.debug("Closing Stream id: \(service.id), request: \(request), error: \(String(describing: inbound))")
            stream.onCloseSubject.send(inbound)
            inboundStreams[service.id]?.removeValue(forKey: request)
            outboundCancellables[service.id]?[request]?.cancel()
            outboundCancellables[service.id]?.removeValue(forKey: request)
        } else {
            Logger.fault("Received request to close unknown stream: \(service.id), request: \(request), closure: \(inbound)")
        }
    }
    private func handleOutboundCloseStream<Service: RPCService>(request: Int, outbound: Swift.Error?, for service: Service.Type) {
        handleCloseStream(request: request, inbound: .finished, for: service)
        
        if let outbound {
            handleClientError(id: service.id, request: request, error: outbound)
        } else {
            send(stream: PisteStreamFrame(id: service.id, request: request, action: .close))
        }
    }
    
    private func openStream(id: String, request: Int, send: @escaping () -> Void) async throws {
        return try await withCheckedThrowingContinuation { [self] continuation in
            let continuation = SafeThrowingContinuation(continuation)
            queue.sync {
                openStreamContinuations[id, default: [:]][request] = continuation
            }
            
            send()
            
            Task {
                try await Task.sleep(for: .seconds(Self.openStreamTimeout))
                if !continuation.isResumed {
                    continuation.resume(throwing: Error.timeout)
                }
            }
        }
    }
    
    enum Error: String, RPCError {
        case timeout
        case internalClientError
        case cancelled
        
        var code: String { rawValue }
        var message: String? { nil }
    }
}

private extension RPCService {
    static func decodePayload(data: Data, decoder: CodableCBORDecoder) throws -> PistePayloadFrame<Response> {
        try decoder.decode(PistePayloadFrame<Response>.self, from: data)
    }
}

protocol AnyInboundStream<Inbound> {
    associatedtype Inbound
    var onValueSubject: PassthroughSubject<Inbound, Never> { get }
    var onCloseSubject: PassthroughSubject<RPCStreamClosure, Never> { get }
}
extension RPCStream: AnyInboundStream {}
