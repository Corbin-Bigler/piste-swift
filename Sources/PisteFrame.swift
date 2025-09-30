//
//  PisteFrame.swift
//  Piste
//
//  Created by Corbin Bigler on 9/17/25.
//

import Foundation

public enum PisteFrame {
    case request(id: PisteId, payload: Data)
    case open(id: PisteId)
    case opened
    case close
    case error(_ error: PisteError)
    case payload(_ payload: Data)
        
    var type: PisteFrameType {
        switch self {
        case .request(_, _): .request
        case .open(_): .open
        case .opened: .opened
        case .close: .close
        case .error(_): .error
        case .payload(_): .payload
        }
    }
    
    var data: Data {
        var data = Data([type.rawValue])
        
        switch self {
        case .request(let id, let payload):
            data.append(contentsOf: withUnsafeBytes(of: id.littleEndian, Array.init))
            data.append(payload)
        case .error(let error):
            data.append(contentsOf: withUnsafeBytes(of: error.rawValue.littleEndian, Array.init))
        case .open(let id):
            data.append(contentsOf: withUnsafeBytes(of: id.littleEndian, Array.init))
        case .payload(let payload):
            data.append(payload)
        case .opened, .close: break
        }
        return data
    }
    
    public nonisolated init?(data: Data) {
        var cursor = data.startIndex
        
        func read<T: FixedWidthInteger>(_ type: T.Type) -> T? {
            let byteCount = MemoryLayout<T>.size
            guard cursor + byteCount <= data.endIndex else { return nil }
            
            let value = data[cursor ..< cursor + byteCount]
                .enumerated()
                .reduce(T(0)) { (result, element) in
                    let (i, byte) = element
                    return result | (T(byte) << (8 * i))
                }
            
            cursor += byteCount
            return value
        }
        
        guard let type = read(PisteFrameType.RawValue.self).flatMap(PisteFrameType.init) else {
            return nil
        }
        
        switch type {
        case .request:
            guard let id = read(PisteId.self) else { return nil }
            self = .request(id: id, payload: data[cursor...])
        case .error:
            guard let error = read(PisteError.RawValue.self).flatMap(PisteError.init) else {
                return nil
            }
            self = .error(error)
        case .open:
            guard let id = read(PisteId.self) else { return nil }
            self = .open(id: id)
        case .payload:
            self = .payload(data[cursor...])
        case .opened:
            self = .opened
        case .close:
            self = .close
        }
    }
}
