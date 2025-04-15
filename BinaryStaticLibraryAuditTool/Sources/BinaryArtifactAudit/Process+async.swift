package import Foundation
package import SystemPackage

extension Process {
    @discardableResult
    package static func run(executable: FilePath, arguments: String...) async throws -> CollectedResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable.string)
        process.arguments = Array(arguments)
        let stdout = process.collectData(for: \.standardOutputPipe)
        let stderr = process.collectData(for: \.standardErrorPipe)

        try process.run()

        await withTaskCancellationHandler {
            process.waitUntilExit()
        } onCancel: {
            process.terminate()
        }

        switch process.terminationReason {
        case .exit:
            if process.terminationStatus != 0 {
                throw Err.failed(status: Int(process.terminationStatus))
            }
        case .uncaughtSignal:
            throw Err.signal(code: Int(process.terminationStatus))
        @unknown default:
            preconditionFailure()
        }

        @Sendable func processOutputDataStream(_ stream: AsyncStream<Data>) async -> Data {
            var data = Data()
            for await nextDataElem in stream {
                data.append(nextDataElem)
            }

            return data
        }

        async let maybeOutData = processOutputDataStream(stdout)
        async let maybeErrData = processOutputDataStream(stderr)

        return CollectedResult(
            output: await maybeOutData,
            error: await maybeErrData
        )
    }
}

extension Process {
    enum Err: Error {
        case failed(status: Int)
        case signal(code: Int)
    }

    /// Type-safe accessor for `standardOutput`.
    fileprivate var standardOutputPipe: Pipe? {
        get { standardOutput as? Pipe }
        set { standardOutput = newValue }
    }

    /// Type-safe accessor for `standardError`.
    fileprivate var standardErrorPipe: Pipe? {
        get { standardError as? Pipe }
        set { standardError = newValue }
    }

    /// Attach a pipe to one of the Process objects output file descriptor and return an async sequence of data items as they are read from the pipe.
    fileprivate func collectData(for keyPath: ReferenceWritableKeyPath<Process, Pipe?>) -> AsyncStream<Data> {
        let pipe = Pipe()
        self[keyPath: keyPath] = pipe
        return AsyncStream { continuation in
            pipe.fileHandleForReading.readabilityHandler = { file in
                let data = file.availableData
                guard !data.isEmpty else {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.finish()
                    return
                }

                continuation.yield(data)
            }
        }
    }

    package struct CollectedResult {
        package var output: Data
        package var error: Data
    }
}
