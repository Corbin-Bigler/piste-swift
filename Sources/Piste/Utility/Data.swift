//
//  Data.swift
//  piste-swift
//
//  Created by Corbin Bigler on 4/27/25.
//

import Foundation

extension Data {
    var hexString: String {
        self.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
