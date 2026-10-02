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
import Testing
@testable import PackageRegistry

@Suite("Registry HTTP Redirects") struct RegistryHTTPRedirectTests {
    @Test func returnsAResponseThatIsNotARedirect() async throws {
        let server = ScriptedServer([.okay(body: "payload")])

        let response = try await server.follower().execute(Self.get, progress: .none)

        #expect(response.statusCode == 200)
        #expect(server.requests.count == 1)
    }

    @Test(arguments: [301, 302, 303, 307, 308]) func followsEveryRedirectStatus(statusCode: Int) async throws {
        let server = ScriptedServer([
            .redirect(statusCode, to: "https://registry.example.com/moved"),
            .okay(body: "payload"),
        ])

        let response = try await server.follower().execute(Self.get, progress: .none)

        #expect(response.body == Data("payload".utf8))
        #expect(server.requests.map(\.url.absoluteString) == [
            "https://registry.example.com/mona",
            "https://registry.example.com/moved",
        ])
    }

    @Test func resolvesARelativeLocation() async throws {
        let server = ScriptedServer([.redirect(307, to: "/elsewhere?page=2"), .okay(body: "payload")])

        _ = try await server.follower().execute(Self.get, progress: .none)

        #expect(server.requests.last?.url.absoluteString == "https://registry.example.com/elsewhere?page=2")
    }

    @Test func returnsARedirectThatHasNoLocation() async throws {
        let server = ScriptedServer([HTTPClientResponse(statusCode: 308)])

        let response = try await server.follower().execute(Self.get, progress: .none)

        #expect(response.statusCode == 308)
        #expect(server.requests.count == 1)
    }

    @Test(arguments: [301, 302, 303]) func convertsARedirectedPostToAGet(statusCode: Int) async throws {
        let server = ScriptedServer([
            .redirect(statusCode, to: "https://registry.example.com/moved"),
            .okay(body: "payload"),
        ])

        _ = try await server.follower().execute(Self.post, progress: .none)

        #expect(server.requests.last?.method == .get)
        #expect(server.requests.last?.body == nil)
    }

    @Test(arguments: [307, 308]) func keepsTheMethodAndBodyOnATemporaryRedirect(statusCode: Int) async throws {
        let server = ScriptedServer([
            .redirect(statusCode, to: "https://registry.example.com/moved"),
            .okay(body: "payload"),
        ])

        _ = try await server.follower().execute(Self.post, progress: .none)

        #expect(server.requests.last?.method == .post)
        #expect(server.requests.last?.body == Data("archive".utf8))
    }

    @Test func convertsAPutToAGetOnSeeOther() async throws {
        let server = ScriptedServer([
            .redirect(303, to: "https://registry.example.com/moved"),
            .okay(body: "payload"),
        ])
        let put = HTTPClientRequest(
            method: .put,
            url: URL(string: "https://registry.example.com/mona")!,
            body: Data("archive".utf8)
        )

        _ = try await server.follower().execute(put, progress: .none)

        #expect(server.requests.last?.method == .get)
        #expect(server.requests.last?.body == nil)
    }

    @Test func stripsCredentialsOnACrossOriginHop() async throws {
        let server = ScriptedServer([
            .redirect(307, to: "https://downloads.example.com/archive.zip"),
            .okay(body: "payload"),
        ])

        _ = try await server.follower().execute(Self.authenticated, progress: .none)

        let redirected = try #require(server.requests.last)
        #expect(redirected.headers.get("Authorization").isEmpty)
        #expect(redirected.headers.get("Proxy-Authorization").isEmpty)
        #expect(redirected.headers.get("Cookie").isEmpty)
        #expect(redirected.headers.get("Accept") == ["application/json"])
    }

    @Test func stripsCredentialsWhenOnlyThePortChanges() async throws {
        let server = ScriptedServer([
            .redirect(307, to: "https://registry.example.com:8443/moved"),
            .okay(body: "payload"),
        ])

        _ = try await server.follower().execute(Self.authenticated, progress: .none)

        #expect(server.requests.last?.headers.get("Authorization").isEmpty == true)
    }

    @Test func reappliesCredentialsOnASameOriginHop() async throws {
        let server = ScriptedServer([
            .redirect(307, to: "https://registry.example.com/moved"),
            .okay(body: "payload"),
        ])

        _ = try await server.follower().execute(Self.authenticated, progress: .none)

        let redirected = try #require(server.requests.last)
        #expect(redirected.headers.get("Authorization") == ["Bearer refreshed"])
        #expect(redirected.headers.get("Cookie") == ["session=1"])
    }

    @Test func dropsTheAuthorizationHeaderWhenNoProviderIsConfigured() async throws {
        let server = ScriptedServer([
            .redirect(307, to: "https://registry.example.com/moved"),
            .okay(body: "payload"),
        ])
        let request = HTTPClientRequest(
            method: .get,
            url: URL(string: "https://registry.example.com/mona")!,
            headers: ["Authorization": "Bearer stale"]
        )

        _ = try await server.follower().execute(request, progress: .none)

        #expect(server.requests.last?.headers.get("Authorization").isEmpty == true)
    }

    @Test func failsWhenTheHopLimitIsExceeded() async throws {
        let server = ScriptedServer(
            (0 ... RegistryHTTPRedirectFollower.maximumHops)
                .map { .redirect(308, to: "https://registry.example.com/hop\($0)") }
        )

        await #expect {
            try await server.follower().execute(Self.get, progress: .none)
        } throws: { error in
            guard case RegistryHTTPTransportError.tooManyRedirects(let url) = error else { return false }
            return url == "https://registry.example.com/mona"
        }
        #expect(server.requests.count == RegistryHTTPRedirectFollower.maximumHops + 1)
    }

    @Test func followsUpToTheHopLimit() async throws {
        let server = ScriptedServer(
            (1 ... RegistryHTTPRedirectFollower.maximumHops)
                .map { .redirect(308, to: "https://registry.example.com/hop\($0)") } + [.okay(body: "payload")]
        )

        let response = try await server.follower().execute(Self.get, progress: .none)

        #expect(response.body == Data("payload".utf8))
        #expect(server.requests.count == RegistryHTTPRedirectFollower.maximumHops + 1)
    }

    private static let get = HTTPClientRequest(
        method: .get,
        url: URL(string: "https://registry.example.com/mona")!
    )

    private static let post = HTTPClientRequest(
        method: .post,
        url: URL(string: "https://registry.example.com/mona")!,
        body: Data("archive".utf8)
    )

    private static var authenticated: HTTPClientRequest {
        var options = HTTPClientRequest.Options()
        options.authorizationProvider = { _ in "Bearer refreshed" }
        return HTTPClientRequest(
            method: .get,
            url: URL(string: "https://registry.example.com/mona")!,
            headers: [
                "Accept": "application/json",
                "Authorization": "Bearer stale",
                "Proxy-Authorization": "Basic proxy",
                "Cookie": "session=1",
            ],
            options: options
        )
    }
}

extension HTTPClientResponse {
    fileprivate static func redirect(_ statusCode: Int, to location: String) -> HTTPClientResponse {
        HTTPClientResponse(statusCode: statusCode, headers: ["Location": location])
    }
}

private struct ScriptedServer: Sendable {
    private let scripted: NIOLockedValueBox<[HTTPClientResponse]>
    private let recorded = NIOLockedValueBox<[HTTPClientRequest]>([])

    init(_ responses: [HTTPClientResponse]) {
        self.scripted = NIOLockedValueBox(responses)
    }

    var requests: [HTTPClientRequest] {
        self.recorded.withLockedValue { $0 }
    }

    func follower() -> RegistryHTTPRedirectFollower {
        RegistryHTTPRedirectFollower { request, _ in
            self.recorded.withLockedValue { $0.append(request) }
            return self.scripted.withLockedValue { $0.isEmpty ? .okay(body: "unscripted") : $0.removeFirst() }
        }
    }
}
