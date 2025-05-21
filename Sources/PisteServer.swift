//
//  PisteServer.swift
//  Lion Energy
//
//  Created by Corbin Bigler on 5/7/25.
//

class PisteServer: @unchecked Sendable {
    var handlers: [String : any PisteHandler] { fatalError() }
}
