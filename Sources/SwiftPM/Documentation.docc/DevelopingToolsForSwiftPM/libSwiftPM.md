# Using SwiftPM as a Library

Build tools on top of SwiftPM

> Warning: The libSwiftPM API is currently _unstable_ and subject to changes without notice.

SwiftPM has a library based architecture and the top-level library product is called `libSwiftPM`. Other packages can add SwiftPM as a package dependency and create powerful custom build tools on top of `libSwiftPM`.

For developers who need only the data model without SwiftPM's build system, a subset called `libSwiftPMDataModel` is available. Project should depend on either `libSwiftPM` or `libSwiftPMDataModel`, but **not** both simultaneously.

The SwiftPM repository contains an [example](https://github.com/swiftlang/swift-package-manager/tree/master/Examples/package-info) that demonstrates the use of
`libSwiftPM` in a Swift package. Use the following commands to run the example
package:

1. Clone the SwiftPM repository:
```bash
git clone https://github.com/swiftlang/swift-package-manager
```

2. Navigate to the example directory:
```bash
cd swift-package-manager/Examples/package-info
```

3. Execute the example:
```bash
swift run
```
