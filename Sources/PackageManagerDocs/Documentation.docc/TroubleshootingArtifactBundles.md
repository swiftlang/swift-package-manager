# Troubleshooting artifact bundles

Diagnose and fix common problems when you create or use an artifact bundle.

## Overview

Most artifact bundle problems come from one of four places: the archive, the manifest, the platform match, or the module map.
This article lists the symptoms you see for each, and how to confirm the cause.
For the manifest schema, read <doc:ArtifactBundleReference>.

## Archive errors

### Error: "invalid archive returned from"

Swift Package Manager validates a downloaded archive before it computes the checksum.
If validation fails, it reports an error like this:

```
error: invalid archive returned from 'https://example.com/MyLibrary.artifactbundle.zip' which is required by binary target 'MyLibrary'
```

**Cause**: The downloaded file isn't a valid archive.
Common reasons include a wrong URL, a release that requires authentication, or a download that returned an HTML error page.

**Solution**: Download the file yourself and inspect it:

```bash
curl -L -o MyLibrary.artifactbundle.zip "https://example.com/MyLibrary.artifactbundle.zip"
unzip -l MyLibrary.artifactbundle.zip
```

If `unzip` can't read the file, fix the URL or the access settings on the release.

### Check the archive layout

Put the `.artifactbundle` directory at the top of the archive:

```
MyLibrary.artifactbundle.zip
└── MyLibrary.artifactbundle/
    ├── info.json
    └── ...
```

Swift Package Manager also accepts an archive with one extra top-level directory, such as `build/MyLibrary.artifactbundle/`.
It removes that directory when it extracts the archive.
Archives with more than one top-level directory don't get this treatment.

To create the archive from the right place, run `zip` in the directory that contains the bundle:

```bash
cd /path/to/parent
zip -r MyLibrary.artifactbundle.zip MyLibrary.artifactbundle/
unzip -l MyLibrary.artifactbundle.zip
```

## Platform errors

### Warning: "did not contain a matching variant"

If no variant in the bundle matches the platform you're building for, Swift Package Manager skips the artifact.
The Swift Build build system reports a warning like this:

```
warning: /path/to/MyLibrary.artifactbundle ignoring 'MyLibrary' because the artifact bundle did not contain a matching variant
```

The warning isn't the end of the problem.
The build goes on without the library, and it then fails with errors about a missing header or an unresolved module:

```
error: 'mylibrary.h' file not found
error: unable to resolve module dependency: 'MyLibrary'
```

**Cause**: No variant lists a triple that matches the build.

**Solution**:

1. Find the triple you're building for:

   ```bash
   swift -print-target-info | jq -r '.target.triple'
   ```

2. List the triples in the manifest:

   ```bash
   jq '.artifacts[].variants[].supportedTriples' MyLibrary.artifactbundle/info.json
   ```

3. Add a variant for the missing platform, or add the triple to an existing variant.

Swift Package Manager ignores the OS version when it compares triples.
A variant for `arm64-apple-macosx` matches a build for `arm64-apple-macosx15.0`.

### Error: "not a mach-o file" or "file not found" when `supportedTriples` is missing

A static library variant that omits `supportedTriples` doesn't match any platform.
Swift Package Manager doesn't warn about it.
The symptoms depend on the build system:

- With the Swift Build system, the linker can fail on archives for other platforms:

  ```
  ld: archive member '/' not a mach-o file in '.../MyLibrary.artifactbundle/mylib/libMyLib-linux-x86_64.a'
  ```

- With the native build system, the build fails on the first header the library provides:

  ```
  fatal error: 'mylibrary.h' file not found
  ```

**Solution**: Add `supportedTriples` to every variant.

### Error: "version `GLIBC_X.XX` not found"

```
./myapp: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.34' not found
```

**Cause**: You built the library on a system with a newer glibc than the system that runs the program.

**Solution**: Rebuild the library in an environment with the oldest glibc you want to support.
A container image for an older Linux distribution is one way to do this.

To see which glibc versions your library requires, list its symbols:

```bash
objdump -T libmylib.a | grep GLIBC_
```

