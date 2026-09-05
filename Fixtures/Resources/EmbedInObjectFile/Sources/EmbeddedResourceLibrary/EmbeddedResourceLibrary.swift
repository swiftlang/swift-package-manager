public func embeddedResourceText() throws -> String {
    precondition(PackageResources.empty_bin.isEmpty)
    if #available(macOS 26, *) {
        return String(copying: try UTF8Span(validating: PackageResources.best_txt))
    }
    return PackageResources.best_txt.withUnsafeBufferPointer {
        String(decoding: $0, as: UTF8.self)
    }
}
