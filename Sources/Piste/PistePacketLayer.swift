//
//  PistePacketLayer.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/4/25.
//

@preconcurrency import Combine
import Foundation
import Logger
import SwiftCBOR

final actor PistePacketLayer {
    typealias FrameData = (serviceId: String, requestId: UInt64, type: PisteFrameType, frame: Data)
    
    private var maximumPacketSize: Int
    public func setMaximumPacketSize(_ value: Int) {
        self.maximumPacketSize = value
    }
    
    private let _onFrame = PassthroughSubject<FrameData, Never>()
    public var onFrame: AsyncStream<FrameData> {
        AsyncStream { continuation in
            let cancellable = self._onFrame.sink { continuation.yield($0) }
            continuation.onTermination = { continuation in
                cancellable.cancel()
            }
        }
    }

    init(maximumPacketSize: Int) {
        self.maximumPacketSize = maximumPacketSize
    }

    func makeStreamPackets(action: PisteStreamAction, requestId: UInt64, serviceId: String) throws -> [Data] {
        return try encode(frameType: .stream, data: PisteStreamFrame(action: action), requestId: requestId, serviceId: serviceId)
    }

    func makeErrorPackets(code: String, message: String?, requestId: UInt64, serviceId: String) throws -> [Data] {
        return try encode(frameType: .payload, data: PisteErrorFrame(code: code, message: message), requestId: requestId, serviceId: serviceId)
    }

    func makePayloadPackets(payload: Encodable, requestId: UInt64, serviceId: String) throws -> [Data] {
        return try encode(frameType: .payload, data: payload, requestId: requestId, serviceId: serviceId)
    }

    private func encode(frameType: PisteFrameType, data: Encodable, requestId: UInt64, serviceId: String) throws -> [Data] {
        let encodedRequest = requestId.uleb128
        let encodedServiceId = Data(serviceId.utf8)
        let encodedServiceIdCount = UInt64(encodedServiceId.count).uleb128
        let encodedData = try CodableCBOREncoder().encode(data)

        var identityHeader = Data()
        identityHeader.append(contentsOf: encodedRequest)
        identityHeader.append(contentsOf: encodedServiceIdCount)
        identityHeader.append(contentsOf: encodedServiceId)

        if identityHeader.count + 1 >= maximumPacketSize {
            throw PisteClientError.maximumPacketSizeTooSmall
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

    var streams: [String : [Int : Data]] = [:]
    func handle(data: Data) {
        var cursor = 0

        guard let (request, requestLength) = data.decodeULEB128(at: cursor) else { return }
        cursor += requestLength

        guard let (serviceIdLength, serviceIdLengthSize) = data.decodeULEB128(at: cursor) else { return }
        cursor += serviceIdLengthSize

        guard cursor + Int(serviceIdLength) <= data.count else { return }

        let serviceIdData = data[cursor..<cursor + Int(serviceIdLength)]
        guard let serviceId = String(data: serviceIdData, encoding: .utf8) else { return }
        cursor += Int(serviceIdLength)

        guard cursor < data.count else { return }
        let packetId = data[cursor]
        cursor += 1

        let payload = data[cursor...]

        let streamKey = "\(request):\(serviceId)"
        var partials = streams[streamKey] ?? [:]
        let nextIndex = (partials.keys.max() ?? -1) + 1
        partials[nextIndex] = payload
        streams[streamKey] = partials

        if isFinalPacketId(packetId) {
            let completePayload = partials
                .sorted(by: { $0.key < $1.key })
                .map(\.value)
                .reduce(Data(), +)

            if let frameType = PisteFrameType.fromPacketId(packetId) {
                _onFrame.send((serviceId: serviceId, requestId: request, type: frameType, frame: completePayload))
            }

            streams.removeValue(forKey: streamKey)
        }
    }

    private func isFinalPacketId(_ byte: UInt8) -> Bool {
        return byte == PisteFrameType.payload.finalPacketId || byte == PisteFrameType.stream.finalPacketId || byte == PisteFrameType.error.finalPacketId
    }
}
