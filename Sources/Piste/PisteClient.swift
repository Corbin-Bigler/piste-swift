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

final actor PisteClient {
    private let aggregator: PistePacketAggregator
    private let logger: Logger
    private let _onData = PassthroughSubject<Data, Never>()
    public var onData: AsyncStream<Data> {
        AsyncStream { continuation in
            let cancellable = self._onData.sink { continuation.yield($0) }
            continuation.onTermination = { continuation in
                cancellable.cancel()
            }
        }
    }

    private var maximumPacketSize: Int
    public func setMaximumPacketSize(_ value: Int) async {
        self.maximumPacketSize = value
    }
    private var openStreamTimeout: Duration = .seconds(5)
    public func setOpenStreamTimeout(_ timeout: Duration) {
        self.openStreamTimeout = timeout
    }
    private var callTimeout: Duration = .seconds(60)
    public func setCallTimeout(_ timeout: Duration) {
        self.callTimeout = timeout
    }
    
    private var requestCancellables: [String: [UInt64: AnyCancellable]] = [:]
    private func removeRequestCancellable(serviceId: String, requestId: UInt64) {
        requestCancellables[serviceId]?.removeValue(forKey: requestId)
    }
    
    init(maximumPacketSize: Int = 1400, logger: Logger = Logger.shared) {
        self.maximumPacketSize = maximumPacketSize
        self.aggregator = PistePacketAggregator()
        self.logger = logger
        
        Task {
            for await data in await aggregator.onFrame {
                await handleFrame(data)
            }
        }
    }
    
    private func handleFrame(_ data: PisteFrameData) {
        do {
            if let continuation = responseStreamContinations[data.serviceId]?[data.requestId], let service = responseStreamTypes[data.serviceId]?[data.requestId] {
                try service.yieldFrameData(data, continuation: continuation)
            }
        } catch {
            Logger.fault(error)
        }
    }

    public func call<Service: RPCCallService>(_ request: Service.Request, for service: Service.Type) async throws -> Service.Response {
        let requestId = getRequestId(for: service)
        return try await withCheckedThrowingContinuation { continuation in
            let stream = SignalableAsyncStream(
                getResponseStream(requestId: requestId, for: service),
                onStart: {
                    Task {
                        do {
                            try await self.send(.init(
                                serviceId: service.id,
                                requestId: requestId,
                                payload: .content(request)
                            ))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            )

            Task {
                for await frame in stream {
                    if case .content(let content) = frame {
                        continuation.resume(returning: content)
                    } else if case .error(let error) = frame {
                        continuation.resume(throwing: error)
                    }

                    self.removeResponseStream(serviceId: service.id, requestId: requestId)
                    break
                }
            }
        }
    }
    
    public func download<Service: RPCDownloadService>(_ request: Service.Request, for service: Service.Type) -> RPCClientDownloadStream<Service.Response> {
        let requestId = getRequestId(for: service)
        let responseStream = getResponseStream(requestId: requestId, for: service)
        let onComplete = Promise<RPCStreamCompletion>()
        
        return .init(
            onValue: .init { continuation in
                Task {
                    for await value in responseStream {
                        if case .content(let content) = value {
                            continuation.yield(content)
                        } else if case .error(let error) = value {
                            await onComplete.resume(.remote(error))
                        } else if case .stream(let stream) = value, stream.action == .close {
                            await onComplete.resume(.completed)
                        }
                    }
                }
            },
            onComplete: onComplete,
            closeHandler: { error in
                Task {
                    do {
                        try await self.send(.init(serviceId: service.id, requestId: requestId, payload: .error(.init(code: error.code, message: error.message))))
                    } catch {
                        Logger.fault(error)
                    }
                    await self.removeResponseStream(serviceId: service.id, requestId: requestId)
                }
            },
            openHandler: {
                let stream = SignalableAsyncStream(
                    responseStream,
                    onStart: {
                        Task {
                            try? await self.send(.init(serviceId: service.id, requestId: requestId, payload: .content(request)))
                        }
                    }
                )
                try await withCheckedThrowingContinuation { continuation in
                    Task {
                        for await value in stream {
                            if case .stream(let stream) = value {
                                if stream.action == .open {
                                    continuation.resume()
                                }
                            } else if case .error(let error) = value {
                                continuation.resume(throwing: error)
                            } else {
                                continue
                            }
                            await self.removeResponseStream(serviceId: service.id, requestId: requestId)
                        }
                    }
                }
            }
        )
    }

    public func handle(data: Data) async { await aggregator.handle(data: data) }

    private var responseStreamTypes: [String: [UInt64: any RPCService.Type]] = [:]
    private var responseStreamContinations: [String: [UInt64: Any]] = [:]
    private var responseStreams: [String: [UInt64: Any]] = [:]
    private func getResponseStream<Service: RPCService>(requestId: UInt64, for service: Service.Type) -> AsyncStream<PistePayload<Service.Response>> {
        if let stream = responseStreams[service.id]?[requestId] as? AsyncStream<PistePayload<Service.Response>> {
            return stream
        }
        let stream = AsyncStream<PistePayload<Service.Response>> { continuation in
            responseStreamTypes[service.id, default: [:]][requestId] = service
            responseStreamContinations[service.id, default: [:]][requestId] = continuation
        }
        responseStreams[service.id, default: [:]][requestId] = stream
        return stream
    }
    private func removeResponseStream(serviceId: String, requestId: UInt64) {
        responseStreamTypes[serviceId]?.removeValue(forKey: requestId)
        responseStreamContinations[serviceId]?.removeValue(forKey: requestId)
        responseStreams[serviceId]?.removeValue(forKey: requestId)
    }
    
    
//    private var requestSubjects: [String: [UInt64: (subject: Any, service: any RPCService.Type)]] = [:]
//    private func createRequestSubject<Service: RPCService>(requestId: UInt64, for service: Service.Type) -> PassthroughSubject<PistePayload<Service.Response>, Never> {
//        let subject = PassthroughSubject<PistePayload<Service.Response>, Never>()
//        requestSubjects[service.id, default: [:]][requestId] = (subject, service)
//        return subject
//    }

    private var requestIds: [String: UInt64] = [:]
    private func getRequestId<Service: RPCService>(for service: Service.Type) -> UInt64 {
        let requestId = requestIds[service.id, default: 0] + 1
        requestIds[service.id] = requestId
        return requestId
    }
    
    private func send(_ frame: PisteFrame) throws {
        for packet in try frame.packets(maxSize: maximumPacketSize) {
            _onData.send(packet)
        }
    }
}

enum PisteClientError: Swift.Error {
    case internalError
}

private extension RPCService {
    static func yieldFrameData(_ frame: PisteFrameData, continuation: Any) throws {
        guard let continuation = continuation as? AsyncStream<PistePayload<Response>>.Continuation else {
            throw PisteClientError.internalError
        }
        
        let decoder = CodableCBORDecoder()
        switch frame.type {
        case .content: continuation.yield(.content(try decoder.decode(Response.self, from: frame.payload)))
        case .stream: continuation.yield(.stream(try decoder.decode(PisteStreamPayload.self, from: frame.payload)))
        case .error: continuation.yield(.error(try decoder.decode(PisteErrorPayload.self, from: frame.payload)))
        }
    }
}