## Checksum errors

### Error: "checksum of downloaded artifact does not match"

```
error: checksum of downloaded artifact of binary target 'MyLibrary' (abc123...) does not match checksum specified by the manifest (def456...)
```

**Cause**: The checksum in `Package.swift` doesn't match the archive at the URL.
This often happens after you upload a rebuilt archive without updating the manifest.

**Solution**: Compute the checksum of the archive you uploaded, and update `Package.swift`:

```bash
swift package compute-checksum MyLibrary.artifactbundle.zip
```

```swift
.binaryTarget(
    name: "MyLibrary",
    url: "https://github.com/org/repo/releases/download/v1.0.0/MyLibrary.artifactbundle.zip",
    checksum: "<new-checksum>"
)
```

## Linking errors

### Error: "Undefined symbols" during linking

```
error: Undefined symbols for architecture arm64:
  "_OPENSSL_init_ssl", referenced from:
      _my_function in libMyLib.a
```

**Cause**: The static library depends on code from another library, and that code isn't in the bundle.

**Solution**: Check which symbols the library expects other code to provide:

```bash
nm -u libmylib.a
```

Symbols from the system libraries are fine.
Symbols from third-party libraries mean you need to include that code in your static library, or add the other library to your bundle.

## Module and import errors

### Error: "No such module"

```
error: no such module 'MyLibrary'
```

**Cause**: The module name in the module map doesn't match the name in the Swift `import` statement.

**Solution**: Check the module declaration in the module map:

```bash
cat MyLibrary.artifactbundle/include/module.modulemap
```

The name after `module` is the name Swift code imports.
Also confirm that the manifest's `moduleMapPath` points at this file, and that `headerPaths` lists the directory that holds the headers.
To learn more, read <doc:DebuggingModuleMaps>.

## Cache issues

### Changes to a bundle aren't picked up

Swift Package Manager caches downloaded artifacts.
If you republish a bundle at the same URL, a build might keep using the old copy.

Work through these steps in order, and stop when the problem is fixed:

```bash
# Remove build products, and keep downloaded artifacts
swift package clean

# Reset the package's state, including checked-out dependencies
swift package reset

# Re-resolve and re-download dependencies
swift package update
```

If none of these work, remove the shared cache.
On macOS, it's in `~/Library/Caches/org.swift.swiftpm`:

```bash
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf .build
swift package resolve
```

Better still, publish each change under a new version and URL, so the checksum and the URL always agree.

## Validate a bundle

### Check the bundle structure

```bash
tree MyLibrary.artifactbundle
```

A static library bundle looks like this:

```
MyLibrary.artifactbundle/
├── info.json
├── mylib/
│   └── *.a files
└── include/
    ├── *.h files
    └── module.modulemap
```

### Check the manifest

```bash
# Confirm the file is valid JSON
jq . MyLibrary.artifactbundle/info.json

# Show the schema version and the artifact names
jq '.schemaVersion' MyLibrary.artifactbundle/info.json
jq '.artifacts | keys' MyLibrary.artifactbundle/info.json
```

### Check the symbols in a static library

```bash
# List the exported symbols
nm -g MyLibrary.artifactbundle/mylib/libMyLib-linux-x86_64.a

# List the undefined symbols
nm -u MyLibrary.artifactbundle/mylib/libMyLib-linux-x86_64.a
```

### Test the bundle in a package

Create a package that depends on the bundle by path:

```swift
// Package.swift
let package = Package(
    name: "ArtifactTest",
    targets: [
        .binaryTarget(
            name: "MyLibrary",
            path: "../MyLibrary.artifactbundle"
        ),
        .executableTarget(
            name: "Test",
            dependencies: ["MyLibrary"]
        )
    ]
)
```

```swift
// Sources/Test/main.swift
import MyLibrary

let result = myLibraryFunction()
print("Result: \(result)")
```

Build and run it on each platform you support:

```bash
swift build
swift run Test
```

## See Also

- <doc:ArtifactBundleReference>
- <doc:ModuleMaps>
- <doc:DebuggingModuleMaps>
