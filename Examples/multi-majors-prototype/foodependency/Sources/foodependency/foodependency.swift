import Alamofire

public struct FooService {
    public var name: String
    public var id: Int

    public init(name: String, id: Int) {
        self.name = name
        self.id = id
    }

    /// Alamofire 4: HTTPHeaders is a plain [String: String], and the defaults live on SessionManager.
    public func defaultHeaders() -> [String: String] {
        SessionManager.defaultHTTPHeaders
    }

    public func acceptEncoding() -> String? {
        SessionManager.defaultHTTPHeaders["Accept-Encoding"]
    }

    /// Module-qualified name of an Alamofire 4 type. SessionManager was removed in Alamofire 5.
    public func alamofireTypeName() -> String {
        String(reflecting: SessionManager.self)
    }}
