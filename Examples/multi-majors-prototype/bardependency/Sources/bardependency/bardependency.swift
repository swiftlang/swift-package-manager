import Alamofire

public struct BarService {
    public var name: String

    public init(name: String) {
        self.name = name
    }

    /// Alamofire 5: HTTPHeaders is a struct, and the defaults live on HTTPHeaders.default.
    public func defaultHeaders() -> HTTPHeaders {
        HTTPHeaders.default
    }

    public func acceptEncoding() -> String? {
        HTTPHeaders.default["Accept-Encoding"]
    }

    /// Module-qualified name of an Alamofire 5 type. Session does not exist in Alamofire 4.
    public func alamofireTypeName() -> String {
        String(reflecting: Session.self)
    }}
