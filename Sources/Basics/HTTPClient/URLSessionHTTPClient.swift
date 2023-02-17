//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift open source project
//
// Copyright (c) 2020-2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See http://swift.org/LICENSE.txt for license information
// See http://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import _Concurrency
import Foundation
import TSCBasic
import struct TSCUtility.Versioning
#if canImport(FoundationNetworking)
// FIXME: this brings OpenSSL dependency on Linux
// need to decide how to best deal with that
import FoundationNetworking
#endif

final class URLSessionHTTPClient {
    private let dataTaskManager: DataTaskManager
    private let downloadTaskManager: DownloadTaskManager
    private let uploadTaskManager: UploadTaskManager

    init(configuration: URLSessionConfiguration = .default) {
        self.dataTaskManager = DataTaskManager(configuration: configuration)
        self.downloadTaskManager = DownloadTaskManager(configuration: configuration)
        self.uploadTaskManager = UploadTaskManager(configuration: configuration)
    }

    #if swift(>=5.5.2)

    @Sendable
    func execute(
        _ request: HTTPClient.Request,
        progress: HTTPClient.ProgressHandler? = nil
    ) async throws -> LegacyHTTPClient.Response {
        try await withCheckedThrowingContinuation { continuation in
            let urlRequest = URLRequest(request)
            let task: URLSessionTask
            switch request.kind {
            case .generic:
                task = self.dataTaskManager.makeTask(
                    urlRequest: urlRequest,
                    authorizationProvider: request.options.authorizationProvider,
                    progress: progress,
                    completion: continuation.resume(with:)
                )
            case .download(_, let destination):
                task = self.downloadTaskManager.makeTask(
                    urlRequest: urlRequest,
                    // FIXME: always using a synchronous filesystem, because `URLSessionDownloadDelegate`
                    // needs temporary files to moved out of temporary locations synchronously in delegate callbacks.
                    fileSystem: localFileSystem,
                    destination: destination,
                    progress: progress,
                    completion: continuation.resume(with:)
                )
            }
            task.resume()
        }
    }

    #endif

    public func execute(
        _ request: LegacyHTTPClient.Request,
        progress: LegacyHTTPClient.ProgressHandler?,
        completion: @escaping LegacyHTTPClient.CompletionHandler
    ) {
        do {
            let urlRequest = URLRequest(request)
            let task: URLSessionTask
            switch request.kind {
            case .generic:
                task = self.dataTaskManager.makeTask(
                    urlRequest: urlRequest,
                    authorizationProvider: request.options.authorizationProvider,
                    progress: progress,
                    completion: completion
                )
            case .download(let fileSystem, let destination):
                task = self.downloadTaskManager.makeTask(
                    urlRequest: urlRequest,
                    fileSystem: fileSystem,
                    destination: destination,
                    progress: progress,
                    completion: completion
                )
            case .upload(_, let streamProvider):
                task = try self.uploadTaskManager.makeTask(
                    urlRequest: urlRequest,
                    streamProvider: streamProvider,
                    progress: progress,
                    completion: completion
                )
            }
            task.resume()
        } catch {
            completion(.failure(error))
        }
    }
}

private class DataTaskManager: NSObject, URLSessionDataDelegate {
    private var tasks = ThreadSafeKeyValueStore<Int, DataTask>()
    private let delegateQueue: OperationQueue
    private var session: URLSession!

