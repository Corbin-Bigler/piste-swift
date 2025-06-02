//
//  NewPiste.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/1/25.
//

import Combine
import Foundation
import Logger
import SwiftCBOR

public enum NewRPCOutboundStreamCompletion<Payload: Sendable>: Sendable {
    case external(RPCError)
    case `internal`(Swift.Error)
    case completed(Payload)
}
public enum NewRPCInboundStreamClosure: Sendable {
    case external(RPCError)
    case `internal`(Swift.Error)
    case completed
}

public protocol RPCClientStream {
    func open() async throws
}
public protocol NewRPCInboundStream {
    associatedtype Inbound: Sendable
    associatedtype Outbound: Sendable

    var onValue: AnyPublisher<Inbound, Never> { get }
    var onClose: AnyPublisher<NewRPCInboundStreamClosure, Never> { get }
    
    func finish(_ outbound: Outbound)
    func close(_ reason: RPCError)
}
public protocol NewRPCOutboundStream {
    associatedtype Outbound: Sendable
    associatedtype Inbound: Sendable

    var onComplete: AnyPublisher<NewRPCOutboundStreamCompletion<Inbound>, Never> { get }

    func send(_ outbound: Outbound)
    func close(_ reason: RPCError)
}
public protocol NewRPCChannelStream<Outbound, Inbound>: NewRPCInboundStream & NewRPCOutboundStream {}
public struct NewRPCStream<Outbound: Sendable, Inbound: Sendable>: RPCClientStream, NewRPCInboundStream, NewRPCOutboundStream {
    private let _onValue: (AnyPublisher<Inbound, Never>)?
    public var onValue: AnyPublisher<Inbound, Never> { _onValue! }
    private let _onClose: (AnyPublisher<NewRPCInboundStreamClosure, Never>)?
    public var onClose: AnyPublisher<NewRPCInboundStreamClosure, Never> { _onClose! }
    private let _onComplete: (AnyPublisher<NewRPCOutboundStreamCompletion<Inbound>, Never>)?
    public var onComplete: AnyPublisher<NewRPCOutboundStreamCompletion<Inbound>, Never> { _onComplete! }

    private let sendCallback: ((Outbound) -> Void)?
    private let openCallback: () async throws -> Void
    private let closeCallback: (RPCError) -> Void
    
    init(
        onValue: AnyPublisher<Inbound, Never>,
        onClose: AnyPublisher<NewRPCInboundStreamClosure, Never>,
        sendCallback: @escaping (Outbound) -> Void,
        openCallback: @escaping () async throws -> Void,
        closeCallback: @escaping (RPCError) -> Void
    ) {
        self._onValue = onValue
        self._onClose = onClose
        self._onComplete = nil
        self.sendCallback = sendCallback
        self.openCallback = openCallback
        self.closeCallback = closeCallback
    }
    init(
        onComplete: AnyPublisher<NewRPCOutboundStreamCompletion<Inbound>, Never>,
        sendCallback: @escaping (Outbound) -> Void,
        openCallback: @escaping () async throws -> Void,
        closeCallback: @escaping (RPCError) -> Void
    ) {
        self._onValue = nil
        self._onClose = nil
        self._onComplete = onComplete
        self.sendCallback = sendCallback
        self.openCallback = openCallback
        self.closeCallback = closeCallback
    }

    public func finish(_ outbound: Outbound) {
        sendCallback?(outbound)
    }
    public func send(_ outbound: Outbound) {
        sendCallback?(outbound)
    }
    public func open() async throws {
        try await openCallback()
    }
    public func close(_ reason: RPCError) {
        closeCallback(reason)
    }
}

