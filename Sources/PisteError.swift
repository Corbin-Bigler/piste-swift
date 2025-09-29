//
//  PisteError.swift
//  Piste
//
//  Created by Corbin Bigler on 9/18/25.
//

public enum PisteError: UInt16, Error {
    case unhandledError = 0x00
    case decodingFailed = 0x01
    case invalidAction = 0x02
    case invalidFrame = 0x03
    case invalidFrameType = 0x04
    case unsupportedService = 0x05
    case channelClosed = 0x06
}
