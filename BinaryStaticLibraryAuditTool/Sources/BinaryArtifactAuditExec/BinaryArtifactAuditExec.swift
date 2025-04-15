internal import Foundation
internal import ArgumentParser
internal import SystemPackage
private import BinaryArtifactAudit

@main
struct BinaryArtifactAudit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "binary-artifact-audit",
        abstract: "A utility for validating library binary artifacts.",
        subcommands: [ValidateRemote.self, ValidateLocal.self]
    )
}

extension BinaryArtifactAudit {
    struct ValidateRemote: AsyncParsableCommand {
        @Argument(
            help: "URL to the remote artifact bundle",
            transform: BinaryArtifactAudit.parseURL(argument:)
        )
        var remoteArtifactBundle: URL

        @OptionGroup(title: "Configuration")
        var commonArgs: CommonArgs

        func run() async throws {
            try await BinaryArtifactAudit.check(
                bundle: remoteArtifactBundle,
                bundleProvider: RemoteArtifactBundleProvider(),
                provider: ObjdumpSymbolProvider(objdumpPath: commonArgs.objdump)
            )
        }
    }

    struct ValidateLocal: AsyncParsableCommand {
        @Argument(
            help: "Path to the local artifact bundle",
            transform: parseURL(argument:)
        )
        var localArtifactBundle: URL

        @OptionGroup(title: "Configuration")
        var commonArgs: CommonArgs

        func run() async throws {
            try await BinaryArtifactAudit.check(
                bundle: localArtifactBundle,
                bundleProvider: LocalArtifactBundleProvider(),
                provider: ObjdumpSymbolProvider(objdumpPath: commonArgs.objdump)
            )
        }
    }

    static private func getTargetTriple() async throws -> String {
        let output = try await Process.run(executable: "/usr/bin/clang", arguments: "-v")
        let targetLine = String(data: output.error, encoding: .utf8)!.split(whereSeparator: \.isNewline).first { $0.hasPrefix("Target: ") }!
        return String(targetLine.dropFirst("Target: ".count))
    }

    static private func check(bundle url: URL, bundleProvider: some ArtifactBundleProvider, provider: some SymbolProvider) async throws {
        let localTriple = try await getTargetTriple()
        let bundle = try await bundleProvider.artifact(for: url)
        var platformDefaultSymbols = ReferencedSymbols()

        for binary in try await detectAdditionalObjects() {
            try await provider.symbols(for: binary, symbols: &platformDefaultSymbols, recordUndefined: false)
        }

        for variant in bundle.manifest.artifacts.values.flatMap({ $0.variants }) {
            guard variant.supportedTriples.contains(localTriple) else {
                continue
            }

            let binary = variant.path
            var symbols = platformDefaultSymbols
            try await provider.symbols(for: bundle.root.appending(binary.components), symbols: &symbols)

            guard symbols.undefined.isEmpty else {
                print("Invalid artifact binary \(binary.string), found undefined symbols:")
                for name in symbols.undefined {
                    print("- \(name)")
                }

                throw ExitCode(1)
            }
        }

        print("Artifact is safe to use across supported Swift deployment targets!")
    }
}

struct CommonArgs: ParsableArguments {
    @Option(
        name: .long,
        help: "The path to the llvm-objdump command to use.",
        transform: FilePath.init(_:)
    )
    var objdump: FilePath
}

extension BinaryArtifactAudit {
    enum ParsingError: Error {
        case invalidURLError
    }

    private static func parseURL(argument: String) throws -> URL {
        guard let url = URL(string: argument) else { throw ParsingError.invalidURLError }
        return url
    }
}
