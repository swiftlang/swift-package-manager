# swift package build-cache configure

@Metadata {
    @PageImage(purpose: icon, source: command-icon)
}

Configure build cache options.

```
package build-cache configure [--enable-caching]
  [--disable-caching] [--path=<path>]
  [--size-limit=<size-limit>] [--enable-diagnostic-remarks]
  [--disable-diagnostic-remarks]
  [--experimental-plugin-path=<experimental-plugin-path>]
  [--experimental-remote-service-path=<experimental-remote-service-path>]
  [--enable-prefix-mapping] [--disable-prefix-mapping]
  [--global] [--version] [--help]
```

- term **--enable-caching**:

*Enable or disable the build cache.*


- term **--disable-caching**:

*Enable or disable the build cache.*


- term **--path=\<path\>**:

*The path to the build cache.*


- term **--size-limit=\<size-limit\>**:

*Limit the build cache size, either as an absolute size (e.g. '10G') or as a percentage of available disk space (e.g. '50%').*


- term **--enable-diagnostic-remarks**:

*Enable or disable diagnostic remarks about build cache hits and misses.*


- term **--disable-diagnostic-remarks**:

*Enable or disable diagnostic remarks about build cache hits and misses.*


- term **--experimental-plugin-path=\<experimental-plugin-path\>**:

*The path to an LLVM-compatible build cache plugin.*


- term **--experimental-remote-service-path=\<experimental-remote-service-path\>**:

*The path to a remote build cache service.*


- term **--enable-prefix-mapping**:

*Enable or disable prefix mapping, allowing copies of a package at different paths to share cached outputs.*


- term **--disable-prefix-mapping**:

*Enable or disable prefix mapping, allowing copies of a package at different paths to share cached outputs.*


- term **--global**:

*Apply to the shared global configuration instead of the local package configuration.*


- term **--version**:

*Show the version.*


- term **--help**:

*Show help information.*
