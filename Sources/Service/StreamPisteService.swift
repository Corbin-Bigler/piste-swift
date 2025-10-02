//
//  StreamPisteService.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

public protocol StreamPisteService: PisteService {}
extension StreamPisteService {
    public nonisolated static var type: PisteServiceType { .stream }
}
