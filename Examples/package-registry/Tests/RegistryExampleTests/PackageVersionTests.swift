//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Testing
@testable import RegistryExample

@Suite("PackageVersion")
struct PackageVersionTests {
    @Test func `parses basic major.minor.patch`() throws {
        let v = try PackageVersion("1.2.3")
        #expect(v.major == 1)
        #expect(v.minor == 2)
        #expect(v.patch == 3)
        #expect(v.prerelease == nil)
        #expect(v.buildMetadata == nil)
    }

    @Test func `parses prerelease and build metadata`() throws {
        let v = try PackageVersion("1.0.0-beta.1+build.7")
        #expect(v.prerelease == "beta.1")
        #expect(v.buildMetadata == "build.7")
    }

    @Test(
        arguments: [
            "",
            "1",
            "1.2",
            "1.2.3.4",
            "01.0.0",
            "1.0.0-",
            "1.0.0-..",
            "1.0.0+",
            "1.0.0+a..b",
            "1.0.0+a b",
            ".1.2",
            "1..2",
            "v1.0.0",
            "abc",
        ]
    )
    func `rejects invalid versions`(_ raw: String) {
        #expect(throws: PackageVersionError.self) {
            _ = try PackageVersion(raw)
        }
    }

    @Test func `description roundtrips`() throws {
        #expect(try PackageVersion("1.2.3").description == "1.2.3")
        #expect(try PackageVersion("1.0.0-alpha").description == "1.0.0-alpha")
        #expect(try PackageVersion("1.0.0-alpha+001").description == "1.0.0-alpha+001")
    }

    @Test func `numeric ordering by major/minor/patch`() throws {
        let a = try PackageVersion("1.0.0")
        let b = try PackageVersion("1.0.1")
        let c = try PackageVersion("1.1.0")
        let d = try PackageVersion("2.0.0")
        #expect(a < b)
        #expect(b < c)
        #expect(c < d)
    }

    @Test func `prerelease has lower precedence than release`() throws {
        let pre = try PackageVersion("1.0.0-alpha")
        let rel = try PackageVersion("1.0.0")
        #expect(pre < rel)
        #expect(!(rel < pre))
    }

    @Test func `prerelease identifier ordering`() throws {
        let alpha = try PackageVersion("1.0.0-alpha")
        let alpha1 = try PackageVersion("1.0.0-alpha.1")
        let beta = try PackageVersion("1.0.0-beta")
        let beta11 = try PackageVersion("1.0.0-beta.11")
        let beta2 = try PackageVersion("1.0.0-beta.2")
        #expect(alpha < alpha1)
        #expect(!(alpha1 < alpha))
        #expect(alpha1 < beta)
        #expect(!(beta < alpha1))
        #expect(beta2 < beta11)
        #expect(!(beta11 < beta2))
    }

    @Test func `numeric prerelease has lower precedence than alphanumeric prerelease`() throws {
        let numericPre = try PackageVersion("1.0.0-1")
        let alphaPre = try PackageVersion("1.0.0-alpha")
        #expect(numericPre < alphaPre)
        #expect(!(alphaPre < numericPre))
    }

    @Test func `shared prefix prerelease with additional identifier is greater`() throws {
        let short = try PackageVersion("1.0.0-alpha")
        let long = try PackageVersion("1.0.0-alpha.beta")
        #expect(short < long)
        #expect(!(long < short))
    }

    @Test func `build metadata is ignored for precedence ordering`() throws {
        let a = try PackageVersion("1.0.0+build1")
        let b = try PackageVersion("1.0.0+build2")
        #expect(!(a < b) && !(b < a))
    }
}