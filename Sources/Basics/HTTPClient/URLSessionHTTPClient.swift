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
import struct TSCUtility.Versioning
#if canImport(FoundationNetworking)
// FIXME: this brings OpenSSL dependency on Linux and needs to be replaced with `swift-server/async-http-client` package
import FoundationNetworking
#endif

final class URLSessionHTTPClient: Sendable {
    private let dataSession: URLSession
    private let downloadSession: URLSession
    private let dataTaskManager: DataTaskManager
    private let downloadTaskManager: DownloadTaskManager

    init(configuration: URLSessionConfiguration = .default) {
        let dataDelegateQueue = OperationQueue()
        dataDelegateQueue.name = "org.swift.swiftpm.urlsession-http-client-data-delegate"
        dataDelegateQueue.maxConcurrentOperationCount = 1
        self.dataTaskManager = DataTaskManager()
        self.dataSession = URLSession(
            configuration: configuration,
            delegate: self.dataTaskManager,
            delegateQueue: dataDelegateQueue
        )

        let downloadDelegateQueue = OperationQueue()
        downloadDelegateQueue.name = "org.swift.swiftpm.urlsession-http-client-download-delegate"
        downloadDelegateQueue.maxConcurrentOperationCount = 1
        self.downloadTaskManager = DownloadTaskManager()
        self.downloadSession = URLSession(
            configuration: configuration,
            delegate: self.downloadTaskManager,
            delegateQueue: downloadDelegateQueue
        )
    }

    deinit {
        dataSession.finishTasksAndInvalidate()
        downloadSession.finishTasksAndInvalidate()
    }

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
                let dataTask = self.dataSession.dataTask(with: urlRequest)
                self.dataTaskManager.register(
                    task: dataTask,
                    urlRequest: urlRequest,
                    authorizationProvider: request.options.authorizationProvider,
                    progress: progress,
                    completion: { continuation.resume(with: $0) }
                )
                task = dataTask
            case .download(_, let destination):
                let downloadTask = self.downloadSession.downloadTask(with: urlRequest)
                self.downloadTaskManager.register(
                    task: downloadTask,
                    urlRequest: urlRequest,
                    // FIXME: always using synchronous filesystem, because `URLSessionDownloadDelegate`
                    // needs temporary files to moved out of temporary locations synchronously in delegate callbacks.
                    fileSystem: localFileSystem,
                    destination: destination,
                    progress: progress,
                    completion: { continuation.resume(with: $0) }
                )
                task = downloadTask
            }
            task.resume()
        }
    }

    @Sendable
    public func execute(
        _ request: LegacyHTTPClient.Request,
        progress: LegacyHTTPClient.ProgressHandler?,
        completion: @escaping LegacyHTTPClient.CompletionHandler
    ) {
        let urlRequest = URLRequest(request)
        let task: URLSessionTask
        switch request.kind {
        case .generic:
            let dataTask = self.dataSession.dataTask(with: urlRequest)
            self.dataTaskManager.register(
                task: dataTask,
                urlRequest: urlRequest,
                authorizationProvider: request.options.authorizationProvider,
                progress: progress,
                completion: completion
            )
            task = dataTask
        case .download(let fileSystem, let destination):
            let downloadTask = self.downloadSession.downloadTask(with: urlRequest)
            self.downloadTaskManager.register(
                task: downloadTask,
                urlRequest: urlRequest,
                fileSystem: fileSystem,
                destination: destination,
                progress: progress,
                completion: completion
            )
            task = downloadTask
        }
        task.resume()
    }
}

private final class DataTaskManager: NSObject, URLSessionDataDelegate {
    private let tasks = ThreadSafeKeyValueStore<Int, DataTask>()

    func register(
        task: URLSessionDataTask,
        urlRequest: URLRequest,
        authorizationProvider: LegacyHTTPClientConfiguration.AuthorizationProvider?,
        progress: LegacyHTTPClient.ProgressHandler?,
        completion: @escaping LegacyHTTPClient.CompletionHandler
    ) {
        self.tasks[task.taskIdentifier] = DataTask(
            task: task,
            progressHandler: progress,
            dataTaskManager: self,
            completionHandler: completion,
            authorizationProvider: authorizationProvider
        )
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard var task = self.tasks[dataTask.taskIdentifier] else {
            return completionHandler(.cancel)
        }
        task.response = response as? HTTPURLResponse
        task.expectedContentLength = response.expectedContentLength
        self.tasks[dataTask.taskIdentifier] = task

        do {
            try task.progressHandler?(0, response.expectedContentLength)
            completionHandler(.allow)
        } catch {
            completionHandler(.cancel)
        }
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard var task = self.tasks[dataTask.taskIdentifier] else {
            return
        }
        if task.buffer != nil {
            task.buffer?.append(data)
        } else {
            task.buffer = data
        }
        self.tasks[dataTask.taskIdentifier] = task

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
        if let error {
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

    struct DataTask: Sendable {
        let task: URLSessionDataTask
        let completionHandler: LegacyHTTPClient.CompletionHandler
        /// A strong reference to keep the `DataTaskManager` alive so it can handle the callbacks from the
        /// `URLSession`.
        ///
        /// See comment on `WeakDataTaskManager`.
        let dataTaskManager: DataTaskManager
        let progressHandler: LegacyHTTPClient.ProgressHandler?
        let authorizationProvider: LegacyHTTPClientConfiguration.AuthorizationProvider?

        var response: HTTPURLResponse?
        var expectedContentLength: Int64?
        var buffer: Data?

        init(
            task: URLSessionDataTask,
            progressHandler: LegacyHTTPClient.ProgressHandler?,
            dataTaskManager: DataTaskManager,
            completionHandler: @escaping LegacyHTTPClient.CompletionHandler,
            authorizationProvider: LegacyHTTPClientConfiguration.AuthorizationProvider?
        ) {
            self.task = task
            self.progressHandler = progressHandler
            self.dataTaskManager = dataTaskManager
            self.completionHandler = completionHandler
            self.authorizationProvider = authorizationProvider
        }
    }
}

private final class DownloadTaskManager: NSObject, URLSessionDownloadDelegate {
    private let tasks = ThreadSafeKeyValueStore<Int, DownloadTask>()

    func register(
        task: URLSessionDownloadTask,
        urlRequest: URLRequest,
        fileSystem: FileSystem,
        destination: AbsolutePath,
        progress: LegacyHTTPClient.ProgressHandler?,
        completion: @escaping LegacyHTTPClient.CompletionHandler
    ) {
        self.tasks[task.taskIdentifier] = DownloadTask(
            task: task,
            fileSystem: fileSystem,
            destination: destination,
            downloadTaskManager: self,
            progressHandler: progress,
            completionHandler: completion
        )
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
        guard var task = self.tasks[downloadTask.taskIdentifier] else {
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
            self.tasks[downloadTask.taskIdentifier] = task
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
            if let error {
                throw HTTPClientError.downloadError(error.interpolationDescription)
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

    struct DownloadTask: Sendable {
        let task: URLSessionDownloadTask
        let fileSystem: FileSystem
        let destination: AbsolutePath
        let progressHandler: LegacyHTTPClient.ProgressHandler?
        let completionHandler: LegacyHTTPClient.CompletionHandler

        var moveFileError: Error?

        init(
            task: URLSessionDownloadTask,
            fileSystem: FileSystem,
            destination: AbsolutePath,
            downloadTaskManager: DownloadTaskManager,
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
