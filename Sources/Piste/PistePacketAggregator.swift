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

final actor PistePacketAggregator {
    private let _onFrame = PassthroughSubject<PisteFrameData, Never>()
    public var onFrame: AsyncStream<PisteFrameData> {
        AsyncStream { continuation in
            let cancellable = _onFrame.sink { continuation.yield($0) }
            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
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

        let content = data[cursor...]

        let streamKey = "\(request):\(serviceId)"
        var partials = streams[streamKey] ?? [:]
        let nextIndex = (partials.keys.max() ?? -1) + 1
        partials[nextIndex] = content
        streams[streamKey] = partials

        if isFinalPacketId(packetId) {
            let completedPayload = partials
                .sorted(by: { $0.key < $1.key })
                .map(\.value)
                .reduce(Data(), +)

            if let frameType = PistePayloadType.fromPacketId(packetId) {
                _onFrame.send(.init(serviceId: serviceId, requestId: request, type: frameType, payload: completedPayload))
            }

            streams.removeValue(forKey: streamKey)
        }
    }

    private func isFinalPacketId(_ byte: UInt8) -> Bool {
        return byte == PistePayloadType.content.finalPacketId || byte == PistePayloadType.stream.finalPacketId || byte == PistePayloadType.error.finalPacketId
    }
}
