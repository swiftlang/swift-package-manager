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

@testable import Basics
import Foundation
import _InternalTestSupport
import Testing

import class Basics.AsyncProcess
import struct TSCUtility.Version

// MARK: - PktLine

@Suite("PktLine")
struct PktLineTests {

    @Test("encode produces correct hex-prefixed pkt-line")
    func encode() {
        let encoded = PktLine.encode("command=ls-refs\n")
        let str = String(data: encoded, encoding: .ascii)!
        #expect(str == "0014command=ls-refs\n")
    }

    @Test("encode without trailing newline")
    func encodeNoNewline() {
        let encoded = PktLine.encode("agent=git/2.50.1-Darwin")
        let str = String(data: encoded, encoding: .ascii)!
        #expect(str == "001bagent=git/2.50.1-Darwin")
    }

    @Test("decode parses pkt-line response, skipping flush and delimiter")
    func decode() {
        var data = Data()
        data.append(PktLine.encode("first line\n"))
        data.append(PktLine.delimiter)
        data.append(PktLine.encode("second line\n"))
        data.append(PktLine.flush)

        let lines = PktLine.decode(data)
        #expect(lines == ["first line", "second line"])
    }

    @Test("decode handles empty data")
    func decodeEmpty() {
        #expect(PktLine.decode(Data()).isEmpty)
    }

    @Test("decode handles truncated length prefix")
    func decodeTruncated() {
        let data = Data("00".utf8)
        #expect(PktLine.decode(data).isEmpty)
    }

    @Test("encode-decode round trip")
    func roundTrip() {
        let original = "abc123 refs/tags/v1.0.0 peeled:def456"
        var data = Data()
        data.append(PktLine.encode(original))
        data.append(PktLine.flush)
        let decoded = PktLine.decode(data)
        #expect(decoded == [original])
    }
}

// MARK: - GitHTTPProtocolV2 URL construction

struct SmartHTTPURLCase: CustomTestStringConvertible, Sendable {
    let input: String
    let infoRefs: String?
    let uploadPack: String?

    var testDescription: String { input }
}

@Suite("GitHTTPProtocolV2.makeSmartHTTPURLs")
struct SmartHTTPURLTests {

    static let cases: [SmartHTTPURLCase] = [
        SmartHTTPURLCase(
            input: "https://github.com/apple/swift-log.git",
            infoRefs: "https://github.com/apple/swift-log.git/info/refs?service=git-upload-pack",
            uploadPack: "https://github.com/apple/swift-log.git/git-upload-pack"
        ),
        SmartHTTPURLCase(
            input: "https://github.com/apple/swift-log",
            infoRefs: "https://github.com/apple/swift-log/info/refs?service=git-upload-pack",
            uploadPack: "https://github.com/apple/swift-log/git-upload-pack"
        ),
        SmartHTTPURLCase(
            input: "http://example.com/repo.git",
            infoRefs: "http://example.com/repo.git/info/refs?service=git-upload-pack",
            uploadPack: "http://example.com/repo.git/git-upload-pack"
        ),
        SmartHTTPURLCase(
            input: "https://github.com/apple/swift-log.git/",
            infoRefs: "https://github.com/apple/swift-log.git/info/refs?service=git-upload-pack",
            uploadPack: "https://github.com/apple/swift-log.git/git-upload-pack"
        ),
        SmartHTTPURLCase(input: "ssh://git@github.com/apple/swift-log.git", infoRefs: nil, uploadPack: nil),
        SmartHTTPURLCase(input: "git@github.com:apple/swift-log.git", infoRefs: nil, uploadPack: nil),
    ]

    @Test("constructs correct URLs or returns nil", arguments: cases)
    func urlConstruction(testCase: SmartHTTPURLCase) {
        let urls = GitHTTPProtocolV2.makeSmartHTTPURLs(from: testCase.input)
        #expect(urls?.infoRefs.absoluteString == testCase.infoRefs)
        #expect(urls?.uploadPack.absoluteString == testCase.uploadPack)
    }
}

// MARK: - GitHTTPProtocolV2.resolvedTags

@Suite("GitHTTPProtocolV2.resolvedTags")
struct ParseTagRefsTests {

