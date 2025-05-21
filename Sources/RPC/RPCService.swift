//
//  RPCService.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/7/25.
//

public protocol RPCService {
    static var id: String { get }
    associatedtype Request: Codable, Sendable
    associatedtype Response: Codable, Sendable
}
public protocol RPCCallService: RPCService {}
public protocol RPCUploadService: RPCService {}
public protocol RPCDownloadService: RPCService {}
public protocol RPCChannelService: RPCService {}
