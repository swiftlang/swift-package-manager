# PackageDescription Library

This library defines the APIs which are available to `Package.swift` manifests.

The `Package.swift` manifests are currently implemented by using the Swift
interpreter to execute the manifest along with a library search path which
allows the `PackageDescription` library to be imported. This means that this
library needs to be self contained and cannot have other library dependencies
which are not also satisfied by that search path.

This library also needs to be built and made available at runtime. This is
handle through a combination of the manifest `products` features, and logic in
the `Utilities/bootstrap` script which knows how to build the library in such a
way that it can be installed alongside the Swift runtime libraries (in
`lib/swift/pm/`).
