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

    init(configuration: URLSessionConfiguration = .default) {
        self.dataTaskManager = DataTaskManager(configuration: configuration)
        self.downloadTaskManager = DownloadTaskManager(configuration: configuration)
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

    public func execute(
        _ request: LegacyHTTPClient.Request,
        progress: LegacyHTTPClient.ProgressHandler?,
        completion: @escaping LegacyHTTPClient.CompletionHandler
    ) {
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
        }
        task.resume()
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
