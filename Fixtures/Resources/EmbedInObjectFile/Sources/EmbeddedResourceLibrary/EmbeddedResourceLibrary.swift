public func embeddedResourceText() -> String {
    precondition(PackageResources.empty_bin.isEmpty)
    return PackageResources.best_txt.withUnsafeBufferPointer {
        String(decoding: $0, as: UTF8.self)
    }
}