    @Test("lightweight semver tag")
    func lightweight() {
        let lines = ["abc123 refs/tags/1.0.0"]
        let tags = GitHTTPProtocolV2.resolvedTags(from: lines)
        #expect(tags == [ResolvedTag(name:"1.0.0", commitSHA: "abc123", version: Version(1, 0, 0))])
    }

    @Test("annotated tag uses peeled SHA")
    func annotatedPeeled() {
        let lines = ["tagobj123 refs/tags/v2.0.0 peeled:commit456"]
        let tags = GitHTTPProtocolV2.resolvedTags(from: lines)
        #expect(tags == [ResolvedTag(name:"v2.0.0", commitSHA: "commit456", version: Version(2, 0, 0))])
    }

    @Test("non-semver tags are filtered out")
    func nonSemver() {
        let lines = [
            "aaa refs/tags/1.0.0",
            "bbb refs/tags/not-a-version",
            "ccc refs/tags/v3.0.0-rc.1",
        ]
        let tags = GitHTTPProtocolV2.resolvedTags(from: lines)
        #expect(tags.count == 2)
        #expect(tags[0].name == "1.0.0")
        #expect(tags[1].name == "v3.0.0-rc.1")
    }

    @Test("mixed lightweight and annotated tags")
    func mixed() {
        let lines = [
            "aaa refs/tags/1.0.0",
            "bbb refs/tags/v2.0.0 peeled:ccc",
            "ddd refs/tags/3.0.0",
        ]
        let tags = GitHTTPProtocolV2.resolvedTags(from: lines)
        #expect(tags.count == 3)
        #expect(tags[0] == ResolvedTag(name:"1.0.0", commitSHA: "aaa", version: Version(1, 0, 0)))
        #expect(tags[1] == ResolvedTag(name:"v2.0.0", commitSHA: "ccc", version: Version(2, 0, 0)))
        #expect(tags[2] == ResolvedTag(name:"3.0.0", commitSHA: "ddd", version: Version(3, 0, 0)))
    }

    @Test("empty input returns empty")
    func empty() {
        #expect(GitHTTPProtocolV2.resolvedTags(from: []).isEmpty)
    }

    @Test("malformed lines are skipped")
    func malformed() {
        let lines = ["", "no-space-line", "abc refs/heads/main"]
        #expect(GitHTTPProtocolV2.resolvedTags(from: lines).isEmpty)
    }
}

// MARK: - makeTagRefsRequestBody

@Suite("GitHTTPProtocolV2.makeTagRefsRequestBody")
struct LsRefsTagsBodyTests {

    @Test("body emits per-digit ref-prefix lines for semver filtering")
    func bodyStructure() {
        let body = GitHTTPProtocolV2.makeTagRefsRequestBody()
        let lines = PktLine.decode(body)
        #expect(lines.contains("command=ls-refs"))
        #expect(!lines.contains { $0.hasPrefix("agent=") }, "agent must not be sent without server capability")
        #expect(lines.contains { $0.contains("peel") })
        for digit in 0...9 {
            #expect(lines.contains("ref-prefix refs/tags/\(digit)"))
            #expect(lines.contains("ref-prefix refs/tags/v\(digit)"))
        }
    }

    @Test("agent line included when server advertises agent capability")
    func agentIncludedWhenAdvertised() {
        let body = GitHTTPProtocolV2.makeTagRefsRequestBody(
            serverCapabilities: ["agent=git/2.45.0", "ls-refs=unborn"]
        )
        let lines = PktLine.decode(body)
        #expect(lines.contains { $0.hasPrefix("agent=SwiftPackageManager/") })
    }
}

// MARK: - End-to-end against a real git repo

@Suite("PktLine + resolvedTags against real git upload-pack", .tags(.TestSize.large))
struct GitProtocolV2E2ETests {

