# swift sdk configure

@Metadata {
    @PageImage(purpose: icon, source: command-icon)
    @Available("Swift", introduced: "6.1")
}

Manages configuration options for installed Swift SDKs.

```
sdk configure [--package-path=<package-path>]
  [--cache-path=<cache-path>] [--config-path=<config-path>]
  [--security-path=<security-path>]
  [--scratch-path=<scratch-path>]
  [--swift-sdks-path=<swift-sdks-path>]
  [--toolset=<toolset>...]
  [--pkg-config-path=<pkg-config-path>...]
  [--sdk-root-path=<sdk-root-path>]
  [--swift-resources-path=<swift-resources-path>]
  [--swift-static-resources-path=<swift-static-resources-path>]
  [--include-search-path=<include-search-path>...]
  [--library-search-path=<library-search-path>...]
  [--toolset-path=<toolset-path>...] [--reset]
  [--show-configuration] <sdk-id> [target-triple...] [--version]
  [--help]
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


- term **--sdk-root-path=\<sdk-root-path\>**:

*A path to a directory containing the SDK root.*


- term **--swift-resources-path=\<swift-resources-path\>**:

*A path to a directory containing Swift resources for dynamic linking.*


- term **--swift-static-resources-path=\<swift-static-resources-path\>**:

*A path to a directory containing Swift resources for static linking.*


- term **--include-search-path=\<include-search-path\>**:

*A path to a directory containing headers. Multiple paths can be specified by providing this option multiple times to the command.*


- term **--library-search-path=\<library-search-path\>**:

*"A path to a directory containing libraries. Multiple paths can be specified by providing this option multiple times to the command.*


- term **--toolset-path=\<toolset-path\>**:

*"A path to a toolset file. Multiple paths can be specified by providing this option multiple times to the command.*


- term **--reset**:

*Resets configuration properties currently applied to a given Swift SDK and target triple. If no specific property is specified, all of them are reset for the Swift SDK.*


- term **--show-configuration**:

*Prints all configuration properties currently applied to a given Swift SDK and target triple.*


- term **sdk-id**:

*An identifier of an already installed Swift SDK. Use the `list` subcommand to see all available identifiers.*


- term **target-triple**:

*The target triple of the Swift SDK to configure.*


- term **--version**:

*Show the version.*


- term **--help**:

*Show help information.*


