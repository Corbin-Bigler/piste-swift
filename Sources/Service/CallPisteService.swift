//
//  CallPisteService.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

public protocol CallPisteService: PisteService {}
extension CallPisteService {
    public nonisolated static var type: PisteServiceType { .call }
}
