//
//  PisteService.swift
//  piste-swift
//
//  Created by Corbin Bigler on 4/27/25.
//

import SwiftProtobuf

public protocol PisteService {
    static var path: String { get }
    associatedtype Request: Codable
    associatedtype Response: Codable
}
public protocol CallPisteService: PisteService {}
public protocol UploadPisteService: PisteService {}
public protocol DownloadPisteService: PisteService {}
public protocol StreamingPisteService: PisteService {}
