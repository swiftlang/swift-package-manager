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
import NIOPosix
import NIOSSL

/// A custom HTTP Client that supports mTLS
/// `AsyncHTTPClient` was not used because it bloats SPM's dependency graph
/// If a lot of logic is being copied from `AsyncHTTPClient`, use it instead of this struct
struct RegistryNIOHTTPClient: Sendable {
    static let connectTimeout: TimeAmount = .seconds(10)

    private let eventLoopGroup: any EventLoopGroup

    init(eventLoopGroup: any EventLoopGroup = NIOSingletons.posixEventLoopGroup) {
        self.eventLoopGroup = eventLoopGroup
    }

    func execute(
        _ request: HTTPClientRequest,
        tlsConfiguration: TLSConfiguration,
        progress: HTTPClient.ProgressHandler?
    ) async throws -> HTTPClientResponse {
        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
        let deadline = request.options.timeout
            .flatMap { $0.nanoseconds() }
            .map { NIODeadline.now() + .nanoseconds(Int64($0)) }

        return try await self.exchange(request, sslContext: sslContext, deadline: deadline, progress: progress)
    }

    private func exchange(
        _ request: HTTPClientRequest,
        sslContext: NIOSSLContext,
        deadline: NIODeadline?,
        progress: HTTPClient.ProgressHandler?
    ) async throws -> HTTPClientResponse {
        let target = try RequestTarget(url: request.url)
        let remaining = Self.remaining(until: deadline)
        let serverHostname = Self.serverHostname(for: target)

        let channel = try await ClientBootstrap(group: self.eventLoopGroup)
            .connectTimeout(remaining ?? Self.connectTimeout)
            .channelInitializer { channel in
                do {
                    let handler = try NIOSSLClientHandler(context: sslContext, serverHostname: serverHostname)
                    try channel.pipeline.syncOperations.addHandler(handler)
                    return channel.eventLoop.makeSucceededVoidFuture()
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
            .connect(host: target.host, port: target.port)
            .get()

        defer { channel.close(promise: nil) }

        let promise = channel.eventLoop.makePromise(of: HTTPClientResponse.self)
        do {
            try await channel.eventLoop.submit {
                try channel.pipeline.syncOperations.addRegistryHTTPHandlers(
                    RegistryHTTPExchangeHandler(
                        request: request,
                        timeout: Self.remaining(until: deadline),
                        progress: progress,
                        promise: promise
                    )
                )
            }.get()
        } catch {
            promise.fail(error)
        }

        return try await promise.futureResult.get()
    }

    private static func remaining(until deadline: NIODeadline?) -> TimeAmount? {
        guard let deadline else { return .none }
        return max(deadline - .now(), .nanoseconds(0))
    }

    private static func serverHostname(for target: RequestTarget) -> String? {
        guard (try? SocketAddress(ipAddress: target.host, port: target.port)) == nil else { return .none }
        return target.host
    }
}
