//
//  PisteFrameData.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/4/25.
//

import Foundation

struct PisteFrameData {
    let serviceId: String
    let requestId: UInt64
    let type: PistePayloadType
    let payload: Data
    
    init(serviceId: String, requestId: UInt64, type: PistePayloadType, payload: Data) {
        self.serviceId = serviceId
        self.requestId = requestId
        self.type = type
        self.payload = payload
    }
    
    func packets(maxSize: Int) throws -> [Data] {
        let encodedRequest = requestId.uleb128
        let encodedServiceId = Data(serviceId.utf8)
        let encodedServiceIdCount = UInt64(encodedServiceId.count).uleb128

        var identityHeader = Data()
        identityHeader.append(contentsOf: encodedRequest)
        identityHeader.append(contentsOf: encodedServiceIdCount)
        identityHeader.append(contentsOf: encodedServiceId)

        if identityHeader.count + 1 >= maxSize {
            throw PisteFrameError.maximumPacketSizeTooSmall
        }
        
        let dataChunkSize = maxSize - (identityHeader.count + 1)
        let chunks = payload.chunked(into: dataChunkSize)
        
        var packets: [Data] = []
        for index in chunks.indices {
            let packetId = Data([index == chunks.count - 1 ? type.finalPacketId : type.continuationPacketId])
            packets.append(identityHeader + packetId + chunks[index])
        }
        
        return packets
    }
}

enum PisteFrameError: Error {
    case maximumPacketSizeTooSmall
}

