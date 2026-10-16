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
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import NIOHTTP1
import Testing
@testable import PackageRegistry

@Suite("Registry HTTP Exchange") struct RegistryHTTPExchangeTests {
    @Test func encodesTheRequestLineHeadersAndBody() throws {
        let exchange = try Exchange(
            request: HTTPClientRequest(
                method: .post,
                url: URL(string: "https://registry.example.com/mona/LinkedList?version=1.0.0")!,
                headers: ["Accept": "application/json", "X-Trace": "abc"],
                body: Data("hello".utf8)
            )
        )

        let wire = try exchange.drainOutbound()

        #expect(wire.hasPrefix("POST /mona/LinkedList?version=1.0.0 HTTP/1.1\r\n"))
        #expect(wire.contains("Host: registry.example.com\r\n"))
        #expect(wire.contains("Accept: application/json\r\n"))
        #expect(wire.contains("X-Trace: abc\r\n"))
        #expect(wire.contains("Content-Length: 5\r\n"))
        #expect(wire.hasSuffix("\r\n\r\nhello"))
    }

    @Test func encodesARootPathForAnEmptyPath() throws {
        let exchange = try Exchange(
            request: HTTPClientRequest(method: .get, url: URL(string: "https://registry.example.com")!)
        )

        let wire = try exchange.drainOutbound()

        #expect(wire.hasPrefix("GET / HTTP/1.1\r\n"))
        #expect(!wire.contains("Content-Length"))
    }

    @Test func keepsANonDefaultPortInTheHostHeader() throws {
        let exchange = try Exchange(
            request: HTTPClientRequest(method: .get, url: URL(string: "https://registry.example.com:8443/availability")!)
        )

        #expect(try exchange.drainOutbound().contains("Host: registry.example.com:8443\r\n"))
    }

    @Test func stripsBracketsFromAnIPv6HostButKeepsThemInTheHostHeader() throws {
        let target = try RequestTarget(url: URL(string: "https://[::1]:8443/availability")!)

        #expect(target.host == "::1")
        #expect(target.hostHeader == "[::1]:8443")
    }

    @Test func keepsAnIPv6HostHeaderBracketedOnTheDefaultPort() throws {
        let target = try RequestTarget(url: URL(string: "https://[::1]/availability")!)

        #expect(target.host == "::1")
        #expect(target.hostHeader == "[::1]")
    }

    @Test func framesABodilessPostWithAZeroContentLength() throws {
        let exchange = try Exchange(
            request: HTTPClientRequest(method: .post, url: URL(string: "https://registry.example.com/login")!)
        )

        let wire = try exchange.drainOutbound()

        #expect(wire.contains("Content-Length: 0\r\n"))
        #expect(!wire.lowercased().contains("transfer-encoding"))
    }

    @Test func leavesABodilessGetWithoutAContentLength() throws {
        let exchange = try Exchange(
            request: HTTPClientRequest(method: .get, url: URL(string: "https://registry.example.com/mona")!)
        )

        let wire = try exchange.drainOutbound()

        #expect(!wire.contains("Content-Length"))
        #expect(!wire.lowercased().contains("transfer-encoding"))
    }

    @Test func collectsAResponseWithAContentLengthBody() throws {
        let exchange = try Exchange(
            request: HTTPClientRequest(method: .get, url: URL(string: "https://registry.example.com/mona")!)
        )

        try exchange.receive(
            """
            HTTP/1.1 200 OK\r
            Content-Type: application/json\r
            Content-Length: 11\r
            \r
            {"ok":true}
            """
        )

        let response = try exchange.response()
        #expect(response.statusCode == 200)
        #expect(response.statusText == "OK")
        #expect(response.headers.get("Content-Type") == ["application/json"])
        #expect(response.body == Data(#"{"ok":true}"#.utf8))
    }

    @Test func collectsAChunkedResponse() throws {
        let exchange = try Exchange(
            request: HTTPClientRequest(method: .get, url: URL(string: "https://registry.example.com/mona")!)
        )

        try exchange.receive(
            """
            HTTP/1.1 200 OK\r
            Transfer-Encoding: chunked\r
            \r
            5\r
            hello\r
            6\r
             world\r
            0\r
            \r

            """
        )

        let response = try exchange.response()
        #expect(response.statusCode == 200)
        #expect(response.body == Data("hello world".utf8))
    }

