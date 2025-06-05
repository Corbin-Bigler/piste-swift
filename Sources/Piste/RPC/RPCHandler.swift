//
//  RPCService.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/7/25.
//

public protocol RPCHandler: Sendable {
    associatedtype Service: RPCService
}
extension RPCHandler {
    var id: String { Service.id }
}

public protocol RPCCallHandler: RPCHandler where Service: RPCCallService {
    func handle(request: Service.Request) async throws -> Service.Response
}
public protocol RPCDownloadHandler: RPCHandler where Service: RPCDownloadService {
    func handle(request: Service.Request, stream: RPCServerDownloadStream<Service.Response>) throws
}
public protocol RPCUploadHandler: RPCHandler where Service: RPCUploadService {
    func handle(stream: RPCServerUploadStream<Service.Request, Service.Response>) async throws -> Service.Response
}
public protocol RPCChannelHandler: RPCHandler where Service: RPCChannelService {
    func handle(stream: RPCServerChannelStream<Service.Request, Service.Response>) throws
}

