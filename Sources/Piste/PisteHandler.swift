//
//  PisteHandler.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/7/25.
//

import Combine

public protocol PisteHandler: Sendable, RPCHandler {
    var title: String { get }
    var description: String { get }
    var deprecated: Bool { get }
}

public protocol PisteCallHandler: PisteHandler, RPCCallHandler where Service: RPCCallService {}
public protocol PisteDownloadHandler: PisteHandler, RPCDownloadHandler where Service: RPCDownloadService {}
public protocol PisteUploadHandler: PisteHandler, RPCUploadHandler where Service: RPCUploadService {}
public protocol PisteChannelHandler: PisteHandler, RPCChannelHandler where Service: RPCChannelService {}

