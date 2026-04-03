# ``PackageCollectionsModel``

Models for creating and publishing package collections.

<!-- swift package --disable-sandbox preview-documentation --target PackageCollectionsModel -->
## Overview

Package collections are JSON documents that group packages for discovery.
The ``PackageCollectionModel`` enum serves as a namespace for the collection format, versioned under ``PackageCollectionModel/V1``.
Use the types in this module to create, encode, and decode package collection documents that conform to the v1.0 schema.

## Topics

### Collection Format

- ``PackageCollectionModel``
- ``PackageCollectionModel/FormatVersion``
- ``PackageCollectionModel/V1``

### Describing a Collection

- ``PackageCollectionModel/V1/Collection``
- ``PackageCollectionModel/V1/Collection/Author``
- ``PackageCollectionModel/V1/Collection/Package``

### Describing Package Versions

- ``PackageCollectionModel/V1/Collection/Package/Version``
- ``PackageCollectionModel/V1/Collection/Package/Version/Manifest``
- ``PackageCollectionModel/V1/Collection/Package/Version/Author``

### Targets and Products

- ``PackageCollectionModel/V1/Target``
- ``PackageCollectionModel/V1/Product``
- ``PackageCollectionModel/V1/ProductType``

### Platforms and Compatibility

- ``PackageCollectionModel/V1/PlatformVersion``
- ``PackageCollectionModel/V1/Platform``
- ``PackageCollectionModel/V1/Compatibility``

### Licensing

- ``PackageCollectionModel/V1/License``

### Signing

- ``PackageCollectionModel/V1/Signer``
- ``PackageCollectionModel/V1/SignedCollection``
- ``PackageCollectionModel/V1/Signature``
