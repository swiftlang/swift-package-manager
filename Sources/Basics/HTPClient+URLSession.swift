/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import TSCBasic
import struct TSCUtility.Versioning
#if canImport(FoundationNetworking)
// FIXME: this brings OpenSSL dependency on Linux
// need to decide how to best deal with that
import FoundationNetworking
#endif

public struct URLSessionHTTPClient: HTTPClientProtocol {
    private let dataTasksManager: DataTaskManager
    private let downloadsTasksManager: DownloadTaskManager

    public init(configuration: URLSessionConfiguration = .default) {
        self.dataTasksManager = DataTaskManager(configuration: configuration)
        self.downloadsTasksManager = DownloadTaskManager(configuration: configuration)
    }

    public func execute(_ request: HTTPClient.Request, progress: ProgressHandler?, completion: @escaping CompletionHandler) {
        switch request.kind {
        case .generic:
            let task = self.dataTasksManager.makeTask(request: request, progress: progress, completion: completion)
            task.resume()
        case .download(let fileSystem, let destination):
            let task = self.downloadsTasksManager.makeTask(request: request, fileSystem: fileSystem, destination: destination, progress: progress, completion: completion)
            task.resume()
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

    func makeTask(request: HTTPClient.Request, progress: HTTPClient.ProgressHandler?, completion: @escaping HTTPClient.CompletionHandler) -> URLSessionDataTask {
        let task = self.session.dataTask(with: request.urlRequest())
        self.tasks[task.taskIdentifier] = DataTask(task: task, progressHandler: progress, completionHandler: completion)
        return task
    }

    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let task = self.tasks[dataTask.taskIdentifier] else {
            return completionHandler(.cancel)
        }
        task.response = response as? HTTPURLResponse
        task.expectedContentLength = response.expectedContentLength
        task.progressHandler?(0, response.expectedContentLength)
        completionHandler(.allow)
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
        task.progressHandler?(Int64(task.buffer?.count ?? 0), task.expectedContentLength) // safe since created in the line above
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

    class DataTask {
        let task: URLSessionDataTask
        let completionHandler: HTTPClient.CompletionHandler
        let progressHandler: HTTPClient.ProgressHandler?

        var response: HTTPURLResponse?
        var expectedContentLength: Int64?
        var buffer: Data?

        init(task: URLSessionDataTask, progressHandler: HTTPClient.ProgressHandler?, completionHandler: @escaping HTTPClient.CompletionHandler) {
            self.task = task
            self.progressHandler = progressHandler
            self.completionHandler = completionHandler
        }
    }
}

private class DownloadTaskManager: NSObject, URLSessionDownloadDelegate {
    private var tasks = ThreadSafeKeyValueStore<Int, DownloadTask>()
    private let delegateQueue: OperationQueue
    private var session: URLSession!

    public init(configuration: URLSessionConfiguration) {
        self.delegateQueue = OperationQueue()
        self.delegateQueue.name = "org.swift.swiftpm.urlsession-http-client-download-delegate"
        self.delegateQueue.maxConcurrentOperationCount = 1
        super.init()
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: self.delegateQueue)
    }

    func makeTask(request: HTTPClient.Request, fileSystem: FileSystem, destination: AbsolutePath, progress: HTTPClient.ProgressHandler?, completion: @escaping HTTPClient.CompletionHandler) -> URLSessionDownloadTask {
        let task = self.session.downloadTask(with: request.urlRequest())
        self.tasks[task.taskIdentifier] = DownloadTask(task: task, fileSystem: fileSystem, destination: destination, progressHandler: progress, completionHandler: completion)
        return task
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let task = self.tasks[downloadTask.taskIdentifier] else {
            return
        }

        let totalBytesToDownload = totalBytesExpectedToWrite != NSURLSessionTransferSizeUnknown ? totalBytesExpectedToWrite : nil
        task.progressHandler?(totalBytesWritten, totalBytesToDownload)
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: Foundation.URL) {
        guard let task = self.tasks[downloadTask.taskIdentifier] else {
            return
        }

        task.location = location
    }

    public func urlSession(_ session: URLSession, task downloadTask: URLSessionTask, didCompleteWithError error: Error?) {
        guard let task = self.tasks.removeValue(forKey: downloadTask.taskIdentifier) else {
            return
        }

        do {
            if let error = error {
                throw HTTPClientError.downloadError("\(error)")
            } else if let response = downloadTask.response as? HTTPURLResponse {
                if let location = task.location {
                    try task.fileSystem.move(from: AbsolutePath(location.path), to: task.destination)
                }
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
        let completionHandler: HTTPClient.CompletionHandler
        let progressHandler: HTTPClient.ProgressHandler?

        var location: Foundation.URL?

        init(task: URLSessionDownloadTask, fileSystem: FileSystem, destination: AbsolutePath, progressHandler: HTTPClient.ProgressHandler?, completionHandler: @escaping HTTPClient.CompletionHandler) {
            self.task = task
            self.fileSystem = fileSystem
            self.destination = destination
            self.progressHandler = progressHandler
            self.completionHandler = completionHandler
        }
    }
}

extension HTTPClient.Request {
    func urlRequest() -> URLRequest {
        var request = URLRequest(url: self.url)
        request.httpMethod = self.methodString()
        self.headers.forEach { header in
            request.addValue(header.value, forHTTPHeaderField: header.name)
        }
        request.httpBody = self.body
        if let interval = self.options.timeout?.timeInterval() {
            request.timeoutInterval = interval
        }
        return request
    }

    func methodString() -> String {
        switch self.method {
        case .head:
            return "HEAD"
        case .get:
            return "GET"
        case .post:
            return "POST"
        case .put:
            return "PUT"
        case .delete:
            return "DELETE"
        }
    }
}

extension HTTPURLResponse {
    func response(body: Data?) -> HTTPClient.Response {
        let headers = HTTPClientHeaders(self.allHeaderFields.map { header in
            .init(name: "\(header.key)", value: "\(header.value)")
        })
        return HTTPClient.Response(statusCode: self.statusCode,
                                   statusText: Self.localizedString(forStatusCode: self.statusCode),
                                   headers: headers,
                                   body: body)
    }
}
