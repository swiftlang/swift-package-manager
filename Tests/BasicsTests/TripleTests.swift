//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2022-2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
import Foundation

import Basics
import Testing

struct TripleTests {
    @Test(
        "Triple is Apple and is Darwin",
        arguments: [
            (tripleName: "x86_64-pc-linux-gnu", isApple: false, isDarwin: false),
            (tripleName: "x86_64-pc-linux-musl", isApple: false, isDarwin: false),
            (tripleName: "powerpc-bgp-linux", isApple: false, isDarwin: false),
            (tripleName: "arm-none-none-eabi", isApple: false, isDarwin: false),
            (tripleName: "arm-none-linux-musleabi", isApple: false, isDarwin: false),
            (tripleName: "wasm32-unknown-wasi", isApple: false, isDarwin: false),
            (tripleName: "riscv64-unknown-linux", isApple: false, isDarwin: false),
            (tripleName: "mips-mti-linux-gnu", isApple: false, isDarwin: false),
            (tripleName: "mipsel-img-linux-gnu", isApple: false, isDarwin: false),
            (tripleName: "mips64-mti-linux-gnu", isApple: false, isDarwin: false),
            (tripleName: "mips64el-img-linux-gnu", isApple: false, isDarwin: false),
            (tripleName: "mips64el-img-linux-gnuabin32", isApple: false, isDarwin: false),
            (tripleName: "mips64-unknown-linux-gnuabi64", isApple: false, isDarwin: false),
            (tripleName: "mips64-unknown-linux-gnuabin32", isApple: false, isDarwin: false),
            (tripleName: "mipsel-unknown-linux-gnu", isApple: false, isDarwin: false),
            (tripleName: "mips-unknown-linux-gnu", isApple: false, isDarwin: false),
            (tripleName: "arm-oe-linux-gnueabi", isApple: false, isDarwin: false),
            (tripleName: "aarch64-oe-linux", isApple: false, isDarwin: false),
            (tripleName: "armv7em-unknown-none-macho", isApple: false, isDarwin: false),
            (tripleName: "armv7em-apple-none-macho", isApple: true, isDarwin: false),
            (tripleName: "armv7em-apple-none", isApple: true, isDarwin: false),
            (tripleName: "aarch64-apple-macosx", isApple: true, isDarwin: true),
            (tripleName: "x86_64-apple-macosx", isApple: true, isDarwin: true),
            (tripleName: "x86_64-apple-macosx10.15", isApple: true, isDarwin: true),
            (tripleName: "x86_64h-apple-darwin", isApple: true, isDarwin: true),
            (tripleName: "i686-pc-windows-msvc", isApple: false, isDarwin: false),
            (tripleName: "i686-pc-windows-gnu", isApple: false, isDarwin: false),
            (tripleName: "i686-pc-windows-cygnus", isApple: false, isDarwin: false),
        ],
    )
    func isAppleIsDarwin(_ tripleName: String, _ isApple: Bool, _ isDarwin: Bool) throws {
        let triple = try Triple(tripleName)
        #expect(
            isApple == triple.isApple(),
            """
            Expected triple '\(triple.tripleString)' \
            \(isApple ? "" : " not") to be an Apple triple.
            """,
        )
        #expect(
            isDarwin == triple.isDarwin(),
            """
            Expected triple '\(triple.tripleString)' \
            \(isDarwin ? "" : " not") to be a Darwin triple.
            """,
        )
    }

    @Test
    func description() throws {
        let triple = try Triple("x86_64-pc-linux-gnu")
        #expect("foo \(triple) bar" == "foo x86_64-pc-linux-gnu bar")
    }

    @Test(
        "Triple String for Platform Version",
        arguments: [
            (
                tripleName: "x86_64-apple-macosx",
                version: "",
                expectedTriple: "x86_64-apple-macosx",
            ),
            (
                tripleName: "x86_64-apple-macosx",
                version: "13.0",
                expectedTriple: "x86_64-apple-macosx13.0",
            ),
            (
                tripleName: "armv7em-apple-macosx10.12",
                version: "",
                expectedTriple: "armv7em-apple-macosx",
            ),
            (
                tripleName: "armv7em-apple-macosx10.12",
                version: "13.0",
                expectedTriple: "armv7em-apple-macosx13.0",
            ),
            (
                tripleName: "powerpc-apple-macos",
                version: "",
                expectedTriple: "powerpc-apple-macos",
            ),
            (
                tripleName: "powerpc-apple-macos",
                version: "13.0",
                expectedTriple: "powerpc-apple-macos13.0",
            ),
            (
                tripleName: "i686-apple-macos10.12.0",
                version: "",
                expectedTriple: "i686-apple-macos",
            ),
            (
                tripleName: "i686-apple-macos10.12.0",
                version: "13.0",
                expectedTriple: "i686-apple-macos13.0",
            ),
            (
                tripleName: "riscv64-apple-darwin",
                version: "",
                expectedTriple: "riscv64-apple-darwin",
            ),
            (
                tripleName: "riscv64-apple-darwin",
                version: "22",
                expectedTriple: "riscv64-apple-darwin22",
            ),
            (
                tripleName: "mips-apple-darwin19",
                version: "",
                expectedTriple: "mips-apple-darwin",
            ),
            (
                tripleName: "mips-apple-darwin19",
                version: "22",
                expectedTriple: "mips-apple-darwin22",
            ),
            (
                tripleName: "arm64-apple-ios-simulator",
                version: "",
                expectedTriple: "arm64-apple-ios-simulator",
            ),
            (
                tripleName: "arm64-apple-ios-simulator",
                version: "13.0",
                expectedTriple: "arm64-apple-ios13.0-simulator",
            ),
            (
                tripleName: "arm64-apple-ios12-simulator",
                version: "",
                expectedTriple: "arm64-apple-ios-simulator",
            ),
            (
                tripleName: "arm64-apple-ios12-simulator",
                version: "13.0",
                expectedTriple: "arm64-apple-ios13.0-simulator",
            ),
        ]
    )
    func tripleStringForPlatformVersion(
        tripleName: String, version: String, expectedTriple: String
    ) throws {
        let triple = try Triple(tripleName)
        let actualTriple = triple.tripleString(forPlatformVersion: version)
        #expect(
            actualTriple == expectedTriple,
            """
            Actual triple '\(actualTriple)' did not match expected triple \
            '\(expectedTriple)' for platform version '\(version)'.
            """,
        )

    }

    struct DataKnownTripleParsing {
        var tripleName: String
        var expectedArch: Triple.Arch?
        var expectedSubArch: Triple.SubArch?
        var expectedVendor: Triple.Vendor?
        var expectedOs: Triple.OS?
        var expectedEnvironment: Triple.Environment?
        var expectedObjectFormat: Triple.ObjectFormat?
    }
    @Test(
        "Known Triple Parsing",
        arguments: [
            DataKnownTripleParsing(
                tripleName: "armv7em-apple-none-eabihf-macho",
                expectedArch: .arm,
                expectedSubArch : .arm(.v7em),
                expectedVendor: .apple,
                expectedOs: .noneOS,
                expectedEnvironment: .eabihf,
                expectedObjectFormat: .macho
            ),
            DataKnownTripleParsing(
                tripleName: "x86_64-apple-macosx",
                expectedArch: .x86_64,
                expectedSubArch: nil,
                expectedVendor: .apple,
                expectedOs: .macosx,
                expectedEnvironment: nil,
                expectedObjectFormat: .macho
            ),
            DataKnownTripleParsing(
                tripleName: "x86_64-unknown-linux-gnu",
                expectedArch: .x86_64,
                expectedSubArch: nil,
                expectedVendor: nil,
                expectedOs: .linux,
                expectedEnvironment: .gnu,
                expectedObjectFormat: .elf
            ),
            DataKnownTripleParsing(
                tripleName: "aarch64-unknown-linux-gnu",
                expectedArch: .aarch64,
                expectedSubArch: nil,
                expectedVendor: nil,
                expectedOs: .linux,
                expectedEnvironment: .gnu,
                expectedObjectFormat: .elf
            ),
            DataKnownTripleParsing(
                tripleName: "aarch64-unknown-linux-android",
                expectedArch: .aarch64,
                expectedSubArch: nil,
                expectedVendor: nil,
                expectedOs: .linux,
                expectedEnvironment: .android,
                expectedObjectFormat: .elf
            ),
            DataKnownTripleParsing(
                tripleName: "x86_64-unknown-windows-msvc",
                expectedArch: .x86_64,
                expectedSubArch: nil,
                expectedVendor: nil,
                expectedOs: .win32,
                expectedEnvironment: .msvc,
                expectedObjectFormat: .coff
            ),
            DataKnownTripleParsing(
                tripleName: "wasm32-unknown-wasi",
                expectedArch: .wasm32,
                expectedSubArch: nil,
                expectedVendor: nil,
                expectedOs: .wasi,
                expectedEnvironment: nil,
                expectedObjectFormat: .wasm
            )
        ]
    )
    func knownTripleParsing(
        data: DataKnownTripleParsing,
    ) throws {
        let triple = try Triple(data.tripleName)
        #expect(triple.arch == data.expectedArch, "Actual arch not as expected")
        #expect(triple.subArch == data.expectedSubArch, "Actual subarch is not as expected")
        #expect(triple.vendor == data.expectedVendor, "Actual Vendor is not as expected")
        #expect(triple.os == data.expectedOs, "Actual OS is not as expcted")
        #expect(triple.environment == data.expectedEnvironment, "Actual environment is not as expected")
        #expect(triple.objectFormat == data.expectedObjectFormat, "Actual object format is not as expected")
    }

    @Test
    func triple() throws {
        let linux = try Triple("x86_64-unknown-linux-gnu")
        #expect(linux.os == .linux)
        #expect(linux.osVersion == Triple.Version.zero)
        #expect(linux.environment == .gnu)

        let macos = try Triple("x86_64-apple-macosx10.15")
        #expect(macos.osVersion == .init(parse: "10.15"))
        let newVersion = "10.12"
        let tripleString = macos.tripleString(forPlatformVersion: newVersion)
        #expect(tripleString == "x86_64-apple-macosx10.12")
        let macosNoX = try Triple("x86_64-apple-macos12.2")
        #expect(macosNoX.os == .macosx)
        #expect(macosNoX.osVersion == .init(parse: "12.2"))

        let android = try Triple("aarch64-unknown-linux-android24")
        #expect(android.os == .linux)
        #expect(android.environment == .android)

        let linuxWithABIVersion = try Triple("x86_64-unknown-linux-gnu42")
        #expect(linuxWithABIVersion.environment == .gnu)
    }

    @Test
    func equality() throws {
        let macOSTriple = try Triple("arm64-apple-macos")
        let macOSXTriple = try Triple("arm64-apple-macosx")
        #expect(macOSTriple == macOSXTriple)

        let intelMacOSTriple = try Triple("x86_64-apple-macos")
        #expect(macOSTriple != intelMacOSTriple)

        let linuxWithoutGNUABI = try Triple("x86_64-unknown-linux")
        let linuxWithGNUABI = try Triple("x86_64-unknown-linux-gnu")
        #expect(linuxWithoutGNUABI != linuxWithGNUABI)
    }

    @Test
    func WASI() throws {
        let wasi = try Triple("wasm32-unknown-wasi")

        // WASI dynamic libraries are only experimental,
        // but SwiftPM requires this property not to crash.
        _ = wasi.dynamicLibraryExtension
    }

    @Test(
        "Test dynamicLibraryExtesion attribute on Triple returns expected value",
        arguments: [
            (tripleName: "armv7em-unknown-none-coff", expected: ".coff"),
            (tripleName: "armv7em-unknown-none-elf", expected: ".elf"),
            (tripleName: "armv7em-unknown-none-macho", expected: ".macho"),
            (tripleName: "armv7em-unknown-none-wasm", expected: ".wasm"),
            (tripleName: "armv7em-unknown-none-xcoff", expected: ".xcoff"),
            (tripleName: "wasm32-unknown-wasi", expected: ".wasm"),  // Added by bkhouri
        ],
    )
    func noneOSDynamicLibrary(tripleName: String, expected: String) throws {
        // Dynamic libraries aren't actually supported for OS none, but swiftpm
        // wants an extension to avoid crashing during build planning.
        let triple = try Triple(tripleName)
        #expect(triple.dynamicLibraryExtension == expected)
    }

    @Test(
        "isRuntimeCompatibleWith returns expected value",
        arguments: [
            (
                firstTripleName: "x86_64-apple-macosx",
                secondTripleName: "x86_64-apple-macosx",
                isCompatible: true,
            ),
            (
                firstTripleName: "x86_64-unknown-linux",
                secondTripleName: "x86_64-unknown-linux",
                isCompatible: true,
            ),
            (
                firstTripleName: "x86_64-apple-macosx",
                secondTripleName: "x86_64-apple-linux",
                isCompatible: false,
            ),
            (
                firstTripleName: "x86_64-apple-macosx14.0",
                secondTripleName: "x86_64-apple-macosx13.0",
                isCompatible: true,
            ),
        ],
    )
    func isRuntimeCompatibleWith(
        firstTripleName: String, secondTripleName: String, isCompatible: Bool,
    ) throws {
        let triple = try Triple(firstTripleName)
        let other = try Triple(secondTripleName)
        #expect(triple.isRuntimeCompatible(with: other) == isCompatible)
    }
}
