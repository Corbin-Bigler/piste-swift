//
//  Data.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/4/25.
//

import Foundation

extension Data {
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
    func decodeULEB128(at offset: Int) -> (value: UInt64, length: Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var cursor = offset

        while cursor < self.count {
            let byte = self[cursor]
            result |= UInt64(byte & 0x7F) << shift
            cursor += 1

            if (byte & 0x80) == 0 {
                return (result, cursor - offset)
            }

            shift += 7
            if shift >= 64 {
                return nil
            }
        }

        return nil
    }
}
