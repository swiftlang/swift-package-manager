# Swift Package Manager as a library

Include Swift Package Manager as a dependency in your Swift package.

## Overview

> Warning: **The libSwiftPM API is _unstable_ and may change at any time.**

Swift Package Manager has a library based architecture and the top-level library product is called `libSwiftPM`.
Other packages can add SwiftPM as a package dependency and create powerful custom build tools on top of `libSwiftPM`.

A subset of `libSwiftPM` that includes only the data model (without the package manager's build system) is available as `libSwiftPMDataModel`.
Any one client should depend on one or the other, but not both.
