import Foundation
import Hardpack

public struct EncodedPisteFrame: Codable, Sendable {
    public let function: PisteFunction
    public let version: VarInt
    @Nullable public var error: String?
    public let payload: Data
    
    public init(function: PisteFunction, version: VarInt, error: PisteError) {
        self.function = function
        self.version = version
        self.error = error.value
        self.payload = Data()
    }
    
    public init(function: PisteFunction, version: VarInt, payload: Data) {
        self.function = function
        self.version = version
        self.error = nil
        self.payload = payload
    }
}
