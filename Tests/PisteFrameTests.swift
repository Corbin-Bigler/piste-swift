//
//  PisteFrameTests.swift
//  Piste
//
//  Created by Corbin Bigler on 10/2/25.
//

import Testing
import Foundation
@testable import Piste

final class PisteFrameTests {
    
    private func roundTrip(_ frame: PisteFrame) -> PisteFrame {
        let encoded = frame.data
        let decoded = PisteFrame(data: encoded)
        #expect(decoded != nil, "Decoding returned nil for \(frame)")
        return decoded!
    }
    
    @Test func testRequestCall() {
        let frame = PisteFrame.requestCall(id: 1234, payload: Data([1, 2, 3]))
        let decoded = roundTrip(frame)
        
        if case let .requestCall(id, payload) = decoded {
            #expect(id == 1234)
            #expect(payload == Data([1, 2, 3]))
        } else {
            #expect(Bool(false), "Decoded frame is not requestCall")
        }
    }
    
    @Test func testRequestDownload() {
        let frame = PisteFrame.requestDownload(id: 5678, payload: Data([9, 8, 7, 6]))
        let decoded = roundTrip(frame)
        
        if case let .requestDownload(id, payload) = decoded {
            #expect(id == 5678)
            #expect(payload == Data([9, 8, 7, 6]))
        } else {
            #expect(Bool(false), "Decoded frame is not requestDownload")
        }
    }
    
    @Test func testOpenUpload() {
        let frame = PisteFrame.openUpload(id: 42)
        let decoded = roundTrip(frame)
        #expect(frame == decoded)
    }
    
    @Test func testOpenStream() {
        let frame = PisteFrame.openStream(id: 99)
        let decoded = roundTrip(frame)
        #expect(frame == decoded)
    }
    
    @Test func testOpen() {
        let frame = PisteFrame.open
        let decoded = roundTrip(frame)
        #expect(frame == decoded)
    }
    
    @Test func testClose() {
        let frame = PisteFrame.close
        let decoded = roundTrip(frame)
        #expect(frame == decoded)
    }
    
    @Test func testPayload() {
        let frame = PisteFrame.payload("hello".data(using: .utf8)!)
        let decoded = roundTrip(frame)
        
        if case let .payload(payload) = decoded {
            #expect(payload == "hello".data(using: .utf8)!)
        } else {
            #expect(Bool(false), "Decoded frame is not payload")
        }
    }
    
    @Test func testError() {
        let frame = PisteFrame.error(.internalServerError)
        let decoded = roundTrip(frame)
        #expect(frame == decoded)
    }
    
    @Test func testSupportedServicesRequest() {
        let frame = PisteFrame.supportedServicesRequest
        let decoded = roundTrip(frame)
        #expect(frame == decoded)
    }
    
    @Test func testSupportedServicesResponse() {
        let services = [
            PisteSupportedService(id: 1, type: .call),
            PisteSupportedService(id: 2, type: .stream)
        ]
        let frame = PisteFrame.supportedServicesResponse(services: services)
        let decoded = roundTrip(frame)
        
        if case let .supportedServicesResponse(decodedServices) = decoded {
            #expect(decodedServices == services)
        } else {
            #expect(Bool(false), "Decoded frame is not supportedServicesResponse")
        }
    }
}
