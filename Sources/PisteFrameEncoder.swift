//
//  SudokuBattlesFrameEncoder.swift
//  sudoku-battles-server
//
//  Created by Corbin Bigler on 3/5/25.
//

import NIO
import Hardpack

final class PisteFrameEncoder: MessageToByteEncoder, Sendable {
    public typealias OutboundIn = EncodedPisteFrame
    public typealias OutboundOut = ByteBuffer

    func encode(data: EncodedPisteFrame, out: inout ByteBuffer) throws {
        let encoder = HardpackEncoder()
        
        let encodedData = try encoder.encode(data)
        out.writeBytes(encodedData)
    }
}
