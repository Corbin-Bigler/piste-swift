//
//  RPCChannelStream.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/20/25.
//

public protocol RPCChannelStream<Outbound, Inbound>: RPCInboundStream & RPCOutboundStream {}