    @Test("pkt-line parser and resolvedTags handle real git upload-pack output")
    func realUploadPack() async throws {
        try await withTemporaryDirectory(removeTreeOnDeinit: true) { tmpDir in
            let bareRepoPath = tmpDir.appending(component: "test-repo.git")
            let workTreePath = tmpDir.appending(component: "work")

            try await git("init", "--bare", bareRepoPath.pathString)
            try await git("clone", bareRepoPath.pathString, workTreePath.pathString)
            try await git("-C", workTreePath.pathString, "config", "user.email", "test@test.com")
            try await git("-C", workTreePath.pathString, "config", "user.name", "Test")

            // First commit + lightweight tag.
            try localFileSystem.writeFileContents(
                workTreePath.appending(component: "file.txt"), string: "v1\n"
            )
            try await git("-C", workTreePath.pathString, "add", ".")
            try await git("-C", workTreePath.pathString, "commit", "-m", "First")
            try await git("-C", workTreePath.pathString, "tag", "1.0.0")

            // Second commit + annotated tag.
            try localFileSystem.writeFileContents(
                workTreePath.appending(component: "file.txt"), string: "v2\n"
            )
            try await git("-C", workTreePath.pathString, "add", ".")
            try await git("-C", workTreePath.pathString, "commit", "-m", "Second")
            try await git("-C", workTreePath.pathString, "tag", "-a", "v2.0.0", "-m", "Release 2.0.0")

            // Non-semver tag (should be filtered out).
            try await git("-C", workTreePath.pathString, "tag", "nightly-2025-01-01")

            try await git("-C", workTreePath.pathString, "push", "origin", "HEAD", "--tags")

            // Pipe our pkt-line ls-refs request into git upload-pack --stateless-rpc
            // via a shell pipe so we don't need package-scoped AsyncProcess.launch().
            let requestBody = GitHTTPProtocolV2.makeTagRefsRequestBody()
            let requestPath = tmpDir.appending(component: "request.bin")
            try localFileSystem.writeFileContents(requestPath, bytes: .init(requestBody))

            let responseData = try await uploadPack(
                repoPath: bareRepoPath.pathString,
                requestPath: requestPath.pathString
            )

            // Full pipeline: PktLine.decode → resolvedTags
            let lines = PktLine.decode(responseData)
            let tags = GitHTTPProtocolV2.resolvedTags(from: lines)

            // resolvedTags(from:) filters to valid semver — non-semver tags
            // like "nightly-2025-01-01" are excluded regardless of whether
            // the server honoured the ref-prefix hint.
            let tagNames = Set(tags.map(\.name))
            #expect(tagNames.contains("1.0.0"), "lightweight tag missing")
            #expect(tagNames.contains("v2.0.0"), "annotated tag missing")
            #expect(!tagNames.contains("nightly-2025-01-01"), "non-semver tag should be filtered by client")
            #expect(tags.count >= 2, "expected at least the 2 semver tags")

            for tag in tags {
                #expect(tag.commitSHA.count == 40, "SHA should be 40 hex chars, got '\(tag.commitSHA)'")
                #expect(tag.commitSHA.allSatisfy { $0.isHexDigit }, "SHA contains non-hex: '\(tag.commitSHA)'")
            }

            // Annotated tag must resolve to the commit SHA (peeled), not the tag object.
            let v1SHA = tags.first { $0.name == "1.0.0" }?.commitSHA
            let v2SHA = tags.first { $0.name == "v2.0.0" }?.commitSHA
            #expect(v1SHA != v2SHA, "different commits should have different SHAs")

            let expectedV2CommitSHA = try await git(
                "-C", bareRepoPath.pathString, "rev-parse", "v2.0.0^{commit}"
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(v2SHA == expectedV2CommitSHA, "annotated tag should peel to commit SHA")

            #expect(tags.first { $0.name == "1.0.0" }?.version == Version(1, 0, 0))
            #expect(tags.first { $0.name == "v2.0.0" }?.version == Version(2, 0, 0))
        }
    }

    @discardableResult
    private func git(_ args: String...) async throws -> String {
        try await AsyncProcess.checkNonZeroExit(arguments: ["git"] + args)
    }

    /// Runs `git upload-pack --stateless-rpc` with GIT_PROTOCOL=version=2,
    /// piping the request file to stdin and returning the raw response bytes.
    private func uploadPack(repoPath: String, requestPath: String) async throws -> Data {
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "upload-pack", "--stateless-rpc", repoPath]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["GIT_PROTOCOL": "version=2"]
        ) { _, new in new }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        let requestData = try Data(contentsOf: URL(fileURLWithPath: requestPath))
        stdinPipe.fileHandleForWriting.write(requestData)
        stdinPipe.fileHandleForWriting.closeFile()

        let responseData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw StringError("git upload-pack exited with status \(process.terminationStatus)")
        }
        return responseData
    }
}
