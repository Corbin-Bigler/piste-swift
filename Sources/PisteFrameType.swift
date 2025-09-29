//
//  PisteFrameType.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

enum PisteFrameType: UInt8 {
    case request = 0x00
    case open = 0x01
    case opened = 0x02
    case close = 0x03
    case error = 0x04
    case payload = 0x05
}
