

import Foundation
import struct TSCUtility.Versioning
#if canImport(FoundationNetworking)
// FIXME: this brings OpenSSL dependency on Linux
// need to decide how to best deal with that
import FoundationNetworking
#endif

public final class URLSessionHTTPClient: NSObject {
    public var configuration: HTTPClientConfiguration = .init()

    private var session: URLSession!
    private var taskDelegates: [URLSessionTask: TaskDelegate] = [:]

    final class TaskDelegate: NSObject {
        private let configuration: HTTPClientConfiguration
        private let callback: (Result<HTTPClient.Response, Error>) -> Void
        private var accumulatedData: Data = Data()

        required init(configuration: HTTPClientConfiguration, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) {
            self.configuration = configuration
            self.callback = callback
        }
    }

    public required init(configuration: URLSessionConfiguration = .default) {
        super.init()
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
}

extension URLSessionHTTPClient: HTTPClientProtocol {
    public func execute(_ request: HTTPClient.Request, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) {
        let task = session.dataTask(with: request.urlRequest())
        taskDelegates[task] = TaskDelegate(configuration: configuration, callback: callback)

        task.resume()
    }
}

extension URLSessionHTTPClient: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void)
    {
        guard let delegate = taskDelegates[task] else {
            return completionHandler(request)
        }

        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request, completionHandler: completionHandler)
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?)
    {
        guard let delegate = taskDelegates[task] else { return }
        defer { taskDelegates[task] = nil }

        delegate.urlSession(session, task: task, didCompleteWithError: error)
    }

    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           didReceive data: Data)
    {
        guard let delegate = taskDelegates[dataTask] else { return }
        delegate.urlSession(session, dataTask: dataTask, didReceive: data)
    }
}


extension URLSessionHTTPClient.TaskDelegate: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void)
    {
        completionHandler(configuration.followRedirects ? request : nil)
    }

    public func urlSession(_ session: URLSession,
                           task: URLSessionTask,
                           didCompleteWithError error: Error?)
    {
        if let error = error {
            configuration.callbackQueue.async {
                self.callback(.failure(error))
            }
        } else if let response = task.response as? HTTPURLResponse {
            let body = accumulatedData.isEmpty ? nil : accumulatedData
            configuration.callbackQueue.async {
                self.callback(.success(response.response(body: body)))
            }
        } else {
            configuration.callbackQueue.async {
                self.callback(.failure(HTTPClientError.invalidResponse))
            }
        }
    }

    public func urlSession(_ session: URLSession,
                           dataTask: URLSessionDataTask,
                           didReceive data: Data)
    {
        accumulatedData.append(data)
    }
}

// MARK: -

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
