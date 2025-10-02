//
//  PisteFrameType.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

enum PisteFrameType: UInt8 {
    case requestCall = 0x00
    case requestDownload = 0x01
    case openUpload = 0x02
    case openStream = 0x03
    case open = 0x04
    case close = 0x05
    case payload = 0x06
    case error = 0x07
    case supportedServicesRequest = 0x08
    case supportedServicesResponse = 0x09
}
