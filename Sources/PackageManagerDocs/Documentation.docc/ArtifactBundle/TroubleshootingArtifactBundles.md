# Troubleshooting artifact bundles

Solutions to common artifact bundle errors and issues.

## Archive structure errors

### Error: "A bundle archive should contain at least one directory with the `.artifactbundle` extension"

**Cause**: The ZIP archive structure is incorrect. SPM expects the `.artifactbundle` directory at the root of the archive.

**Solution**:

```bash
# ❌ Wrong structure (directory not in archive root)
MyLibrary.zip
└── build/
    └── MyLibrary.artifactbundle/

# ✅ Correct structure
MyLibrary.artifactbundle.zip
└── MyLibrary.artifactbundle/
    ├── info.json
    └── ...

# Fix by creating archive from parent directory:
cd /path/to/parent
zip -r MyLibrary.artifactbundle.zip MyLibrary.artifactbundle/

# Verify archive structure:
unzip -l MyLibrary.artifactbundle.zip
```

## Platform compatibility errors

### Error: "No suitable variant found for platform"

**Full error**:
```
error: No suitable artifact for the target platform (arm64-apple-macosx) was found in the artifact bundle
```

**Cause**: Your artifact bundle doesn't contain a variant matching the current platform triple.

**Solution**:

1. Check which platform you're building for:
```bash
swift build --verbose 2>&1 | grep "target triple"
# Output example: arm64-apple-macosx
```

2. Verify your info.json includes this triple:
```bash
jq '.artifacts[].variants[].supportedTriples' info.json
```

3. Add the missing platform variant to your artifact bundle.

### Error: "version `GLIBC_X.XX` not found"

**Full error**:
```
./myapp: /lib/x86_64-linux-gnu/libc.so.6: version `GLIBC_2.34' not found
```

**Cause**: Static library was built against a newer glibc version than the target system has.

**Solution**: Rebuild using an older glibc version via Docker:

```bash
# Use manylinux_2_28 (glibc 2.28 - broad compatibility)
docker run --rm -v $(pwd):/workspace -w /workspace \
    quay.io/pypa/manylinux_2_28_x86_64 \
    bash -c "
        # Install Rust if needed
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
        source \$HOME/.cargo/env

        # Build
        cargo build --release --target x86_64-unknown-linux-gnu
    "
```

**Check glibc version**:
```bash
# On Linux, check required glibc version
objdump -T libmylib.a | grep GLIBC_
```

## Checksum errors

### Error: "Checksum mismatch"

**Full error**:
```
error: checksum of downloaded artifact of binary target 'MyLibrary' (abc123...)
does not match checksum specified by the manifest (def456...)
```

**Cause**: The downloaded artifact's checksum doesn't match Package.swift.

**Solution**:

```bash
# Recompute checksum for the actual file you uploaded
swift package compute-checksum MyLibrary.artifactbundle.zip

# Update Package.swift with the correct checksum:
.binaryTarget(
    name: "MyLibrary",
    url: "https://github.com/org/repo/releases/download/v1.0.0/MyLibrary.artifactbundle.zip",
    checksum: "<paste-new-checksum-here>"
)
```

## Linking errors

### Error: "Undefined symbols" during linking

**Full error**:
```
error: Undefined symbols for architecture arm64:
  "_OPENSSL_init_ssl", referenced from:
      _my_function in libMyLib.a
```

**Cause**: Static library has external dependencies that weren't statically linked.

**Solution**:

For Rust libraries:
```bash
# Use vendored/static features
cargo build --release \
    --features vendored-openssl,static-linking \
    --crate-type=staticlib
```

For C++ libraries:
```bash
# Statically link libstdc++ and libgcc
g++ -static-libstdc++ -static-libgcc -c mylib.cpp
ar rcs libmylib.a mylib.o
```

**Verify symbols are resolved**:
```bash
# Check for undefined symbols (should be empty or only system symbols)
nm -u libmylib.a

# macOS: Check dynamic dependencies (should be minimal)
otool -L libmylib.a
```

## Module and import errors

### Error: "Cannot find module 'X' in scope"

**Full error**:
```swift
error: Cannot find 'crypto_hash' in scope
import Crypto  // No such module
```

**Cause**: Module name mismatch between info.json, module.modulemap, and Swift import.

**Solution**: Verify naming consistency:

```bash
# 1. Check artifact name in info.json
jq '.artifacts | keys' MyLibrary.artifactbundle/info.json
# Output: ["Crypto"]

# 2. Check module name in module.modulemap
cat MyLibrary.artifactbundle/include/module.modulemap
# Should have: module Crypto { ... }

# 3. Swift import must match
# import Crypto  ← Must match exactly
```

## Cache issues

### Forcing cache refresh

Changes to artifact bundle aren't being picked up:

```bash
# Level 1: Clean build artifacts (keeps downloaded artifacts)
swift package clean

# Level 2: Reset package state (clears all caches)
swift package reset

# Level 3: Update dependencies (re-resolves and re-downloads)
swift package update

# Level 4: Manual cache clear (nuclear option)
rm -rf ~/Library/Caches/org.swift.swiftpm/
rm -rf .build/
rm Package.resolved
swift package resolve
```

## Validation procedures

### Check bundle structure

```bash
# Verify bundle structure
tree MyLibrary.artifactbundle

# Expected:
# MyLibrary.artifactbundle/
# ├── info.json
# ├── mylib/
# │   └── *.a files
# └── include/
#     ├── *.h files
#     └── module.modulemap
```

### Validate info.json

```bash
# Check JSON is valid
cat MyLibrary.artifactbundle/info.json | jq .

# Verify schema version
jq '.schemaVersion' MyLibrary.artifactbundle/info.json

# List all artifacts
jq '.artifacts | keys' MyLibrary.artifactbundle/info.json

# Validate required fields exist
jq -e '.schemaVersion' MyLibrary.artifactbundle/info.json && \
jq -e '.artifacts' MyLibrary.artifactbundle/info.json && \
jq -e '.artifacts[] | .type' MyLibrary.artifactbundle/info.json && \
jq -e '.artifacts[] | .version' MyLibrary.artifactbundle/info.json && \
jq -e '.artifacts[] | .variants' MyLibrary.artifactbundle/info.json || \
{ echo "ERROR: Missing required fields in info.json"; exit 1; }

echo "✅ info.json validation passed"
```

### Verify symbol exports (Linux)

```bash
# List symbols in static library
nm -g MyLibrary.artifactbundle/mylib/libmylib-linux-x86_64.a

# Check for undefined symbols
nm -u MyLibrary.artifactbundle/mylib/libmylib-linux-x86_64.a
```

### Test on target platforms

Create a test package:

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

```bash
# Build and run on each platform
swift build
swift run Test
```
