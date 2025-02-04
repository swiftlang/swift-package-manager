public func getPlatform() throws -> String {
    #if os(Windows)
    return "Windows"
    #else
        #if os(macOS)
        return "macOS"
        #else
            #if os(linux)
                return "Linux"
            #else
                return "Unknown platform"
            #endif
        #endif
    #endif
}


public protocol MyProtocol {
    static var name: String { get }
}