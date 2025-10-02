//
//  UploadPisteService.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

public protocol UploadPisteService: PisteService {}
extension UploadPisteService {
    public nonisolated static var type: PisteServiceType { .upload }
}
