# ``PackageDescription/Package/Dependency``

## Topics

### Creating a package dependency from a URL

- ``package(url:from:)``
- ``package(url:from:traits:)``
- ``package(url:_:)-2ys47``
- ``package(url:_:traits:)-(_,Range<Version>,_)``
- ``package(url:_:)-1r6rc``
- ``package(url:_:traits:)-(_,ClosedRange<Version>,_)``
- ``package(url:branch:)``
- ``package(url:branch:traits:)``
- ``package(url:revision:)``
- ``package(url:revision:traits:)``
- ``package(url:exact:)``
- ``package(url:exact:traits:)``

### Creating a package dependency from a registry

- ``package(id:from:)``
- ``package(id:from:traits:)``
- ``package(id:_:)-(_,Range<Version>)``
- ``package(id:_:traits:)-(_,Range<Version>,_)``
- ``package(id:_:)-(_,ClosedRange<Version>)``
- ``package(id:_:traits:)-(_,ClosedRange<Version>,_)``
- ``package(id:exact:)``
- ``package(id:exact:traits:)``

### Creating a local dependency

- ``package(name:path:)``
- ``package(name:path:traits:)``
- ``package(path:)``
- ``package(path:traits:)``

### Declaring Requirements

- ``traits``
- ``Trait``
- ``RegistryRequirement``
- ``SourceControlRequirement``
- ``requirement-swift.property``
- ``Requirement-swift.enum``

### Describing a Package Dependency

- ``kind-swift.property``
- ``Kind``
- ``Version``
- ``name``
- ``url``

### Deprecated methods

- ``package(name:url:_:)-(String?,_,_)``
- ``package(name:url:_:)-(_,_,Range<Version>)``
- ``package(name:url:_:)-(_,_,ClosedRange<Version>)``
- ``package(name:url:branch:)``
- ``package(name:url:from:)``
- ``package(name:url:revision:)``
- ``package(url:_:)-(_,Package.Dependency.Requirement)``
- ``name``
- ``url``
