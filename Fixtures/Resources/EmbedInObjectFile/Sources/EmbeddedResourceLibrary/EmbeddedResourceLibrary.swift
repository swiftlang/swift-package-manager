public func embeddedResourceText() -> String {
    precondition(PackageResources.empty_bin.isEmpty)
    precondition(PackageResources.empty_bin.byteCount == 0)
    let bytes: RawSpan = PackageResources.best_txt
    return bytes.withUnsafeBytes {
        String(decoding: $0, as: UTF8.self)
    }
}
