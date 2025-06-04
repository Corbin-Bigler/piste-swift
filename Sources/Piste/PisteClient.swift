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
    private let packetLayer: PistePacketLayer
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
        await packetLayer.setMaximumPacketSize(value)
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
        self.packetLayer = PistePacketLayer(maximumPacketSize: maximumPacketSize)
        self.logger = logger
        
        Task {
            for await data in await packetLayer.onFrame {
                await handleFrame(data)
            }
        }
    }
    
    private func handleFrame(_ data: PistePacketLayer.FrameData) {
        if let subject = requestSubjects[data.serviceId]?[data.requestId] {
            
        }
    }
    
    public func call<Service: RPCCallService>(_ request: Service.Request, for service: Service.Type) async throws -> Service.Response {
        let requestId = getRequestId(for: service)
        return try await withCheckedThrowingContinuation { continuation in
            let requestSubject = createRequestSubject(requestId: requestId, for: service)
            let cancellable = requestSubject.sink { [weak self] frame in
                guard let self else { return }
                Task {
                    if case .payload(let payload) = frame {
                        continuation.resume(returning: payload)
                        await self.removeRequestCancellable(serviceId: service.id, requestId: requestId)
                    } else if case .error(let error) = frame {
                        continuation.resume(throwing: error)
                        await self.removeRequestCancellable(serviceId: service.id, requestId: requestId)
                    }
                }
            }
            requestCancellables[service.id, default: [:]][requestId] = cancellable
            
            Task {
                do {
                    let packets = try await packetLayer.makePayloadPackets(payload: request, requestId: requestId, serviceId: service.id)
                    for packet in packets { _onData.send(packet) }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func handle(data: Data) async { await packetLayer.handle(data: data) }

    private var requestSubjects: [String: [UInt64: (subject: Any, service: any RPCService.Type)]] = [:]
    private func createRequestSubject<Service: RPCService>(requestId: UInt64, for service: Service.Type) -> PassthroughSubject<PisteFrame<Service.Response>, Never> {
        let subject = PassthroughSubject<PisteFrame<Service.Response>, Never>()
        requestSubjects[service.id, default: [:]][requestId] = (subject, service)
        return subject
    }

    private var requestIds: [String: UInt64] = [:]
    private func getRequestId<Service: RPCService>(for service: Service.Type) -> UInt64 {
        let requestId = requestIds[service.id, default: 0] + 1
        requestIds[service.id] = requestId
        return requestId
    }
}

enum PisteClientError: Swift.Error {
    case maximumPacketSizeTooSmall
}
