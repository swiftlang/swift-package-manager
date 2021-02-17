/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import XCTest

import Basics
@testable import PackageCollections
import PackageModel
import SourceControl
import SPMTestSupport
import TSCBasic
import TSCUtility

class GitHubPackageMetadataProviderTests: XCTestCase {
    func testBaseURL() throws {
        let apiURL = URL(string: "https://api.github.com/repos/octocat/Hello-World")
        let provider = GitHubPackageMetadataProvider()

        do {
            let sshURLRetVal = provider.apiURL("git@github.com:octocat/Hello-World.git")
            XCTAssertEqual(apiURL, sshURLRetVal)
        }

        do {
            let httpsURLRetVal = provider.apiURL("https://github.com/octocat/Hello-World.git")
            XCTAssertEqual(apiURL, httpsURLRetVal)
        }

        do {
            let httpsURLRetVal = provider.apiURL("https://github.com/octocat/Hello-World")
            XCTAssertEqual(apiURL, httpsURLRetVal)
        }

        XCTAssertNil(provider.apiURL("bad/Hello-World.git"))
    }

    func testGood() throws {
        let repoURL = "https://github.com/octocat/Hello-World.git"
        let apiURL = URL(string: "https://api.github.com/repos/octocat/Hello-World")!
        let releasesURL = URL(string: "https://api.github.com/repos/octocat/Hello-World/releases?per_page=20")!

        fixture(name: "Collections") { directoryPath in
            let handler: HTTPClient.Handler = { request, _, completion in
                switch (request.method, request.url) {
                case (.get, apiURL):
                    let path = directoryPath.appending(components: "GitHub", "metadata.json")
                    let data = Data(try! localFileSystem.readFileContents(path).contents)
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                              body: data)))
                case (.get, releasesURL):
                    let path = directoryPath.appending(components: "GitHub", "releases.json")
                    let data = Data(try! localFileSystem.readFileContents(path).contents)
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                              body: data)))
                case (.get, apiURL.appendingPathComponent("contributors")):
                    let path = directoryPath.appending(components: "GitHub", "contributors.json")
                    let data = Data(try! localFileSystem.readFileContents(path).contents)
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                              body: data)))
                case (.get, apiURL.appendingPathComponent("readme")):
                    let path = directoryPath.appending(components: "GitHub", "readme.json")
                    let data = Data(try! localFileSystem.readFileContents(path).contents)
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                              body: data)))
                case (.get, apiURL.appendingPathComponent("license")):
                    let path = directoryPath.appending(components: "GitHub", "license.json")
                    let data = Data(try! localFileSystem.readFileContents(path).contents)
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                              body: data)))
                default:
                    XCTFail("method and url should match")
                }
            }

            var httpClient = HTTPClient(handler: handler)
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none
            let provider = GitHubPackageMetadataProvider(httpClient: httpClient)
            let reference = PackageReference(repository: RepositorySpecifier(url: repoURL))
            let metadata = try tsc_await { callback in provider.get(reference, callback: callback) }

            XCTAssertEqual(metadata.summary, "This your first repo!")
            XCTAssertEqual(metadata.versions.count, 1)
            XCTAssertEqual(metadata.versions[0].version, TSCUtility.Version("1.0.0"))
            XCTAssertEqual(metadata.versions[0].summary, "Description of the release")
            XCTAssertEqual(metadata.authors, [PackageCollectionsModel.Package.Author(username: "octocat",
                                                                                     url: URL(string: "https://api.github.com/users/octocat")!,
                                                                                     service: .init(name: "GitHub"))])
            XCTAssertEqual(metadata.readmeURL, URL(string: "https://raw.githubusercontent.com/octokit/octokit.rb/master/README.md"))
            XCTAssertEqual(metadata.license?.type, PackageCollectionsModel.LicenseType.MIT)
            XCTAssertEqual(metadata.license?.url, URL(string: "https://raw.githubusercontent.com/benbalter/gman/master/LICENSE?lab=true"))
            XCTAssertEqual(metadata.watchersCount, 80)
        }
    }

    func testRepoNotFound() throws {
        let repoURL = "https://github.com/octocat/Hello-World.git"

        let handler: HTTPClient.Handler = { _, _, completion in
            completion(.success(.init(statusCode: 404)))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let provider = GitHubPackageMetadataProvider(httpClient: httpClient)
        let reference = PackageReference(repository: RepositorySpecifier(url: repoURL))
        XCTAssertThrowsError(try tsc_await { callback in provider.get(reference, callback: callback) }, "should throw error") { error in
            XCTAssert(error is NotFoundError, "\(error)")
        }
    }

    func testOthersNotFound() throws {
        let repoURL = "https://github.com/octocat/Hello-World.git"
        let apiURL = URL(string: "https://api.github.com/repos/octocat/Hello-World")!

        fixture(name: "Collections") { directoryPath in
            let path = directoryPath.appending(components: "GitHub", "metadata.json")
            let data = try Data(localFileSystem.readFileContents(path).contents)
            let handler: HTTPClient.Handler = { request, _, completion in
                switch (request.method, request.url) {
                case (.get, apiURL):
                    completion(.success(.init(statusCode: 200,
                                              headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                              body: data)))
                default:
                    completion(.success(.init(statusCode: 500)))
                }
            }

            var httpClient = HTTPClient(handler: handler)
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none
            let provider = GitHubPackageMetadataProvider(httpClient: httpClient)
            let reference = PackageReference(repository: RepositorySpecifier(url: repoURL))
            let metadata = try tsc_await { callback in provider.get(reference, callback: callback) }

            XCTAssertEqual(metadata.summary, "This your first repo!")
            XCTAssertEqual(metadata.versions, [])
            XCTAssertNil(metadata.authors)
            XCTAssertNil(metadata.readmeURL)
            XCTAssertEqual(metadata.watchersCount, 80)
        }
    }

    func testPermissionDenied() throws {
        let repoURL = "https://github.com/octocat/Hello-World.git"
        let apiURL = URL(string: "https://api.github.com/repos/octocat/Hello-World")!

        let handler: HTTPClient.Handler = { _, _, completion in
            completion(.success(.init(statusCode: 401)))
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        let provider = GitHubPackageMetadataProvider(httpClient: httpClient)
        let reference = PackageReference(repository: RepositorySpecifier(url: repoURL))
        XCTAssertThrowsError(try tsc_await { callback in provider.get(reference, callback: callback) }, "should throw error") { error in
            XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .permissionDenied(apiURL))
        }
    }

    func testInvalidAuthToken() throws {
        let repoURL = "https://github.com/octocat/Hello-World.git"
        let apiURL = URL(string: "https://api.github.com/repos/octocat/Hello-World")!
        let authTokens = [AuthTokenType.github("api.github.com"): "foo"]

        let handler: HTTPClient.Handler = { request, _, completion in
            if request.headers.get("Authorization").first == "token \(authTokens.first!.value)" {
                completion(.success(.init(statusCode: 401)))
            } else {
                XCTFail("expected correct authorization header")
                completion(.success(.init(statusCode: 500)))
            }
        }

        var httpClient = HTTPClient(handler: handler)
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        var provider = GitHubPackageMetadataProvider(httpClient: httpClient)
        provider.configuration.authTokens = authTokens
        let reference = PackageReference(repository: RepositorySpecifier(url: repoURL))
        XCTAssertThrowsError(try tsc_await { callback in provider.get(reference, callback: callback) }, "should throw error") { error in
            XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .invalidAuthToken(apiURL))
        }
    }

    func testAPILimit() throws {
        let repoURL = "https://github.com/octocat/Hello-World.git"
        let apiURL = URL(string: "https://api.github.com/repos/octocat/Hello-World")!

        let total = 5
        var remaining = total

        fixture(name: "Collections") { directoryPath in
            let path = directoryPath.appending(components: "GitHub", "metadata.json")
            let data = try Data(localFileSystem.readFileContents(path).contents)
            let handler: HTTPClient.Handler = { request, _, completion in
                var headers = HTTPClientHeaders()
                headers.add(name: "X-RateLimit-Limit", value: "\(total)")
                headers.add(name: "X-RateLimit-Remaining", value: "\(remaining)")
                if remaining == 0 {
                    completion(.success(.init(statusCode: 403, headers: headers)))
                } else if request.url == apiURL {
                    remaining = remaining - 1
                    headers.add(name: "Content-Length", value: "\(data.count)")
                    completion(.success(.init(statusCode: 200,
                                              headers: headers,
                                              body: data)))
                } else {
                    completion(.success(.init(statusCode: 500)))
                }
            }

            var httpClient = HTTPClient(handler: handler)
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none
            let provider = GitHubPackageMetadataProvider(httpClient: httpClient)
            let reference = PackageReference(repository: RepositorySpecifier(url: repoURL))
            for index in 0 ... total * 2 {
                if index >= total {
                    XCTAssertThrowsError(try tsc_await { callback in provider.get(reference, callback: callback) }, "should throw error") { error in
                        XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .apiLimitsExceeded(apiURL, total))
                    }
                } else {
                    XCTAssertNoThrow(try tsc_await { callback in provider.get(reference, callback: callback) })
                }
            }
        }
    }

    func testInvalidURL() throws {
        fixture(name: "Collections") { _ in
            let provider = GitHubPackageMetadataProvider()
            let reference = PackageReference(repository: RepositorySpecifier(url: UUID().uuidString))
            XCTAssertThrowsError(try tsc_await { callback in provider.get(reference, callback: callback) }, "should throw error") { error in
                XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .invalidGitURL(reference.location))
            }
        }
    }

    func testInvalidRef() throws {
        fixture(name: "Collections") { _ in
            let provider = GitHubPackageMetadataProvider()
            let reference = PackageReference.local(identity: .init(path: AbsolutePath("/")), path: .root)
            XCTAssertThrowsError(try tsc_await { callback in provider.get(reference, callback: callback) }, "should throw error") { error in
                XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .invalidReferenceType(reference))
            }
        }
    }

    func testForRealz() throws {
        #if ENABLE_GITHUB_NETWORK_TEST
        #else
        try XCTSkipIf(true)
        #endif

        let repoURL = "https://github.com/apple/swift-numerics.git"

        var httpClient = HTTPClient()
        httpClient.configuration.circuitBreakerStrategy = .none
        httpClient.configuration.retryStrategy = .none
        httpClient.configuration.requestHeaders = .init()
        httpClient.configuration.requestHeaders!.add(name: "Cache-Control", value: "no-cache")
        var configuration = GitHubPackageMetadataProvider.Configuration()
        if let token = ProcessEnv.vars["GITHUB_API_TOKEN"] {
            configuration.authTokens = [.github("api.github.com"): token]
        }
        configuration.apiLimitWarningThreshold = 50
        let provider = GitHubPackageMetadataProvider(configuration: configuration, httpClient: httpClient)
        let reference = PackageReference(repository: RepositorySpecifier(url: repoURL))
        for _ in 0 ... 60 {
            let metadata = try tsc_await { callback in provider.get(reference, callback: callback) }
            XCTAssertNotNil(metadata)
            XCTAssert(metadata.versions.count > 0)
            XCTAssert(metadata.keywords!.count > 0)
            XCTAssertNotNil(metadata.license)
            XCTAssert(metadata.authors!.count > 0)
        }
    }
}
