//
//  Data.swift
//  server
//
//  Created by Corbin Bigler on 3/9/25.
//

import Foundation

extension Data {
    var hexString: String {
        return self.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
