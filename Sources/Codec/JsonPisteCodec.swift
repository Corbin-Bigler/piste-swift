//
//  JsonPisteCodec.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

import Foundation

public struct JsonPisteCodec: PisteCodec {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
        
    public func encode<T>(_ value: T) throws -> Data {
        guard let encodable = value as? Encodable else {
            if T.self == Void.self {
                return Data()
            }
            assertionFailure("Type is not Encodable: \(T.self)")
            throw JsonPisteCodecError.typeNotEncodable(T.self)
        }
        
        return try encoder.encode(encodable)
    }
    
    public func decode<T>(_ data: Data) throws -> T {
        guard let type = T.self as? Decodable.Type else {
            if T.self == Void.self {
                return () as! T
            }
            assertionFailure("Type is not Decodable: \(T.self)")
            throw JsonPisteCodecError.typeNotDecodable(T.self)
        }
        
        let decoded = try decoder.decode(type, from: data)
        guard let value = decoded as? T else {
            assertionFailure("Type is not Decodable: \(T.self)")
            throw JsonPisteCodecError.typeNotDecodable(T.self)
        }

        return value
    }
}

enum JsonPisteCodecError<T>: Error {
    case typeNotEncodable(T.Type)
    case typeNotDecodable(T.Type)
}
