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
    func testBaseRL() throws {
        let apiURL = URL(string: "https://api.github.com/octocat/Hello-World")

        let provider = GitHubPackageMetadataProvider()
        let sshURLRetVal = provider.apiURL("git@github.com:octocat/Hello-World.git")
        XCTAssertEqual(apiURL, sshURLRetVal)

        let httpsURLRetVal = provider.apiURL("https://github.com/octocat/Hello-World.git")
        XCTAssertEqual(apiURL, httpsURLRetVal)

        XCTAssertNil(provider.apiURL("bad/Hello-World.git"))
    }

    func testGood() throws {
        let repoURL = "https://github.com/octocat/Hello-World.git"
        let apiURL = URL(string: "https://api.github.com/octocat/Hello-World")!

        fixture(name: "Collections") { directoryPath in
            let handler = { (request: HTTPClient.Request, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) in
                switch (request.method, request.url) {
                case (.get, apiURL):
                    let path = directoryPath.appending(components: "GitHub", "metadata.json")
                    let data = Data(try! localFileSystem.readFileContents(path).contents)
                    callback(.success(.init(statusCode: 200,
                                            headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                            body: data)))
                case (.get, apiURL.appendingPathComponent("tags")):
                    let path = directoryPath.appending(components: "GitHub", "tags.json")
                    let data = Data(try! localFileSystem.readFileContents(path).contents)
                    callback(.success(.init(statusCode: 200,
                                            headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                            body: data)))
                case (.get, apiURL.appendingPathComponent("contributors")):
                    let path = directoryPath.appending(components: "GitHub", "contributors.json")
                    let data = Data(try! localFileSystem.readFileContents(path).contents)
                    callback(.success(.init(statusCode: 200,
                                            headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                            body: data)))
                case (.get, apiURL.appendingPathComponent("readme")):
                    let path = directoryPath.appending(components: "GitHub", "readme.json")
                    let data = Data(try! localFileSystem.readFileContents(path).contents)
                    callback(.success(.init(statusCode: 200,
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

            XCTAssertEqual(metadata.description, "This your first repo!")
            XCTAssertEqual(metadata.versions, [TSCUtility.Version("0.1.0")])
            XCTAssertEqual(metadata.authors, [PackageCollectionsModel.Package.Author(username: "octocat",
                                                                                     url: URL(string: "https://api.github.com/users/octocat")!,
                                                                                     service: .init(name: "GitHub"))])
            XCTAssertEqual(metadata.readmeURL, URL(string: "https://raw.githubusercontent.com/octokit/octokit.rb/master/README.md"))
            XCTAssertEqual(metadata.watchersCount, 80)
        }
    }

    func testRepoNotFound() throws {
        let repoURL = "https://github.com/octocat/Hello-World.git"

        fixture(name: "Collections") { _ in
            let handler = { (_: HTTPClient.Request, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) in
                callback(.success(.init(statusCode: 404)))
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
    }

    func testOthersNotFound() throws {
        let repoURL = "https://github.com/octocat/Hello-World.git"
        let apiURL = URL(string: "https://api.github.com/octocat/Hello-World")!

        fixture(name: "Collections") { directoryPath in
            let handler = { (request: HTTPClient.Request, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) in
                switch (request.method, request.url) {
                case (.get, apiURL):
                    let path = directoryPath.appending(components: "GitHub", "metadata.json")
                    let data = Data(try! localFileSystem.readFileContents(path).contents)
                    callback(.success(.init(statusCode: 200,
                                            headers: .init([.init(name: "Content-Length", value: "\(data.count)")]),
                                            body: data)))
                default:
                    callback(.success(.init(statusCode: 500)))
                }
            }

            var httpClient = HTTPClient(handler: handler)
            httpClient.configuration.circuitBreakerStrategy = .none
            httpClient.configuration.retryStrategy = .none
            let provider = GitHubPackageMetadataProvider(httpClient: httpClient)
            let reference = PackageReference(repository: RepositorySpecifier(url: repoURL))
            let metadata = try tsc_await { callback in provider.get(reference, callback: callback) }

            XCTAssertEqual(metadata.description, "This your first repo!")
            XCTAssertEqual(metadata.versions, [])
            XCTAssertNil(metadata.authors)
            XCTAssertNil(metadata.readmeURL)
            XCTAssertEqual(metadata.watchersCount, 80)
        }
    }

    func testInvalidURL() throws {
        fixture(name: "Collections") { _ in
            let provider = GitHubPackageMetadataProvider()
            let reference = PackageReference(repository: RepositorySpecifier(url: UUID().uuidString))
            XCTAssertThrowsError(try tsc_await { callback in provider.get(reference, callback: callback) }, "should throw error") { error in
                XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .unprocessable(reference))
            }
        }
    }

    func testInvalidRef() throws {
        fixture(name: "Collections") { _ in
            let provider = GitHubPackageMetadataProvider()
            let reference = PackageReference(identity: .init(path: AbsolutePath("/")), path: "/")
            XCTAssertThrowsError(try tsc_await { callback in provider.get(reference, callback: callback) }, "should throw error") { error in
                XCTAssertEqual(error as? GitHubPackageMetadataProvider.Errors, .unprocessable(reference))
            }
        }
    }
}
