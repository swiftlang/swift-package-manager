public func embeddedResourceText() -> String {
    precondition(PackageResources.empty_bin.isEmpty)
    return String(decoding: PackageResources.best_txt, as: UTF8.self)
}
