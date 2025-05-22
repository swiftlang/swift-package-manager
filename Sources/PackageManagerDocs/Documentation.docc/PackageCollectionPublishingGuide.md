# Publishing package collections

Learn how to publish package collections.

## Overview

Package collections can be created and published by anyone. The [swift-package-collection-generator](https://github.com/apple/swift-package-collection-generator) project provides tooling 
intended for package collection publishers:
- [`package-collection-generate`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionGenerator): Generate a package collection given a list of package URLs
- [`package-collection-sign`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionSigner): Sign a package collection
- [`package-collection-validate`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionValidator): Perform basic validations on a package collection
- [`package-collection-diff`](https://github.com/apple/swift-package-collection-generator/tree/main/Sources/PackageCollectionDiff): Compare two package collections to see if their contents are different 
