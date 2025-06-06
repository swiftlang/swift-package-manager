# swift sdk install

@Metadata {
    @PageImage(purpose: icon, source: command-icon)
    @Available("Swift", introduced: "6.1")
}

Installs a given Swift SDK bundle to a location discoverable by SwiftPM.

If the artifact bundle is at a remote location, it's downloaded to local filesystem first.

```
sdk install [--package-path=<package-path>] [--cache-path=<cache-path>] [--config-path=<config-path>] [--security-path=<security-path>] [--scratch-path=<scratch-path>]     [--swift-sdks-path=<swift-sdks-path>] [--toolset=<toolset>...] [--pkg-config-path=<pkg-config-path>...]   <bundle-path-or-url> [--checksum=<checksum>] [--color-diagnostics|no-color-diagnostics] [--version] [--help]
```

- term **--package-path=\<package-path\>**:

*Specify the package path to operate on (default current directory). This changes the working directory before any other operation.*


- term **--cache-path=\<cache-path\>**:

*Specify the shared cache directory path.*


- term **--config-path=\<config-path\>**:

*Specify the shared configuration directory path.*


- term **--security-path=\<security-path\>**:

*Specify the shared security directory path.*


- term **--scratch-path=\<scratch-path\>**:

*Specify a custom scratch directory path. (default .build)*


- term **--swift-sdks-path=\<swift-sdks-path\>**:

*Path to the directory containing installed Swift SDKs.*


- term **--toolset=\<toolset\>**:

*Specify a toolset JSON file to use when building for the target platform. Use the option multiple times to specify more than one toolset. Toolsets will be merged in the order they're specified into a single final toolset for the current build.*


- term **--pkg-config-path=\<pkg-config-path\>**:

*Specify alternative path to search for pkg-config `.pc` files. Use the option multiple times to
specify more than one path.*


- term **bundle-path-or-url**:

*A local filesystem path or a URL of a Swift SDK bundle to install.*


- term **--checksum=\<checksum\>**:

*The checksum of the bundle generated with `swift package compute-checksum`.*


- term **--color-diagnostics|no-color-diagnostics**:

*Enables or disables color diagnostics when printing to a TTY. 
By default, color diagnostics are enabled when connected to a TTY and disabled otherwise.*


- term **--version**:

*Show the version.*


- term **--help**:

*Show help information.*

