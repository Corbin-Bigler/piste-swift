//
//  PisteError.swift
//  Piste
//
//  Created by Corbin Bigler on 9/18/25.
//

public enum PisteError: UInt16, Error {
    case internalServerError = 0x00
    case decodingFailed = 0x01
    case unsupportedService = 0x02
    case channelClosed = 0x03
    case unsupportedFrameType = 0x04
}
