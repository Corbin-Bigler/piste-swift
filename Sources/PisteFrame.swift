//
//  PisteFrame.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

import Foundation

public enum PisteFrame: Equatable {
    case requestCall(id: PisteId, payload: Data)
    case requestDownload(id: PisteId, payload: Data)
    case openUpload(id: PisteId)
    case openStream(id: PisteId)
    case open
    case close
    case payload(_ payload: Data)
    case error(_ error: PisteError)
    case supportedServicesRequest
    case supportedServicesResponse(services: [PisteSupportedService])
    
    var type: PisteFrameType {
        switch self {
        case .requestCall: return .requestCall
        case .requestDownload: return .requestDownload
        case .openUpload: return .openUpload
        case .openStream: return .openStream
        case .open: return .open
        case .close: return .close
        case .payload: return .payload
        case .error: return .error
        case .supportedServicesRequest: return .supportedServicesRequest
        case .supportedServicesResponse: return .supportedServicesResponse
        }
    }
    
    var data: Data {
        var data = Data([type.rawValue])
        
        func appendInteger<T: FixedWidthInteger>(_ value: T) {
            data.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init))
        }
        
        switch self {
        case .requestCall(let id, let payload),
             .requestDownload(let id, let payload):
            appendInteger(id)
            data.append(payload)
            
        case .openUpload(let id),
             .openStream(let id):
            appendInteger(id)
            
        case .error(let error):
            appendInteger(error.rawValue)
            
        case .payload(let payload):
            data.append(payload)
            
        case .supportedServicesResponse(let services):
            appendInteger(UInt32(services.count))
            for service in services {
                appendInteger(service.id)
                data.append(UInt8(service.type.rawValue))
            }
            
        case .open, .close, .supportedServicesRequest:
            break
        }
        return data
    }
    
    public init?(data: Data) {
        var cursor = data.startIndex
        
        func read<T: FixedWidthInteger>(_ type: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard cursor + size <= data.endIndex else { return nil }
            let value = data[cursor ..< cursor + size]
                .enumerated()
                .reduce(T(0)) { (result, element) in
                    let (i, byte) = element
                    return result | (T(byte) << (8 * i))
                }
            cursor += size
            return value
        }
        
        guard let rawType = read(UInt8.self),
              let type = PisteFrameType(rawValue: rawType) else { return nil }
        
        switch type {
        case .requestCall:
            guard let id = read(PisteId.self) else { return nil }
            self = .requestCall(id: id, payload: data[cursor...])
            
        case .requestDownload:
            guard let id = read(PisteId.self) else { return nil }
            self = .requestDownload(id: id, payload: data[cursor...])
            
        case .openUpload:
            guard let id = read(PisteId.self) else { return nil }
            self = .openUpload(id: id)
            
        case .openStream:
            guard let id = read(PisteId.self) else { return nil }
            self = .openStream(id: id)
            
        case .open:
            self = .open
            
        case .close:
            self = .close
            
        case .payload:
            self = .payload(data[cursor...])
            
        case .error:
            guard let raw = read(UInt16.self),
                  let error = PisteError(rawValue: raw) else { return nil }
            self = .error(error)
            
        case .supportedServicesRequest:
            self = .supportedServicesRequest
            
        case .supportedServicesResponse:
            guard let count = read(UInt32.self) else { return nil }
            var services: [PisteSupportedService] = []
            for _ in 0..<count {
                guard let id = read(UInt32.self),
                      let typeRaw = read(UInt8.self),
                      let serviceType = PisteServiceType(rawValue: typeRaw) else { return nil }
                services.append(PisteSupportedService(id: id, type: serviceType))
            }
            self = .supportedServicesResponse(services: services)
        }
    }
}
