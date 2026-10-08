//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Basics
import Foundation
import NIOCore
import NIOHTTP1

final class RegistryHTTPExchangeHandler: ChannelInboundHandler {
    static let continueTimeout: TimeAmount = .seconds(1)
    static let stallTimeout: TimeAmount = .seconds(60)

    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart

    private let request: HTTPClientRequest
    private let timeout: TimeAmount?
    private let progress: HTTPClient.ProgressHandler?

    private var promise: EventLoopPromise<HTTPClientResponse>?
    // SwiftPM sends the zip file of the package in the body of the request
    // This is a large body, so the client sends the headers first:
    // If the server can process the package, it response with a 100-continue status code
    // The body, stored in `withheldBody` is then sent to the server
    private var withheldBody: Data?
    private var responseHead: HTTPResponseHead?
    private var responseBody: ByteBuffer?
    private var bytesReceived: Int64 = 0
    private var expectedBytes: Int64?
    // Throws an error when the request times out
    private var timeoutTask: Scheduled<Void>?
    // If the server stops sending bytes, it waits `stallTimeout` seconds then throws
    private var stallTask: Scheduled<Void>?
    // If 100 Continue is not received within `continueTimeout` seconds, the request body is sent anyway
    private var continueTask: Scheduled<Void>?

    init(
        request: HTTPClientRequest,
        timeout: TimeAmount?,
        progress: HTTPClient.ProgressHandler?,
        promise: EventLoopPromise<HTTPClientResponse>
    ) {
        self.request = request
        self.timeout = timeout
        self.progress = progress
        self.promise = promise
    }

    func handlerAdded(context: ChannelHandlerContext) {
        guard context.channel.isActive else { return }
        self.send(context: context)
    }

    func channelActive(context: ChannelHandlerContext) {
        self.send(context: context)
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.rearmStallTimeout(context: context)
        switch self.unwrapInboundIn(data) {
        case .head(let head):
            self.receive(head: head, context: context)
        case .body(let buffer):
            self.receive(body: buffer, context: context)
        case .end:
            self.finish(context: context)
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.fail(RegistryHTTPTransportError.connectionClosed, context: context)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.fail(error, context: context)
    }

    private func send(context: ChannelHandlerContext) {
        guard self.promise != nil else { return }

        let head: HTTPRequestHead
        do {
            head = try RegistryHTTPRequestEncoding.head(for: self.request)
        } catch {
            return self.fail(error, context: context)
        }

        self.scheduleTimeout(context: context)
        self.rearmStallTimeout(context: context)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)

        guard let body = self.request.body else {
            context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            return
        }

        // Include the body if the `Expect: 100-continue` header is missing
        // Else, store the body in `withheldBody` until the server responds
        guard Self.expectsContinue(head) else {
            self.write(body: body, context: context)
            return
        }

        self.withheldBody = body
        self.continueTask = context.eventLoop.scheduleTask(in: Self.continueTimeout) { [weak self] in
            self?.releaseWithheldBody(context: context)
        }
        context.flush()
    }

    private func releaseWithheldBody(context: ChannelHandlerContext) {
        self.continueTask?.cancel()
        self.continueTask = nil
        guard let body = self.withheldBody else { return }
        self.withheldBody = nil
        self.write(body: body, context: context)
    }

