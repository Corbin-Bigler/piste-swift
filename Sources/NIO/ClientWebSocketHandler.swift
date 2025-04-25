//
//  ClientWebSocketHandler.swift
//  test-client
//
//  Created by Corbin Bigler on 4/24/25.
//

import Foundation
import NIOCore
import NIOWebSocket
import SwiftCBOR
import Combine
import SwiftLogger

final class ClientWebSocketHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = WebSocketFrame
    typealias InboundOut = WebSocketFrame

    private let decoder = CodableCBORDecoder()

    private var client: PisteClient
    init(client: PisteClient) {
        self.client = client
    }
    
    private func handle<Service: TransientPisteService>(_ data: Data, headers: PisteFrameHeader, for service: Service.Type) {
        do {
            let clientbound = try decoder.decode(PisteFrame<Service.Clientbound>.self, from: data).payload
            guard let request = client.requests[headers.service]?[headers.version] else { return }
            try! request.resume(returning: clientbound)
        } catch {
            if let error = try? decoder.decode(PisteErrorFrame.self, from: data) {
                guard let request = client.requests[headers.service]?[headers.version] else { return }
                request.resume(throwing: PisteClientError.error(id: error.error, message: error.message))
            } else {
                Logger.fault(error)
            }
        }
    }
    private func handle<Service: PersistentPisteService>(_ data: Data, headers: PisteFrameHeader, for service: Service.Type) {
        do {
            let clientbound = try decoder.decode(PisteFrame<Service.Clientbound>.self, from: data).payload
            guard let subject = client.subjects[headers.service]?[headers.version] as? PassthroughSubject<PersistentServiceResponse<Service.Clientbound>, Never> else { return }
            subject.send(.response(clientbound))
        } catch {
            if let error = try? decoder.decode(PisteErrorFrame.self, from: data) {
                guard let subject = client.subjects[headers.service]?[headers.version] as? PassthroughSubject<PersistentServiceResponse<Service.Clientbound>, Never> else { return }
                subject.send(.error(id: error.error, message: error.message))
            } else {
                Logger.fault(error)
            }
        }
    }


    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)

        if frame.opcode == .binary {
            var buffer = frame.unmaskedData
            guard let data = buffer.readBytes(length: buffer.readableBytes).flatMap({ Data($0) }),
                  let headers = try? decoder.decode(PisteFrameHeader.self, from: data)
            else { return }
            
            if let transientService = client.requestServices[headers.service]?[headers.version] {
                handle(data, headers: headers, for: transientService)
            } else if let persistentServices = client.subjectServices[headers.service]?[headers.version] {
                handle(data, headers: headers, for: persistentServices)
            }
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Error: \(error)")
        context.close(promise: nil)
    }
}
