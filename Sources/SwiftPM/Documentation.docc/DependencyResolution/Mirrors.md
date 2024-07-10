# Package Mirrors

## Overview

A package mirror is an alternate source location that replicates the contents of an original package source. When using a mirror, SwiftPM fetches the package from the mirror URL instead of the original URL.

Package mirrors are useful in several scenarios:

1. **Availability**: Mirrors ensure that dependencies can be fetched even if the original source becomes unavailable or is deleted.

2. **Performance**: When access to the original source is slow, a mirror can provide faster access to package contents.

3. **Security and Validation**: Organizations can use mirrors to screen and approve upstream updates before making them available internally.

4. **Network Restrictions**: In environments with limited internet access, mirrors on internal networks allow package fetching without external connections.

## How to use mirrors

### Configuring a mirror

To set up a mirror for a package, use the following command:

```sh
swift package config set-mirror \
    --package-url <original URL> \
    --mirror-url <mirror URL>
```

For example:

```sh
swift package config set-mirror \
    --package-url https://github.com/apple/swift-argument-parser.git \
    --mirror-url https://internal-mirror.example.com/swift-argument-parser.git
```

### Removing a mirror

To remove a previously set mirror:

```sh
swift package config unset-mirror --package-url <original URL>
```

### Mirror configuration file

Mirror configurations are stored in a JSON file located at:

```
<package-root>/.swiftpm/configuration/mirrors.json
```

You can use the `SWIFTPM_MIRROR_CONFIG` environment variable to specify a custom mirror configuration file path:

```sh
export SWIFTPM_MIRROR_CONFIG=/path/to/mirrors.json
```

### Example workflow

1. Mirror a commonly used package:

   ```sh
   swift package config set-mirror \
       --package-url https://github.com/pointfreeco/swift-composable-architecture \
       --mirror-url https://internal-mirror.example.com/swift-composable-architecture
   ```

2. In your `Package.swift` or Xcode project, continue to reference the original URL:

   ```swift
   dependencies: [
       .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0"),
   ]
   ```

3. When resolving dependencies, SwiftPM will use the mirror URL instead of the original.

## Reference

- [SE-0219 Package Manager Dependency Mirroring](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0219-package-manager-dependency-mirroring.md)
