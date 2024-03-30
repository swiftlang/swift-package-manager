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

/// A weak wrapper around `DataTaskManager` that conforms to `URLSessionDataDelegate`.
///
/// This ensures that we don't get a retain cycle between `DataTaskManager.session` -> `URLSession.delegate` -> `DataTaskManager`.
///
/// The `DataTaskManager` is being kept alive by a reference from all `DataTask`s that it manages. Once all the
/// `DataTasks` have finished and are deallocated, `DataTaskManager` will get deinitialized, which invalidates the
/// session, which then lets go of `WeakDataTaskManager`.
private class WeakDataTaskManager: NSObject, URLSessionDataDelegate {
    private weak var dataTaskManager: DataTaskManager?

    init(_ dataTaskManager: DataTaskManager? = nil) {
        self.dataTaskManager = dataTaskManager
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        dataTaskManager?.urlSession(
            session,
            dataTask: dataTask,
            didReceive: response,
            completionHandler: completionHandler
        )
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        dataTaskManager?.urlSession(session, dataTask: dataTask, didReceive: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        dataTaskManager?.urlSession(session, task: task, didCompleteWithError: error)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        dataTaskManager?.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: request,
            completionHandler: completionHandler
        )
    }
}

private class DataTaskManager {
    private var tasks = ThreadSafeKeyValueStore<Int, DataTask>()
    private let delegateQueue: OperationQueue
    private var session: URLSession!

    public init(configuration: URLSessionConfiguration) {
        self.delegateQueue = OperationQueue()
        self.delegateQueue.name = "org.swift.swiftpm.urlsession-http-client-data-delegate"
        self.delegateQueue.maxConcurrentOperationCount = 1
        self.session = URLSession(configuration: configuration, delegate: WeakDataTaskManager(self), delegateQueue: self.delegateQueue)
    }

    deinit {
        session.finishTasksAndInvalidate()
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
            dataTaskManager: self,
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

/// This uses the same pattern as `WeakDataTaskManager`. See comment on that type.
private class WeakDownloadTaskManager: NSObject, URLSessionDownloadDelegate {
    private weak var downloadTaskManager: DownloadTaskManager?

    init(_ downloadTaskManager: DownloadTaskManager? = nil) {
      self.downloadTaskManager = downloadTaskManager
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        downloadTaskManager?.urlSession(
            session,
            downloadTask: downloadTask,
            didWriteData: bytesWritten,
            totalBytesWritten: totalBytesWritten,
            totalBytesExpectedToWrite: totalBytesExpectedToWrite
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        downloadTaskManager?.urlSession(session, downloadTask: downloadTask, didFinishDownloadingTo: location)
    }

    func urlSession(
        _ session: URLSession,
        task downloadTask: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        downloadTaskManager?.urlSession(session, task: downloadTask, didCompleteWithError: error)
    }
}

private class DownloadTaskManager {
    private var tasks = ThreadSafeKeyValueStore<Int, DownloadTask>()
    private let delegateQueue: OperationQueue
    private var session: URLSession!

    init(configuration: URLSessionConfiguration) {
        self.delegateQueue = OperationQueue()
        self.delegateQueue.name = "org.swift.swiftpm.urlsession-http-client-download-delegate"
        self.delegateQueue.maxConcurrentOperationCount = 1
        self.session = URLSession(configuration: configuration, delegate: WeakDownloadTaskManager(self), delegateQueue: self.delegateQueue)
    }

    deinit {
        session.finishTasksAndInvalidate()
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
            downloadTaskManager: self,
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
        /// A strong reference to keep the `DownloadTaskManager` alive so it can handle the callbacks from the
        /// `URLSession`.
        ///
        /// See comment on `WeakDownloadTaskManager`.
        private let downloadTaskManager: DownloadTaskManager
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
            self.downloadTaskManager = downloadTaskManager
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