    public init(configuration: URLSessionConfiguration) {
        self.delegateQueue = OperationQueue()
        self.delegateQueue.name = "org.swift.swiftpm.urlsession-http-client-data-delegate"
        self.delegateQueue.maxConcurrentOperationCount = 1
        super.init()
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: self.delegateQueue)
    }

    func makeTask(
        urlRequest: URLRequest,
        authorizationProvider: LegacyHTTPClientConfiguration.AuthorizationProvider?,
        progress: LegacyHTTPClient.ProgressHandler?,
        completion: @escaping LegacyHTTPClient.CompletionHandler
    ) -> URLSessionDataTask {
        let task = self.session.dataTask(with: urlRequest)
        self.tasks[task.taskIdentifier] = DataTask(
            task: task,
            progressHandler: progress,
            completionHandler: completion,
            authorizationProvider: authorizationProvider
        )
        return task
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let task = self.tasks[dataTask.taskIdentifier] else {
            return completionHandler(.cancel)
        }
        task.response = response as? HTTPURLResponse
        task.expectedContentLength = response.expectedContentLength
        do {
            try task.progressHandler?(0, response.expectedContentLength)
            completionHandler(.allow)
        } catch {
            completionHandler(.cancel)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let task = self.tasks[dataTask.taskIdentifier] else {
            return
        }
        if task.buffer != nil {
            task.buffer?.append(data)
        } else {
            task.buffer = data
        }

        do {
            // safe since created in the line above
            try task.progressHandler?(Int64(task.buffer?.count ?? 0), task.expectedContentLength)
        } catch {
            task.task.cancel()
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let task = self.tasks.removeValue(forKey: task.taskIdentifier) else {
            return
        }
        if let error = error {
            task.completionHandler(.failure(error))
        } else if let response = task.response {
            task.completionHandler(.success(response.response(body: task.buffer)))
        } else {
            task.completionHandler(.failure(HTTPClientError.invalidResponse))
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Don't remove task from dictionary because we want to resume it later
        guard let task = self.tasks[task.taskIdentifier] else {
            return
        }

        var request = request
        // Set `Authorization` header for the redirected request
        if let redirectURL = request.url, let authorization = task.authorizationProvider?(redirectURL),
           request.value(forHTTPHeaderField: "Authorization") == nil
        {
            request.addValue(authorization, forHTTPHeaderField: "Authorization")
        }

        completionHandler(request)
    }

    class DataTask {
        let task: URLSessionDataTask
        let completionHandler: LegacyHTTPClient.CompletionHandler
        let progressHandler: LegacyHTTPClient.ProgressHandler?
        let authorizationProvider: LegacyHTTPClientConfiguration.AuthorizationProvider?

        var response: HTTPURLResponse?
        var expectedContentLength: Int64?
        var buffer: Data?

        init(
            task: URLSessionDataTask,
            progressHandler: LegacyHTTPClient.ProgressHandler?,
            completionHandler: @escaping LegacyHTTPClient.CompletionHandler,
            authorizationProvider: LegacyHTTPClientConfiguration.AuthorizationProvider?
        ) {
            self.task = task
            self.progressHandler = progressHandler
            self.completionHandler = completionHandler
            self.authorizationProvider = authorizationProvider
        }
    }
}

private class DownloadTaskManager: NSObject, URLSessionDownloadDelegate {
    private var tasks = ThreadSafeKeyValueStore<Int, DownloadTask>()
    private let delegateQueue: OperationQueue
    private var session: URLSession!

    init(configuration: URLSessionConfiguration) {
        self.delegateQueue = OperationQueue()
        self.delegateQueue.name = "org.swift.swiftpm.urlsession-http-client-download-delegate"
        self.delegateQueue.maxConcurrentOperationCount = 1
        super.init()
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: self.delegateQueue)
    }

    func makeTask(
        urlRequest: URLRequest,
        fileSystem: FileSystem,
        destination: AbsolutePath,
        progress: LegacyHTTPClient.ProgressHandler?,
        completion: @escaping LegacyHTTPClient.CompletionHandler
    ) -> URLSessionDownloadTask {
        let task = self.session.downloadTask(with: urlRequest)
        self.tasks[task.taskIdentifier] = DownloadTask(
            task: task,
            fileSystem: fileSystem,
            destination: destination,
            progressHandler: progress,
            completionHandler: completion
        )
        return task
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let task = self.tasks[downloadTask.taskIdentifier] else {
            return
        }

        let totalBytesToDownload = totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown ?
            totalBytesExpectedToWrite : nil

        do {
            try task.progressHandler?(totalBytesWritten, totalBytesToDownload)
        } catch {
            task.task.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let task = self.tasks[downloadTask.taskIdentifier] else {
            return
        }

        do {
            let path = try AbsolutePath(validating: location.path)

            // Always using synchronous `localFileSystem` here since `URLSession` requires temporary `location`
            // to be moved from synchronously. Otherwise the file will be immediately cleaned up after returning
            // from this delegate method.
            try task.fileSystem.move(from: path, to: task.destination)
        } catch {
            task.moveFileError = error
        }
    }

    public func urlSession(
        _ session: URLSession,
        task downloadTask: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let task = self.tasks.removeValue(forKey: downloadTask.taskIdentifier) else {
            return
        }

        do {
            if let error = error {
                throw HTTPClientError.downloadError("\(error)")
            } else if let error = task.moveFileError {
                throw error
            } else if let response = downloadTask.response as? HTTPURLResponse {
                task.completionHandler(.success(response.response(body: nil)))
            } else {
                throw HTTPClientError.invalidResponse
            }
        } catch {
            task.completionHandler(.failure(error))
        }
    }

    class DownloadTask {
        let task: URLSessionDownloadTask
        let fileSystem: FileSystem
        let destination: AbsolutePath
        let completionHandler: LegacyHTTPClient.CompletionHandler
        let progressHandler: LegacyHTTPClient.ProgressHandler?

        var moveFileError: Error?

        init(
            task: URLSessionDownloadTask,
            fileSystem: FileSystem,
            destination: AbsolutePath,
            progressHandler: LegacyHTTPClient.ProgressHandler?,
            completionHandler: @escaping LegacyHTTPClient.CompletionHandler
        ) {
            self.task = task
            self.fileSystem = fileSystem
            self.destination = destination
            self.progressHandler = progressHandler
            self.completionHandler = completionHandler
        }
    }
}

private class UploadTaskManager: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
    private var tasks = ThreadSafeKeyValueStore<Int, UploadTask>()
    private let sessionDelegateQueue: DispatchQueue
    private let sessionDelegateOperationQueue: OperationQueue
    private var session: URLSession!

    init(configuration: URLSessionConfiguration) {
        self.sessionDelegateQueue = DispatchQueue(label: "org.swift.swiftpm.urlsession-http-client-upload-delegate")
        self.sessionDelegateOperationQueue = OperationQueue()
        self.sessionDelegateOperationQueue.underlyingQueue = self.sessionDelegateQueue
        self.sessionDelegateOperationQueue.name = self.sessionDelegateQueue.label
        self.sessionDelegateOperationQueue.maxConcurrentOperationCount = 1
        super.init()
        self.session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: self.sessionDelegateOperationQueue
        )
    }

    func makeTask(
        urlRequest: URLRequest,
        streamProvider: @escaping () throws -> LegacyHTTPClientRequest.UploadData?,
        progress: LegacyHTTPClient.ProgressHandler?,
        completion: @escaping LegacyHTTPClient.CompletionHandler
    ) throws -> URLSessionUploadTask {
        let task = self.session.uploadTask(withStreamedRequest: urlRequest)
        self.tasks[task.taskIdentifier] = try UploadTask(
            underlying: task,
            streamProvider: streamProvider,
            progressHandler: progress,
            completionHandler: completion
        )
        return task
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        needNewBodyStream completionHandler: @escaping @Sendable (InputStream?) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(self.sessionDelegateQueue))

        guard let task = self.tasks[task.taskIdentifier] else {
            return
        }
        completionHandler(task.inputStream)
        // FIXME: serious hack here
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 10000.0))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        dispatchPrecondition(condition: .onQueue(self.sessionDelegateQueue))

        guard let task = self.tasks[task.taskIdentifier] else {
            return
        }
        task.progress(totalBytesSent: totalBytesSent, totalBytesExpectedToSend: totalBytesExpectedToSend)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        dispatchPrecondition(condition: .onQueue(self.sessionDelegateQueue))

        guard let task = self.tasks.removeValue(forKey: task.taskIdentifier) else {
            return
        }

        do {
            if let error = error as? HTTPClientError {
                throw error
            } else if let error = error {
                throw HTTPClientError.uploadError("\(error)")
            } else if let response = task.response {
                task.complete(with: .success(response))
            } else {
                throw HTTPClientError.invalidResponse
            }
        } catch {
            task.complete(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        dispatchPrecondition(condition: .onQueue(self.sessionDelegateQueue))

        guard let task = self.tasks[dataTask.taskIdentifier] else {
            return
        }

        task.appendResponseBody(data)
    }

    class UploadTask: NSObject, StreamDelegate {
        static let bufferSize = 8 // FIXME: smal buffer for testing

        let underlying: URLSessionUploadTask
        private let streamProvider: () throws -> LegacyHTTPClientRequest.UploadData?
        private let completionHandler: LegacyHTTPClient.CompletionHandler
        private let progressHandler: LegacyHTTPClient.ProgressHandler?
        private var streams: Streams!

        // URLSession APIs are thread safe
        // calls into this are guarded with dispatchPrecondition
        private var responseBuffer: Data?
        // stream events may not be thread safe
        private var streamBuffer: UploadStreamBuffer = .empty
        private let streamBufferLock = NSLock()

        init(
            underlying: URLSessionUploadTask,
            streamProvider: @escaping () throws -> LegacyHTTPClientRequest.UploadData?,
            progressHandler: LegacyHTTPClient.ProgressHandler?,
            completionHandler: @escaping LegacyHTTPClient.CompletionHandler
        ) throws {
            self.underlying = underlying
            self.streamProvider = streamProvider
            self.progressHandler = progressHandler
            self.completionHandler = completionHandler
            super.init()

            // initialize the stream
            var _input: InputStream?
            var _output: OutputStream?

            Stream.getBoundStreams(
                withBufferSize: Self.bufferSize,
                inputStream: &_input,
                outputStream: &_output
            )
            guard let input = _input, let output = _output else {
                throw StringError("Stream.getBoundStreams returned nil streams")
            }

            output.delegate = self
            output.schedule(in: .current, forMode: .default)
            output.open()

            self.streams = Streams(input: input, output: output)
        }

        var inputStream: InputStream {
            self.streams.input
        }

        var outputStream: OutputStream {
            self.streams.output
        }

        var response: HTTPClientResponse? {
            self.underlying.response.flatMap {
                $0 as? HTTPURLResponse
            }.flatMap {
                $0.response(body: self.responseBuffer)
            }
        }

        func appendResponseBody(_ data: Data) {
            if var buffer = self.responseBuffer {
                buffer.append(data)
            } else {
                // copy
                self.responseBuffer = data
            }
        }

        func cancel() {
            self.underlying.cancel()
            self.streams.close()
        }

        func complete(with result: Result<HTTPClientResponse, Error>) {
            self.completionHandler(result)
            self.streams.close()
        }

        func progress(totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            do {
                try self.progressHandler?(totalBytesSent, totalBytesExpectedToSend)
            } catch {
                self.cancel()
            }
        }

        func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
            guard aStream == self.outputStream else {
                return
            }

            // stream events may not be thread safe
            self.streamBufferLock.lock()
            defer { self.streamBufferLock.unlock() }

            do {
                guard !eventCode.contains(.errorOccurred) else {
                    throw HTTPClientError.uploadError("Unknown error occurred: \(eventCode)")
                }

                if eventCode.contains(.hasSpaceAvailable) {
                    let streamBuffer: UploadStreamBuffer

                    switch self.streamBuffer {
                    case .empty:
                        switch try self.streamProvider() {
                        case .chunk(let data):
                            streamBuffer = .data(data)
                        case .stream(let stream):
                            streamBuffer = .stream(stream, .none)
                        case .none:
                            streamBuffer = .empty
                        }
                    case .data(let data):
                        streamBuffer = .data(data)
                    case .stream(let stream, let leftover):
                        streamBuffer = .stream(stream, leftover)
                    }

                    switch streamBuffer {
                    case .data(let data):
                        let totalBytes = data.count
                        let bytesWritten = try data
                            .withUnsafeBytes { (unsafeRawBufferPointer: UnsafeRawBufferPointer) in
                                let unsafeBufferPointer = unsafeRawBufferPointer.bindMemory(to: UInt8.self)
                                guard let unsafePointer = unsafeBufferPointer.baseAddress else {
                                    throw HTTPClientError
                                        .uploadError("Invalid upload state, cannot read upload buffer pointer")
                                }
                                return self.outputStream.write(
                                    unsafePointer,
                                    maxLength: Swift.min(totalBytes, Self.bufferSize)
                                )
                            }
                        if bytesWritten < totalBytes {
                            self.streamBuffer = .data(data.subdata(in: bytesWritten ..< totalBytes))
                        } else if bytesWritten == totalBytes {
                            // done with chunk
                            self.streamBuffer = .empty
                        } else {
                            throw HTTPClientError
                                .uploadError("Invalid upload state: sent too many bytes from data chunk")
                        }
                    case .stream(let inputStream, let leftover):
                        if let leftover = leftover {
                            // write any left over we could not write before
                            let totalBytes = leftover.count
                            let bytesWritten = self.outputStream.write(
                                leftover,
                                maxLength: Swift.min(totalBytes, Self.bufferSize)
                            )
                            if bytesWritten == totalBytes {
                                // continue to read from input stream
                                self.streamBuffer = .stream(inputStream, .none)
                            } else if bytesWritten < totalBytes {
                                // record the unwritten bytes
                                let leftover = leftover[bytesWritten ..< totalBytes]
                                self.streamBuffer = .stream(inputStream, Array(leftover))
                            } else {
                                throw HTTPClientError
                                    .uploadError("Invalid upload state: sent too many bytes from input stream")
                            }
                        } else {
                            // read from input stream
                            inputStream.open()
                            if inputStream.hasBytesAvailable {
                                var buffer = [UInt8](repeating: 0, count: Self.bufferSize)
                                let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)
                                if bytesRead == 0 {
                                    // done with stream
                                    self.streamBuffer = .empty
                                    inputStream.close()
                                } else {
                                    let bytesWritten = self.outputStream.write(
                                        buffer,
                                        maxLength: Swift.min(bytesRead, Self.bufferSize)
                                    )
                                    if bytesWritten == bytesRead {
                                        // read index moves forward
                                        self.streamBuffer = .stream(inputStream, .none)
                                    } else if bytesWritten < bytesRead {
                                        // record the unwritten bytes
                                        let leftover = buffer[bytesWritten ..< bytesRead]
                                        self.streamBuffer = .stream(inputStream, Array(leftover))
                                    } else {
                                        throw HTTPClientError
                                            .uploadError("Invalid upload state: sent too many bytes from input stream")
                                    }
                                }
                            } else {
                                self.streamBuffer = .stream(inputStream, leftover)
                            }
                        }
                    case .empty:
                        self.streams.output.close()
                    }
                }
            } catch {
                self.complete(with: .failure(error))
            }
        }

        public enum UploadStreamBuffer {
            case empty
            case data(Data)
            case stream(InputStream, [UInt8]?)
        }
    }

    private struct Streams {
        let input: InputStream
        let output: OutputStream

        func close() {
            self.input.close()
            self.output.close()
        }
    }
}

