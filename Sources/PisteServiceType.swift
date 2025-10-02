//
//  PisteServiceType.swift
//  Piste
//
//  Created by Corbin Bigler on 10/2/25.
//

public enum PisteServiceType: UInt8, Sendable {
    case call = 0x00
    case download = 0x01
    case upload = 0x02
    case stream = 0x03
}
