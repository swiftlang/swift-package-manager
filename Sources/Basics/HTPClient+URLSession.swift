

import Foundation
import struct TSCUtility.Versioning
#if canImport(FoundationNetworking)
// FIXME: this brings OpenSSL dependency on Linux
// need to decide how to best deal with that
import FoundationNetworking
#endif

public struct URLSessionHTTPClient: HTTPClientProtocol {
    private let configuration: URLSessionConfiguration

    public init(configuration: URLSessionConfiguration = .default) {
        self.configuration = configuration
    }

    public func execute(_ request: HTTPClient.Request, callback: @escaping (Result<HTTPClient.Response, Error>) -> Void) {
        let session = URLSession(configuration: self.configuration)
        let task = session.dataTask(with: request.urlRequest()) { data, response, error in
            if let error = error {
                callback(.failure(error))
            } else if let response = response as? HTTPURLResponse {
                callback(.success(response.response(body: data)))
            } else {
                callback(.failure(HTTPClientError.invalidResponse))
            }
        }
        task.resume()
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
