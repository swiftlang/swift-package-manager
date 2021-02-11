/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
 */

import Foundation
import struct TSCUtility.Versioning
#if canImport(FoundationNetworking)
// FIXME: this brings OpenSSL dependency on Linux
// need to decide how to best deal with that
import FoundationNetworking
#endif

public final class URLSessionHTTPClient: NSObject, HTTPClientProtocol {
    private let configuration: URLSessionConfiguration
    private let delegateQueue: OperationQueue
    private var session: URLSession!
    private var tasks = ThreadSafeKeyValueStore<Int, DataTask>()

    public init(configuration: URLSessionConfiguration = .default) {
        self.configuration = configuration
        self.delegateQueue = OperationQueue()
        self.delegateQueue.name = "org.swift.swiftpm.urlsession-http-client"
        self.delegateQueue.maxConcurrentOperationCount = 1
        super.init()
        self.session = URLSession(configuration: self.configuration, delegate: self, delegateQueue: self.delegateQueue)
    }

    public func execute(_ request: HTTPClient.Request, progress: ProgressHandler?, completion: @escaping CompletionHandler) {
        let task = self.session.dataTask(with: request.urlRequest())
        self.tasks[task.taskIdentifier] = DataTask(task: task, progressHandler: progress, completionHandler: completion)
        task.resume()
    }
}

extension URLSessionHTTPClient: URLSessionDataDelegate {
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
        let completionHandler: CompletionHandler
        let progressHandler: ProgressHandler?

        var response: HTTPURLResponse?
        var expectedContentLength: Int64?
        var buffer: Data?

        init(task: URLSessionDataTask, progressHandler: ProgressHandler?, completionHandler: @escaping CompletionHandler) {
            self.task = task
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
