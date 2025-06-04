//
//  UInt64.swift
//  piste-swift
//
//  Created by Corbin Bigler on 6/4/25.
//

import Foundation

extension UInt64 {
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
