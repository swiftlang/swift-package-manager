import Dispatch

import Basic
import POSIX
import libc
import Utility

/// Execute the file lock test.
///
/// - Parameters:
///   - cacheDir: The cache directory where lock file should be created.
///   - path: Path to a file which will be mutated.
///   - content: Integer that should be added in that file.
func fileLockTest(cacheDir: AbsolutePath, path: AbsolutePath, content: Int) throws {
    let lock = FileLock(name: "TestLock", cachePath: cacheDir)
    try lock.withLock {
        // Get thr current contents of the file if any.
        let currentData: Int
        if localFileSystem.exists(path) {
            currentData = Int(try localFileSystem.readFileContents(path).asString!) ?? 0
        } else {
            currentData = 0
        }
        // Sum and write back to file.
        try localFileSystem.writeFileContents(path, bytes: ByteString(encodingAsUTF8: String(currentData + content)))
    }
}

class HandlerTest {
    let interruptHandler: InterruptHandler

    init(_ file: AbsolutePath) throws {
        interruptHandler = try InterruptHandler {
            print("Hello from handler!")
            libc.exit(0)
        }
        try localFileSystem.writeFileContents(file, bytes: ByteString())
    }

    func run() {
        // Block.
        dispatchMain()
    }
}

// MARK: - Frontend

enum Mode: String {
    case fileLockTest
    case interruptHandlerTest
    case pathArgumentTest
    case help
}

struct Options {
    struct FileLockOptions {
        let cacheDir: AbsolutePath
        let path: AbsolutePath
        let content: Int
    }
    var fileLockOptions: FileLockOptions?
    var temporaryFile: AbsolutePath?
    var absolutePath: AbsolutePath?
    var mode = Mode.help
}

do {
    let binder = ArgumentBinder<Options>()

    let parser = ArgumentParser(
        usage: "subcommand",
        overview: "Test support executable")

    let fileLockParser = parser.add(subparser: Mode.fileLockTest.rawValue, overview: "Execute the file lock test")

    binder.bindPositional(
        fileLockParser.add(positional: "cache directory", kind: String.self, usage: "Path to cache directory"),
        fileLockParser.add(positional: "file path", kind: String.self, usage: "Path of the file to mutate"),
        fileLockParser.add(positional: "contents", kind: Int.self, usage: "Contents to write in the file"),
        to: {
            $0.fileLockOptions = Options.FileLockOptions(
                cacheDir: AbsolutePath($1),
                path: AbsolutePath($2),
                content: $3)
        })

    let intHandlerParser = parser.add(
        subparser: Mode.interruptHandlerTest.rawValue,
        overview: "Execute the interrupt handler test")
    binder.bind(
        positional: intHandlerParser.add(positional: "temporary file", kind: String.self, usage: "Path to temp file"),
        to: { $0.temporaryFile = AbsolutePath($1) })

    let absolutePathParser = parser.add(
        subparser: Mode.pathArgumentTest.rawValue,
        overview: "Print the absolute path for the given relative path")
    binder.bind(
        positional: absolutePathParser.add(
            positional: "relative path",
            kind: PathArgument.self,
            usage: "Relative path to return absolute path for"),
        to: { $0.absolutePath = $1.path })

    binder.bind(
        parser: parser,
        to: { $0.mode = Mode(rawValue: $1)! })

    var options = Options()
    let result = try parser.parse(Array(CommandLine.arguments.dropFirst()))
    binder.fill(result, into: &options)

    switch options.mode {
    case .fileLockTest:
        guard let fileLockOptions = options.fileLockOptions else { break }
        try fileLockTest(
            cacheDir: fileLockOptions.cacheDir,
            path: fileLockOptions.path,
            content: fileLockOptions.content)
    case .interruptHandlerTest:
        let handlerTest = try HandlerTest(options.temporaryFile!)
        handlerTest.run()
    case .pathArgumentTest:
        print(options.absolutePath!.asString)
    case .help:
        parser.printUsage(on: stdoutStream)
    }
} catch {
    stderrStream <<< String(describing: error) <<< "\n"
    stderrStream.flush()
    POSIX.exit(1)
}