    @Test func withholdsTheBodyUntilTheServerSendsContinue() throws {
        let exchange = try Exchange(request: Self.publishRequest)

        let head = try exchange.drainOutbound()
        #expect(head.contains("Expect: 100-continue\r\n"))
        #expect(!head.contains("archive"))

        try exchange.receive("HTTP/1.1 100 Continue\r\n\r\n")
        #expect(try exchange.drainOutbound() == "archive")

        try exchange.receive("HTTP/1.1 201 Created\r\nContent-Length: 0\r\n\r\n")
        #expect(try exchange.response().statusCode == 201)
    }

    @Test func doesNotWaitForeverWhenTheServerRejectsTheExpectation() throws {
        let exchange = try Exchange(request: Self.publishRequest)
        _ = try exchange.drainOutbound()

        try exchange.receive("HTTP/1.1 417 Expectation Failed\r\nContent-Length: 0\r\n\r\n")

        #expect(try exchange.response().statusCode == 417)
        #expect(try exchange.drainOutbound() == "")
    }

    @Test func sendsTheBodyWhenTheContinueDeadlinePasses() throws {
        let exchange = try Exchange(request: Self.publishRequest)
        _ = try exchange.drainOutbound()

        exchange.channel.embeddedEventLoop.advanceTime(by: RegistryHTTPExchangeHandler.continueTimeout)

        #expect(try exchange.drainOutbound() == "archive")
    }

    @Test func reportsProgressAsBodyBytesArrive() throws {
        let progress = ProgressRecorder()
        let exchange = try Exchange(
            request: HTTPClientRequest(method: .get, url: URL(string: "https://registry.example.com/mona")!),
            progress: progress.handler
        )

        try exchange.receive("HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello")
        try exchange.receive(" world")

        #expect(try exchange.response().body == Data("hello world".utf8))
        #expect(progress.calls == [Call(received: 0, total: 11), Call(received: 5, total: 11), Call(received: 11, total: 11)])
    }

    @Test func abortsWhenTheProgressHandlerThrows() throws {
        let exchange = try Exchange(
            request: HTTPClientRequest(method: .get, url: URL(string: "https://registry.example.com/mona")!),
            progress: { received, _ in
                guard received == 0 else { throw StubError.tooLarge }
                return
            }
        )

        try exchange.receive("HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello")

        #expect(throws: StubError.tooLarge) { try exchange.response() }
        #expect(exchange.channel.isActive == false)
    }

    @Test func writesADownloadToTheDestination() throws {
        let fileSystem = InMemoryFileSystem()
        let destination = AbsolutePath("/downloads/archive.zip")
        let progress = ProgressRecorder()
        let exchange = try Exchange(
            request: HTTPClientRequest(
                kind: .download(fileSystem: fileSystem, destination: destination),
                url: URL(string: "https://registry.example.com/mona/LinkedList/1.0.0.zip")!
            ),
            progress: progress.handler
        )

        try exchange.receive("HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello")
        try exchange.receive(" world")

        let response = try exchange.response()
        #expect(response.statusCode == 200)
        #expect(response.body == nil)
        #expect(try fileSystem.readFileContents(destination) as Data == Data("hello world".utf8))
        #expect(progress.calls.last == Call(received: 11, total: 11))
    }

    @Test func keepsAFailedDownloadResponseInMemory() throws {
        let fileSystem = InMemoryFileSystem()
        let destination = AbsolutePath("/downloads/archive.zip")
        let exchange = try Exchange(
            request: HTTPClientRequest(
                kind: .download(fileSystem: fileSystem, destination: destination),
                url: URL(string: "https://registry.example.com/mona/LinkedList/1.0.0.zip")!
            )
        )

        try exchange.receive("HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nno such p")

        let response = try exchange.response()
        #expect(response.statusCode == 404)
        #expect(response.body == Data("no such p".utf8))
        #expect(fileSystem.exists(destination) == false)
    }

