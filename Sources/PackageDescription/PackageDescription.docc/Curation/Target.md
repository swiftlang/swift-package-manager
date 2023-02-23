#  ``PackageDescription/Target``

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

### Creating a System Target

- ``systemLibrary(name:path:pkgConfig:providers:)``
- ``pkgConfig``
- ``providers``

### Creating an Executable Target

- ``executableTarget(name:dependencies:path:exclude:sources:resources:publicHeadersPath:cSettings:cxxSettings:swiftSettings:linkerSettings:)``
- ``executableTarget(name:dependencies:path:exclude:sources:resources:publicHeadersPath:cSettings:cxxSettings:swiftSettings:linkerSettings:plugins:)``

### Creating a Plugin Target

- ``plugin(name:capability:dependencies:path:exclude:sources:)``
- ``pluginCapability-swift.property``
- ``PluginCapability-swift.enum``
- ``PluginCommandIntent``
- ``PluginPermission``

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

### Describing the Target Type

- ``isTest``
- ``type``
- ``TargetType``
