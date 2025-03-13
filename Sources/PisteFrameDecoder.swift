//
//  SudokuBattlesFrameDecoder.swift
//  sudoku-battles-server
//
//  Created by Corbin Bigler on 3/5/25.
//

import Foundation
import Hardpack
import NIO

final class PisteFrameDecoder: ByteToMessageDecoder, Sendable {
    private static let functionSize = MemoryLayout<PisteFunction>.size

    typealias InboundOut = EncodedPisteFrame

    func decode(context: NIOCore.ChannelHandlerContext, buffer: inout NIOCore.ByteBuffer) throws -> NIOCore.DecodingState {
        var index = buffer.readerIndex
        let lastIndex = max(0, buffer.readableBytes - 1)
        guard let functionLength = buffer.getVarInt(at: index) else {
            buffer.moveReaderIndex(to: lastIndex)
            return .needMoreData
        }
        index += functionLength.bytes.count
        guard let function = buffer.getString(at: index, length: Int(functionLength.value)) else {
            buffer.moveReaderIndex(to: lastIndex)
            return .needMoreData
        }
        index += Int(functionLength.value)
        guard let version = buffer.getVarInt(at: index) else {
            buffer.moveReaderIndex(to: lastIndex)
            return .needMoreData
        }
        index += version.bytes.count
        guard let errorByte = buffer.getBytes(at: index, length: 1)?.first else {
            buffer.moveReaderIndex(to: lastIndex)
            return .needMoreData
        }
        index += 1
        var error: PisteError? = nil
        if errorByte == 1 {
            guard let errorLength = buffer.getVarInt(at: index) else {
                buffer.moveReaderIndex(to: lastIndex)
                return .needMoreData
            }
            index += errorLength.bytes.count
            guard let errorValue = buffer.getString(at: index, length: Int(errorLength.value)) else {
                buffer.moveReaderIndex(to: lastIndex)
                return .needMoreData
            }
            index += Int(errorLength.value)
            error = PisteError(value: errorValue)
        }
        guard let length = buffer.getVarInt(at: index) else {
            buffer.moveReaderIndex(to: lastIndex)
            return .needMoreData
        }
        index += Int(length.bytes.count)

        guard buffer.readableBytes >= UInt64(index) + length.value,
            let data = buffer.getBytes(at: index, length: Int(length.value)).flatMap({ Data($0) })
        else {
            return .needMoreData
        }

        buffer.moveReaderIndex(to: lastIndex)
        let encodedFrame = error.flatMap { EncodedPisteFrame(function: function, version: version, error: $0) } ?? EncodedPisteFrame(function: function, version: version, payload: data)
        context.fireChannelRead(wrapInboundOut(encodedFrame))
        return .continue
    }
}

extension ByteBuffer {
    mutating func getVarInt(at index: Int) -> VarInt? {
        guard let bytes = getBytes(at: index, length: min(readableBytes - index, index + 10)) else { return nil }
        return VarInt(bytes: Data(bytes))
    }
}