extension URLRequest {
    init(_ request: LegacyHTTPClient.Request) {
        self.init(url: request.url)
        self.httpMethod = request.method.string
        request.headers.forEach { header in
            self.addValue(header.value, forHTTPHeaderField: header.name)
        }
        self.httpBody = request.body
        if let interval = request.options.timeout?.timeInterval() {
            self.timeoutInterval = interval
        }
    }

    // For `HTTPClient` to be available we need Swift Concurrency back-deployment.
    #if swift(>=5.5.2)
    init(_ request: HTTPClient.Request) {
        self.init(url: request.url)
        self.httpMethod = request.method.string
        request.headers.forEach { header in
            self.addValue(header.value, forHTTPHeaderField: header.name)
        }
        self.httpBody = request.body
        if let interval = request.options.timeout?.timeInterval() {
            self.timeoutInterval = interval
        }
    }
    #endif
}

extension HTTPURLResponse {
    fileprivate func response(body: Data?) -> HTTPClientResponse {
        let headers = HTTPClientHeaders(self.allHeaderFields.map { header in
            .init(name: "\(header.key)", value: "\(header.value)")
        })
        return HTTPClientResponse(
            statusCode: self.statusCode,
            statusText: Self.localizedString(forStatusCode: self.statusCode),
            headers: headers,
            body: body
        )
    }
}
