#  ``PackageDescription/Target``

### Test Libraries Targets

Built-in testing libraries, such as Swift Testing and XCTest, are only available for use in certain runtime contexts.
While you can use these within Swift libraries intended for testing, take care so that any such libraries only terminate in test targets, as targets that use Swift Testing or XCTest should never be distributed to end users.
Including testing libraries as a dependency to an executable target, as either a direct or transitive dependency, can cause clients to encounter linking issues.

## Topics

### Naming the Target

- ``name``

### Configuring File Locations

- ``path``
- ``exclude``
- ``sources``
- ``resources``
- ``Resource``
- ``publicHeadersPath``

### Creating a Binary Target

- ``binaryTarget(name:path:)``
- ``binaryTarget(name:url:checksum:)``
- ``url``
- ``checksum``

### Creating a System Library Target

- ``systemLibrary(name:path:pkgConfig:providers:)``
- ``pkgConfig``
- ``providers``

### Creating an Executable Target

- ``executableTarget(name:dependencies:path:exclude:sources:resources:publicHeadersPath:packageAccess:cSettings:cxxSettings:swiftSettings:linkerSettings:plugins:)``
- ``executableTarget(name:dependencies:path:exclude:sources:resources:publicHeadersPath:cSettings:cxxSettings:swiftSettings:linkerSettings:plugins:)``
- ``executableTarget(name:dependencies:path:exclude:sources:resources:publicHeadersPath:cSettings:cxxSettings:swiftSettings:linkerSettings:)``

### Creating a Regular Target

- ``target(name:dependencies:path:exclude:sources:resources:publicHeadersPath:packageAccess:cSettings:cxxSettings:swiftSettings:linkerSettings:plugins:)``
- ``target(name:dependencies:path:exclude:sources:resources:publicHeadersPath:cSettings:cxxSettings:swiftSettings:linkerSettings:plugins:)``
- ``target(name:dependencies:path:exclude:sources:resources:publicHeadersPath:cSettings:cxxSettings:swiftSettings:linkerSettings:)``
- ``target(name:dependencies:path:exclude:sources:publicHeadersPath:cSettings:cxxSettings:swiftSettings:linkerSettings:)``
- ``target(name:dependencies:path:exclude:sources:publicHeadersPath:)``

### Creating a Test Target

- ``testTarget(name:dependencies:path:exclude:sources:resources:packageAccess:cSettings:cxxSettings:swiftSettings:linkerSettings:plugins:)``
- ``testTarget(name:dependencies:path:exclude:sources:resources:cSettings:cxxSettings:swiftSettings:linkerSettings:plugins:)``
- ``testTarget(name:dependencies:path:exclude:sources:resources:cSettings:cxxSettings:swiftSettings:linkerSettings:)``
- ``testTarget(name:dependencies:path:exclude:sources:cSettings:cxxSettings:swiftSettings:linkerSettings:)``
- ``testTarget(name:dependencies:path:exclude:sources:)``

### Creating a Plugin Target

- ``plugin(name:capability:dependencies:path:exclude:sources:packageAccess:)``
- ``pluginCapability-swift.property``
- ``PluginCapability-swift.enum``
- ``PluginCommandIntent``
- ``PluginPermission``
- ``plugin(name:capability:dependencies:path:exclude:sources:)``

### Declaring a Dependency Target

- ``dependencies``
- ``Dependency``
- ``TargetDependencyCondition``

### Configuring the Target

- ``cSettings``
- ``cxxSettings``
- ``swiftSettings``
- ``linkerSettings``
- ``plugins``
- ``BuildConfiguration``
- ``BuildSettingCondition``
- ``CSetting``
- ``CXXSetting``
- ``SwiftSetting``
- ``LinkerSetting``
- ``PluginUsage``
- ``packageAccess``

### Describing the Target Type

- ``isTest``
- ``type``
- ``TargetType``
