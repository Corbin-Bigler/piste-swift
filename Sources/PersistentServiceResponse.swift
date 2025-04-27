//
//  PersistentServiceResponse.swift
//  piste
//
//  Created by Corbin Bigler on 4/26/25.
//


public enum PersistentServiceResponse<Clientbound> {
    case response(Clientbound)
    case error(id: String, message: String?)
}