    private func write(body: Data, context: ChannelHandlerContext) {
        var buffer = context.channel.allocator.buffer(capacity: body.count)
        buffer.writeBytes(body)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func receive(head: HTTPResponseHead, context: ChannelHandlerContext) {
        guard !Self.isInformational(head) else {
            // The server can handle the body: send it over
            guard head.status == .continue else { return }
            return self.releaseWithheldBody(context: context)
        }

        self.continueTask?.cancel()
        self.continueTask = nil
        self.withheldBody = nil
        self.responseHead = head
        self.expectedBytes = head.headers.first(name: "Content-Length").flatMap(Int64.init)

        self.report(received: 0, context: context)
    }

    private func receive(body buffer: ByteBuffer, context: ChannelHandlerContext) {
        self.bytesReceived += Int64(buffer.readableBytes)
        if self.responseBody == nil {
            self.responseBody = buffer
        } else {
            var incoming = buffer
            self.responseBody?.writeBuffer(&incoming)
        }

        self.report(received: self.bytesReceived, context: context)
    }

    private func report(received: Int64, context: ChannelHandlerContext) {
        guard let progress = self.progress, self.promise != nil else { return }
        do {
            try progress(received, self.expectedBytes)
        } catch {
            self.fail(error, context: context)
        }
    }

    private func finish(context: ChannelHandlerContext) {
        guard let promise = self.promise, let head = self.responseHead else { return }

        let body = self.responseBody.map { Data($0.readableBytesView) }
        let response: HTTPClientResponse
        do {
            response = try self.makeResponse(head: head, body: body)
        } catch {
            return self.fail(error, context: context)
        }

        self.promise = nil
        self.cancelScheduledTasks()
        promise.succeed(response)
        context.close(promise: nil)
    }

    private func makeResponse(head: HTTPResponseHead, body: Data?) throws -> HTTPClientResponse {
        let headers = HTTPClientHeaders(head.headers.map { .init(name: $0.name, value: $0.value) })
        let response = HTTPClientResponse(
            statusCode: Int(head.status.code),
            statusText: head.status.reasonPhrase,
            headers: headers,
            body: body
        )

        guard case .download(let fileSystem, let destination) = self.request.kind, (200 ..< 300)
            .contains(response.statusCode)
        else {
            return response
        }

        try fileSystem.createDirectory(destination.parentDirectory, recursive: true)
        try fileSystem.writeFileContents(destination, data: body ?? Data())

        return HTTPClientResponse(
            statusCode: response.statusCode,
            statusText: response.statusText,
            headers: response.headers,
            body: nil
        )
    }

    private func fail(_ error: Error, context: ChannelHandlerContext) {
        guard let promise = self.promise else { return }
        self.promise = nil
        self.cancelScheduledTasks()
        promise.fail(error)
        context.close(promise: nil)
    }

    private func scheduleTimeout(context: ChannelHandlerContext) {
        guard let timeout = self.timeout else { return }
        let url = self.request.url.absoluteString
        self.timeoutTask = context.eventLoop.scheduleTask(in: timeout) { [weak self] in
            self?.fail(RegistryHTTPTransportError.timedOut(url), context: context)
        }
    }

    private func rearmStallTimeout(context: ChannelHandlerContext) {
        guard self.promise != nil else { return }
        let url = self.request.url.absoluteString
        self.stallTask?.cancel()
        self.stallTask = context.eventLoop.scheduleTask(in: Self.stallTimeout) { [weak self] in
            self?.fail(RegistryHTTPTransportError.timedOut(url), context: context)
        }
    }

    private func cancelScheduledTasks() {
        self.timeoutTask?.cancel()
        self.timeoutTask = nil
        self.stallTask?.cancel()
        self.stallTask = nil
        self.continueTask?.cancel()
        self.continueTask = nil
    }

    private static func expectsContinue(_ head: HTTPRequestHead) -> Bool {
        head.headers[canonicalForm: "Expect"].contains { $0.lowercased() == "100-continue" }
    }

    private static func isInformational(_ head: HTTPResponseHead) -> Bool {
        (100 ..< 200).contains(Int(head.status.code)) && head.status != .switchingProtocols
    }
}

extension ChannelPipeline.SynchronousOperations {
    func addRegistryHTTPHandlers(_ handler: RegistryHTTPExchangeHandler) throws {
        try self.addHandler(HTTPRequestEncoder())
        try self.addHandler(
            ByteToMessageHandler(
                HTTPResponseDecoder(leftOverBytesStrategy: .dropBytes, informationalResponseStrategy: .forward)
            )
        )
        try self.addHandler(handler)
    }
}
