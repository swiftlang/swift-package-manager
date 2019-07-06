import Dispatch
import Foundation

import Basic
import SPMLibc
import SPMUtility

/// Execute the file lock test.
///
/// - Parameters:
///   - cacheDir: The cache directory where lock file should be created.
///   - path: Path to a file which will be mutated.
///   - content: Integer that should be added in that file.
func fileLockTest(name: String, lockDirectory: AbsolutePath, contentPath: AbsolutePath, content: Int) throws {
    let lock = FileLock(name: name, in: lockDirectory)
    try lock.withLock {
        // Get thr current contents of the file if any.
        let currentData: Int
        if localFileSystem.exists(contentPath) {
            currentData = Int(try localFileSystem.readFileContents(contentPath).description) ?? 0
        } else {
            currentData = 0
        }
        // Sum and write back to file.
        try localFileSystem.writeFileContents(contentPath, bytes: ByteString(encodingAsUTF8: String(currentData + content)))
    }
}

func fileLockLock(name: String, in directory: AbsolutePath, duration sleepValue: Int) throws {
    let lock = FileLock(name: name, in: directory)
    try lock.lock()
    SPMLibc.sleep(UInt32(sleepValue))
    lock.unlock()
}

class HandlerTest {
    let interruptHandler: InterruptHandler

    init(_ file: AbsolutePath) throws {
        interruptHandler = try InterruptHandler {
            print("Hello from handler!")
            SPMLibc.exit(0)
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
    case fileLockLock
    case interruptHandlerTest
    case pathArgumentTest
    case help
}

struct Options {
    struct FileLockOptions {
        var name: String?
        var lockDirectory: AbsolutePath?
        var contentPath: AbsolutePath?
        var value: Int?
    }
    var fileLockOptions = FileLockOptions()
    var temporaryFile: AbsolutePath?
    var absolutePath: AbsolutePath?
    var mode = Mode.help
}

do {
    let binder = ArgumentBinder<Options>()

    let parser = ArgumentParser(
        usage: "subcommand",
        overview: "Test support executable")

    let fileLockTestParser = parser.add(subparser: Mode.fileLockTest.rawValue, overview: "Execute the file lock test")
    binder.bind(positional: fileLockTestParser.add(positional: "lock name", kind: String.self, usage: "File lock name"), to: { (options, value) in
        options.fileLockOptions.name = value
    })
    binder.bind(positional: fileLockTestParser.add(positional: "lock directory", kind: String.self, usage: "Path to lock directory"), to: { (options, value) in
        options.fileLockOptions.lockDirectory = AbsolutePath(value)
    })
    binder.bind(positional: fileLockTestParser.add(positional: "file path", kind: String.self, usage: "Path of the file to mutate"), to: { (options, value) in
        options.fileLockOptions.contentPath = AbsolutePath(value)
    })
    binder.bind(positional: fileLockTestParser.add(positional: "content", kind: Int.self, usage: "Contents to write in the file"), to: { (options, value) in
        options.fileLockOptions.value = value
    })

    let fileLockLockParser = parser.add(subparser: Mode.fileLockLock.rawValue, overview: "Execute the file lock test")
    binder.bind(positional: fileLockLockParser.add(positional: "lock name", kind: String.self, usage: "File lock name"), to: { (options, value) in
        options.fileLockOptions.name = value
    })
    binder.bind(positional: fileLockLockParser.add(positional: "lock directory", kind: String.self, usage: "Path to lock directory"), to: { (options, value) in
        options.fileLockOptions.lockDirectory = AbsolutePath(value)
    })
    binder.bind(positional: fileLockLockParser.add(positional: "duration", kind: Int.self, usage: "Lock duration"), to: { (options, value) in
        options.fileLockOptions.value = value
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
    try binder.fill(parseResult: result, into: &options)

    switch options.mode {
    case .fileLockTest:
        let fileLockOptions = options.fileLockOptions
        guard let name = fileLockOptions.name, let lockDirectory = fileLockOptions.lockDirectory,
            let contentPath = fileLockOptions.contentPath, let value = fileLockOptions.value else { break }
        try fileLockTest(
            name: name,
            lockDirectory: lockDirectory,
            contentPath: contentPath,
            content: value)
    case .fileLockLock:
        let fileLockOptions = options.fileLockOptions
        guard let name = fileLockOptions.name, let lockDirectory = fileLockOptions.lockDirectory,
            let value = fileLockOptions.value else { break }
        try fileLockLock(name: name,
                         in: lockDirectory,
                         duration: value)
    case .interruptHandlerTest:
        let handlerTest = try HandlerTest(options.temporaryFile!)
        handlerTest.run()
    case .pathArgumentTest:
        print(options.absolutePath!.pathString)
    case .help:
        parser.printUsage(on: stdoutStream)
    }
} catch {
    stderrStream <<< String(describing: error) <<< "\n"
    stderrStream.flush()
    exit(1)
}
