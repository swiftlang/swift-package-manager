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
import ArgumentParser
import Foundation
import Subprocess
#if canImport(System)
import System
#else
import SystemPackage
#endif

@main
struct ApkBuilder: AsyncParsableCommand {
    @Option(help: "The name of the target")
    var name: String

    @Option(help: "The output directory")
    var outputDir: FilePath

    @Option(help: "The Swift SDK used to build")
    var swiftResourceDir: FilePath

    @Option(help: "The Android NDK sysroot")
    var sysroot: FilePath

    @Option(help: "Native lib to add to APK")
    var nativeLib: [FilePath]

    @Option(help: "Jars to build the java source with and include in APK")
    var jar: [FilePath]

    @Option(help: "Java files to build")
    var java: [FilePath]

    @Option(help: "Than AndroidManifest.xml file")
    var manifest: FilePath

    let androidHome: FilePath
    
    init() {
        guard let androidHome = ProcessInfo.processInfo.environment["ANDROID_HOME"] else {
            fatalError("ANDROID_HOME not defined")
        }

        self.androidHome = .init(androidHome)
    }

    func run() async throws {
        // TODO: parameterize the platform version
        let androidJar = androidHome.appending("platforms/android-35/android.jar")
        let buildToolsDir = androidHome.appending("build-tools/35.0.0")

        // Copy over native libraries and runtime
        let apkTemp = outputDir.appending("apk")
        let apkLib = apkTemp.appending("lib/arm64-v8a")

        try? FileManager.default.removeItem(atPath: apkTemp.string)
        try FileManager.default.createDirectory(atPath: apkLib.string, withIntermediateDirectories: true)

        for lib in nativeLib {
            try FileManager.default.copyItem(atPath: lib.string, toPath: apkLib.appending(lib.lastComponent!).string)
        }

        let swiftDir = swiftResourceDir.appending("android")
        let swiftLibs = [
            "lib_FoundationICU.so",
            "libBlocksRuntime.so",
            "libFoundation.so",
            "libFoundationEssentials.so",
            "libFoundationInternationalization.so",
            "libdispatch.so",
            "libswiftAndroid.so",
            "libswiftCore.so",
            "libswiftDispatch.so",
            "libswiftSwiftOnoneSupport.so",
            "libswiftSynchronization.so",
            "libswift_Builtin_float.so",
            "libswift_Concurrency.so",
            "libswift_RegexParser.so",
            "libswift_StringProcessing.so",
            "libswift_math.so"
        ]
        for lib in swiftLibs {
            try FileManager.default.copyItem(atPath: swiftDir.appending(lib).string, toPath: apkLib.appending(lib).string)
        }

        let cxxShared = sysroot.appending("usr/lib/aarch64-linux-android/libc++_shared.so")
        try FileManager.default.copyItem(atPath: cxxShared.string, toPath: apkLib.appending(cxxShared.lastComponent!).string)

        // Java compile
        let classOutput = outputDir.appending("classes")

        var classpath = androidJar.string
        if !jar.isEmpty {
            classpath += ":" + jar.map(\.string).joined(separator: ":")
        }

        let javacResult = try await Subprocess.run(
            .name("javac"),
            arguments: .init([
                "--release", "17",
                "-classpath", classpath,
                "-d", classOutput.string,
            ] + java.map(\.string)),
            output: .currentStandardOutput,
            error: .currentStandardError
        )

        if !javacResult.terminationStatus.isSuccess {
            throw ApkBuilderError.javaCompileFailed
        }

        let d8Result = try await Subprocess.run(
            .path(buildToolsDir.appending("d8")),
            arguments: .init([
                androidJar.string,
            ] + jar.map(\.string) + Self.findClassFiles(in: classOutput).map(\.string) + [
                "--output", apkTemp.string
            ]),
            output: .currentStandardOutput,
            error: .currentStandardError
        )

        if !d8Result.terminationStatus.isSuccess {
            throw ApkBuilderError.d8Failed
        }

        // TODO: Should use aapt2
        let unsignedApk = outputDir.appending(name + "-unsigned.apk")
        let aaptResult = try await Subprocess.run(
            .path(buildToolsDir.appending("aapt")),
            arguments: .init([
                "package", "-f",
                "-M", manifest.string,
                "-I", androidJar.string,
                "-F", unsignedApk.string,
                apkTemp.string
            ]),
            output: .currentStandardOutput,
            error: .currentStandardError
        )

        if !aaptResult.terminationStatus.isSuccess {
            throw ApkBuilderError.apptFailed
        }

        let alignedApk = outputDir.appending(name + "-aligned.apk")
        let alignResult = try await Subprocess.run(
            .path(buildToolsDir.appending("zipalign")),
            arguments: .init([
                "-f", "-p", "4",
                unsignedApk.string,
                alignedApk.string
            ]),
            output: .currentStandardOutput,
            error: .currentStandardError
        )

        if !alignResult.terminationStatus.isSuccess {
            throw ApkBuilderError.zipalignFailed
        }

        let keystore = androidHome.appending("../android.keystore")
        let apk = outputDir.appending(name + ".apk")
        let signResult = try await Subprocess.run(
            .path(buildToolsDir.appending("apksigner")),
            arguments: .init([
                "sign",
                "--ks", keystore.string,
                "--ks-pass", "pass:android",
                "--key-pass", "pass:android",
                "--out", apk.string,
                alignedApk.string
            ]),
            output: .currentStandardOutput,
            error: .currentStandardError
        )

        if !signResult.terminationStatus.isSuccess {
            throw ApkBuilderError.signingFailed
        }
    }

    static func findClassFiles(in directory: FilePath) throws -> [FilePath] {
        var classFiles: [FilePath] = []

        if let enumerator = FileManager.default.enumerator(atPath: directory.string) {
            for case let relPath as String in enumerator {
                let filePath = FilePath(relPath)
                guard filePath.extension == "class" else { continue }
                classFiles.append(directory.appending(filePath.components))
            }
        }

        return classFiles
    }
}

extension FilePath: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(argument)
    }
}

enum ApkBuilderError: Error {
    case androidHomeNotDefined
    case javaCompileFailed
    case d8Failed
    case apptFailed
    case zipalignFailed
    case signingFailed
}

func doExit() {
    exit(1)
}