actor NewPisteClient {
    private let logger: Logger
    private let _onData = PassthroughSubject<Data, Never>()
    public var onData: AnyPublisher<Data, Never> { _onData.eraseToAnyPublisher() }
    
    public init(logger: Logger = Logger.shared) {
        self.logger = logger
    }
    
    private var maximumPacketSize: Int = 1400
    public func setMaximumPacketSize(_ value: Int) {
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
        }
    }
    
    public func handle(data: Data) {
        
    }
    
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
    
    private func streamFramePackets<Service: RPCService>(action: PisteStreamAction, request: UInt64, for service: Service.Type) throws -> [Data] {
        return try encodableFramePackets(frameType: .stream, data: NewPisteStreamFrame(action: action), request: request, for: service)
    }
    private func errorFramePackets<Service: RPCService>(code: String, message: String, request: UInt64, for service: Service.Type) throws -> [Data] {
        return try encodableFramePackets(frameType: .payload, data: NewPisteErrorFrame(code: code, message: message), request: request, for: service)
    }
    private func payloadFramePackets<Service: RPCService>(payload: Service.Response, request: UInt64, for service: Service.Type) throws -> [Data] {
        return try encodableFramePackets(frameType: .payload, data: payload, request: request, for: service)
    }
    private func encodableFramePackets<Service: RPCService>(frameType: PisteFrameType, data: Encodable, request: UInt64, for service: Service.Type) throws -> [Data] {
        let encodedRequest = encodeULEB128(request)
        let encodedServiceId = Data(service.id.utf8)
        let encodedServiceIdCount = encodeULEB128(UInt64(encodedServiceId.count))
        let encodedData = try CodableCBOREncoder().encode(data)

        var identityHeader = Data()
        identityHeader.append(contentsOf: encodedRequest)
        identityHeader.append(contentsOf: encodedServiceIdCount)
        identityHeader.append(contentsOf: encodedServiceId)

        if identityHeader.count + 1 >= maximumPacketSize {
            throw NewPisteClientError.maximumPacketSizeTooSmall
        }
        
        let dataChunkSize = maximumPacketSize - (identityHeader.count + 1)
        let chunks = encodedData.chunked(into: dataChunkSize)
        
        var packets: [Data] = []
        for index in chunks.indices {
            let packetId = Data([index == chunks.count - 1 ? frameType.finalPacketId : frameType.continuationPacketId])
            packets.append(identityHeader + packetId + chunks[index])
        }
        
        return packets
    }
    
    private func encodeULEB128(_ value: UInt64) -> Data {
        var result: [UInt8] = []
        var value = value

        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            result.append(byte)
        } while value != 0

        return Data(result)
    }
    
    func decodeULEB128(_ data: Data, index: Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var currentIndex = index

        while currentIndex < data.count {
            let byte = data[currentIndex]
            let value = UInt64(byte & 0x7F)
            result |= value << shift

            if (byte & 0x80) == 0 {
                return result
            }

            shift += 7
            currentIndex += 1

            if shift >= 64 {
                return nil
            }
        }

        return nil
    }
}

enum NewPisteClientError: Swift.Error {
    case maximumPacketSizeTooSmall
}

struct NewPisteStreamFrame: Codable, Sendable {
    let action: PisteStreamAction
}

struct NewPisteErrorFrame: Codable, Sendable, RPCError {
    let code: String
    let message: String?
}

enum PisteFrame<Payload: Sendable> {
    case payload(Payload)
    case stream(NewPisteStreamFrame)
    case error(NewPisteErrorFrame)
}

enum PisteFrameType {
    case payload
    case stream
    case error
    
    var continuationPacketId: UInt8 {
        switch self {
        case .payload: return 128
        case .stream: return 129
        case .error: return 130
        }
    }
    
    var finalPacketId: UInt8 {
        switch self {
        case .payload: return 0
        case .stream: return 1
        case .error: return 2
        }
    }
}

private extension UInt64 {
    var uleb128: Data {
        var result: [UInt8] = []
        var value = self

        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 {
                byte |= 0x80
            }
            result.append(byte)
        } while value != 0

        return Data(result)
    }
}
private extension Data {
    func chunked(into size: Int) -> [Data] {
        var chunks: [Data] = []
        var offset = 0
        
        while offset < self.count {
            let chunkSize = Swift.min(size, self.count - offset)
            let chunk = self.subdata(in: offset..<offset + chunkSize)
            chunks.append(chunk)
            offset += chunkSize
        }
        
        return chunks
    }
    func decodeULEB128(at index: Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var currentIndex = index

        while currentIndex < self.count {
            let byte = self[currentIndex]
            let value = UInt64(byte & 0x7F)
            result |= value << shift

            if (byte & 0x80) == 0 {
                return result
            }

            shift += 7
            currentIndex += 1

            if shift >= 64 {
                return nil
            }
        }

        return nil
    }
}
