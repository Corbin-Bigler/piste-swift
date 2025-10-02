//
//  PisteInternalError.swift
//  Piste
//
//  Created by Corbin Bigler on 9/26/25.
//


enum PisteInternalError: Error {
    case cancelled
    case channelClosed
    case unsupportedService
    case incorrectServiceType
}