    @Test func failsWhenTheTimeoutExpires() throws {
        let exchange = try Exchange(
            request: HTTPClientRequest(method: .get, url: URL(string: "https://registry.example.com/mona")!),
            timeout: .milliseconds(500)
        )

        exchange.channel.embeddedEventLoop.advanceTime(by: .milliseconds(500))

        #expect {
            try exchange.response()
        } throws: { error in
            guard case RegistryHTTPTransportError.timedOut(let url) = error else { return false }
            return url == "https://registry.example.com/mona"
        }
        #expect(exchange.channel.isActive == false)
    }

    @Test func failsWhenTheServerGoesSilentWithoutASuppliedTimeout() throws {
        let exchange = try Exchange(
            request: HTTPClientRequest(method: .get, url: URL(string: "https://registry.example.com/mona")!)
        )

        exchange.channel.embeddedEventLoop.advanceTime(by: RegistryHTTPExchangeHandler.stallTimeout)

        #expect {
            try exchange.response()
        } throws: { error in
            guard case RegistryHTTPTransportError.timedOut(let url) = error else { return false }
            return url == "https://registry.example.com/mona"
        }
    }

    @Test func keepsASlowDownloadAliveWhileBytesKeepArriving() throws {
        let exchange = try Exchange(
            request: HTTPClientRequest(method: .get, url: URL(string: "https://registry.example.com/mona")!)
        )
        let halfOfTheStallTimeout = TimeAmount.nanoseconds(RegistryHTTPExchangeHandler.stallTimeout.nanoseconds / 2)

        try exchange.receive("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
        for _ in 0 ..< 10 {
            exchange.channel.embeddedEventLoop.advanceTime(by: halfOfTheStallTimeout)
            try exchange.receive("4\r\ndata\r\n")
        }

        #expect(throws: StubError.exchangeStillPending) { try exchange.response() }

        try exchange.receive("0\r\n\r\n")
        #expect(try exchange.response().statusCode == 200)
    }

    @Test func failsWhenTheConnectionClosesBeforeAnyResponse() throws {
        let exchange = try Exchange(
            request: HTTPClientRequest(method: .get, url: URL(string: "https://registry.example.com/mona")!)
        )

        try exchange.channel.close().wait()

        #expect {
            try exchange.response()
        } throws: { error in
            guard case RegistryHTTPTransportError.connectionClosed = error else { return false }
            return true
        }
    }

    @Test func failsWhenTheResponseBodyIsTruncated() throws {
        let exchange = try Exchange(
            request: HTTPClientRequest(method: .get, url: URL(string: "https://registry.example.com/mona")!)
        )

        try exchange.receive("HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\nhello")
        try? exchange.channel.close().wait()

        #expect(throws: (any Error).self) { try exchange.response() }
    }

    private static let publishRequest = HTTPClientRequest(
        method: .put,
        url: URL(string: "https://registry.example.com/mona/LinkedList/1.0.0")!,
        headers: ["Expect": "100-continue"],
        body: Data("archive".utf8)
    )
}

private enum StubError: Error, Equatable {
    case tooLarge
    case exchangeStillPending
}

private struct Call: Equatable {
    let received: Int64
    let total: Int64?
}

private final class ProgressRecorder: Sendable {
    private let recorded = NIOLockedValueBox<[Call]>([])

    var calls: [Call] {
        self.recorded.withLockedValue { $0 }
    }

    var handler: HTTPClient.ProgressHandler {
        { received, total in
            self.recorded.withLockedValue { $0.append(Call(received: received, total: total)) }
        }
    }
}

private struct Exchange {
    let channel: EmbeddedChannel
    private let outcome: NIOLockedValueBox<Result<HTTPClientResponse, Error>?>

    init(
        request: HTTPClientRequest,
        timeout: TimeAmount? = nil,
        progress: HTTPClient.ProgressHandler? = nil
    ) throws {
        let channel = EmbeddedChannel()
        let promise = channel.eventLoop.makePromise(of: HTTPClientResponse.self)
        let outcome = NIOLockedValueBox<Result<HTTPClientResponse, Error>?>(nil)
        promise.futureResult.whenComplete { result in
            outcome.withLockedValue { $0 = result }
        }

        try channel.connect(to: SocketAddress(ipAddress: "127.0.0.1", port: 443)).wait()
        try channel.pipeline.syncOperations.addRegistryHTTPHandlers(
            RegistryHTTPExchangeHandler(
                request: request,
                timeout: timeout,
                progress: progress,
                promise: promise
            )
        )

        self.channel = channel
        self.outcome = outcome
    }

    func drainOutbound() throws -> String {
        var wire = ""
        while let buffer = try self.channel.readOutbound(as: ByteBuffer.self) {
            wire += String(buffer: buffer)
        }
        return wire
    }

    func receive(_ bytes: String) throws {
        try self.channel.writeInbound(ByteBuffer(string: bytes))
    }

    func response() throws -> HTTPClientResponse {
        guard let outcome = self.outcome.withLockedValue({ $0 }) else {
            throw StubError.exchangeStillPending
        }
        return try outcome.get()
    }
}
