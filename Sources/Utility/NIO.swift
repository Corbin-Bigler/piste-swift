//
//  BackPressureHandler.swift
//  SwiftNIOTutorial
//
//  Created by Corbin Bigler on 3/2/25.
//

import NIO
import NIOSSL

extension NIOSSLServerHandler: @unchecked @retroactive Sendable { }
extension BackPressureHandler: @unchecked @retroactive Sendable { }
extension ByteToMessageHandler: @retroactive @unchecked Sendable { }
extension MessageToByteHandler: @retroactive @unchecked Sendable { }
extension NIOSSLClientHandler: @retroactive @unchecked Sendable { }
extension ChannelHandlerContext: @retroactive @unchecked Sendable { }
