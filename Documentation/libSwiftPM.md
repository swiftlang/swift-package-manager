# libSwiftPM - SwiftPM as a Library

**NOTE: The libSwiftPM API is currently _unstable_ and may change at any time.**

SwiftPM has a library based architecture and the top-level library product is
called `libSwiftPM`. Other packages can add SwiftPM as a package dependency and
create powerful custom build tools on top of `libSwiftPM`.

The SwiftPM repository contains an [example](https://github.com/apple/swift-package-manager/tree/master/Examples/package-info) that demonstrates the use of
`libSwiftPM` in a Swift package. Use the following commands to run the example
package:

```sh
$ git clone https://github.com/apple/swift-package-manager
$ cd swift-package-manager/Examples/package-info
$ make build
$ swift run
```

The Makefile in the example package contains commands to build the runtime
libraries that are required for loading the `Package.swift` manifest files of
Swift packages. The runtime libraries require (re)building only when the SwiftPM
checkout is changed.
