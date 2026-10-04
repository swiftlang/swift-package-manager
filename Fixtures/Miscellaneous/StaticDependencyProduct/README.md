# Static dependency product reproduction

This fixture uses ordinary SwiftPM APIs and does not depend on custom targets or
build-tool plugins. Run these commands from this directory with `SWIFT_BUILD`
pointing to the SwiftPM checkout's freshly built `swift-build` executable:

```sh
"$SWIFT_BUILD" --package-path App --build-system swiftbuild --product StaticLibrary
bin_path=$("$SWIFT_BUILD" --package-path App --build-system swiftbuild --show-bin-path)
test -f "$bin_path/libStaticLibrary.a"
```

On unmodified main, the build succeeds but the archive is missing. With the fix,
the declared static product is materialized as `libStaticLibrary.a`. On Windows,
the archive is named `StaticLibrary.lib` instead.

Building `--product App` and running the resulting executable prints `42` both
before and after the fix. The regression concerns the missing declared archive,
not ordinary Swift executable linking. Use a fresh scratch directory when
switching between binaries to avoid artifacts from a previous build.
