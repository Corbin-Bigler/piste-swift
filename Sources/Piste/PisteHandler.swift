//
//  PisteHandler.swift
//  piste-swift
//
//  Created by Corbin Bigler on 4/27/25.
//

import Combine

public protocol PisteHandler: Sendable {
    associatedtype Service: PisteService
    var title: String { get }
    var description: String { get }
}
extension PisteHandler {
    var path: String { Service.path }
}

public protocol CallPisteHandler: PisteHandler where Service: CallPisteService {
    func handle(request: Service.Request) async throws -> Service.Response
}
public protocol UploadPisteHandler: PisteHandler where Service: UploadPisteService {
    func handle(request: PassthroughSubject<Service.Request, Error>) async throws -> Service.Response
}
public protocol DownloadPisteHandler: PisteHandler where Service: DownloadPisteService {
    func handle(request: Service.Request) -> PassthroughSubject<Service.Response, Error>
}
public protocol StreamingPisteHandler: PisteHandler where Service: StreamingPisteService {
    func handle(request: PassthroughSubject<Service.Request, Error>) -> PassthroughSubject<Service.Response, Error>
}
