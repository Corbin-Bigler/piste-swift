//
//  PisteChannelServer.swift
//  piste-swift
//
//  Created by Corbin Bigler on 4/27/25.
//

import Combine
import Foundation
import Logger
import SwiftProtobuf

public class PisteChannelServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "piste.channelServer")
    private let logger: Logger
    
    private var onResponse: (Data) -> () = { _ in }
    
    private var streams: [String : Any] = [:]
    private var cancellables: [String : AnyCancellable] = [:]

    private(set) var callHandlers: [String : any CallPisteHandler] = [:]
    private(set) var uploadHandlers: [String : any UploadPisteHandler] = [:]
    private(set) var downloadHandlers: [String : any DownloadPisteHandler] = [:]
    private(set) var streamingHandlers: [String : any StreamingPisteHandler] = [:]
    var handlers: [String : any PisteHandler] {
        var allHandlers: [String: any PisteHandler] = [:]
        for (key, handler) in callHandlers { allHandlers[key] = handler }
        for (key, handler) in uploadHandlers { allHandlers[key] = handler }
        for (key, handler) in downloadHandlers { allHandlers[key] = handler }
        for (key, handler) in streamingHandlers { allHandlers[key] = handler }
        return allHandlers
    }

    public init(logger: Logger = Logger.shared) {
        self.logger = logger
        
        register(PisteGetServicesHandler(server: self))
        register(PisteGetInformationHandler(server: self))
    }
    
    public func onResponse(_ callback: @escaping (Data) -> ()) {
        queue.sync { self.onResponse = callback }
    }
    
    private func close(path: String) throws {
        var frame = PisteCloseFrame()
        frame.path = path
        onResponse(try frame.serializedBytes())
    }
    private func error(_ error: Error) {
        let error = error as? PisteError ?? PisteServerError.internalServerError
        do {
            var frame = PisteErrorFrame()
            frame.error = error.id
            if let message = error.message { frame.message = message }
            onResponse(try frame.serializedData())
        } catch {
            logger.fault("Unable to encode error: \(error)")
        }
    }
    private func error<Handler: PisteHandler>(_ error: Error, for handler: Handler) {
        let error = error as? PisteError ?? PisteServerError.internalServerError
        do {
            var frame = PisteErrorFrame()
            frame.path = handler.path
            frame.error = error.id
            if let message = error.message { frame.message = message }
            onResponse(try frame.serializedData())
        } catch {
            logger.fault("Unable to encode error: \(error)")
        }
    }
    private func response<Handler: PisteHandler>(_ message: Message, for handler: Handler) {
        do {
            var frame = PisteFrame()
            frame.path = handler.path
            frame.payload = try Google_Protobuf_Any(message: message)
            onResponse(try frame.serializedData())
        } catch {
            logger.fault("Unable to encode response: \(error)")
            self.error(PisteServerError.internalServerError, for: handler)
        }
    }
    private func handle<Handler: CallPisteHandler>(payload: Google_Protobuf_Any, for handler: Handler) {
        let request: Handler.Service.Request
        do {
            request = try .init(unpackingAny: payload)
        } catch {
            logger.error(error)
            self.error(PisteServerError.badPayload, for: handler)
            return
        }
        
        Task {
            do {
                let response = try await handler.handle(request: request)
                self.response(response, for: handler)
            } catch {
                self.error(error, for: handler)
            }
        }
    }
    private func handle<Handler: DownloadPisteHandler>(payload: Google_Protobuf_Any, for handler: Handler) {
        let request: Handler.Service.Request
        do {
            request = try .init(unpackingAny: payload)
        } catch {
            logger.error(error)
            self.error(PisteServerError.badPayload, for: handler)
            return
        }
        
        let subject = handler.handle(request: request)
        streams[handler.path] = subject
        cancellables[handler.path] = subject
            .sink(
                receiveCompletion: {
                    switch $0 {
                    case .finished: try? self.close(path: handler.path)
                    case .failure(let error): self.error(error, for: handler)
                    }
                },
                receiveValue: { data in
                    self.response(data, for: handler)
                }
            )
    }
    private func closeStream<Handler: PisteHandler>(error: PisteError?, for handler: Handler) {
        if let stream = streams[handler.path] as? PassthroughSubject<Handler.Service.Response, Error> {
            if let error {
                stream.send(completion: .failure(error))
            } else {
                stream.send(completion: .finished)
            }
        }
        streams.removeValue(forKey: handler.path)
        cancellables.removeValue(forKey: handler.path)
    }

    public func handle(_ data: Data) {
        if let frame = try? PisteFrame(serializedBytes: data), frame.hasPayload, frame.unknownFields.data.isEmpty {
            if let callHandler = callHandlers[frame.path] {
                handle(payload: frame.payload, for: callHandler)
            } else if let downloadHandler = downloadHandlers[frame.path] {
                handle(payload: frame.payload, for: downloadHandler)
            } else {
                self.error(PisteServerError.unsupportedService(service: frame.path))
            }
        } else if let error = try? PisteErrorFrame(serializedBytes: data), error.unknownFields.data.isEmpty {
            if let handler = handlers[error.path] {
                closeStream(error: PisteServerError.clientError(id: error.error, message: error.message), for: handler)
            }
        } else if let close = try? PisteCloseFrame(serializedBytes: data), close.unknownFields.data.isEmpty {
            if let handler = handlers[close.path] {
                closeStream(error: nil, for: handler)
            }
        } else {
            self.error(PisteServerError.badFrame)
            return
        }
    }
    
    public func register<Handler: CallPisteHandler>(_ handler: Handler) {
        queue.sync {
            precondition(callHandlers[handler.path] == nil, "Attempting to register \(handler.path) more than once")
            callHandlers[handler.path] = handler
        }
    }
    public func register<Handler: UploadPisteHandler>(_ handler: Handler) {
        queue.sync {
            precondition(uploadHandlers[handler.path] == nil, "Attempting to register \(handler.path) more than once")
            uploadHandlers[handler.path] = handler
        }
    }
    public func register<Handler: DownloadPisteHandler>(_ handler: Handler) {
        queue.sync {
            precondition(downloadHandlers[handler.path] == nil, "Attempting to register \(handler.path) more than once")
            downloadHandlers[handler.path] = handler
        }
    }
    public func register<Handler: StreamingPisteHandler>(_ handler: Handler) {
        queue.sync {
            precondition(streamingHandlers[handler.path] == nil, "Attempting to register \(handler.path) more than once")
            streamingHandlers[handler.path] = handler
        }
    }
}
