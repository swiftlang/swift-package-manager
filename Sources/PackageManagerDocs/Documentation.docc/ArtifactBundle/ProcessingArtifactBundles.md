# Processing Artifact Bundles

Understand how Swift Package Manager processes artifact bundles to debug issues and optimize your build configuration.

## Overview

When you add an artifact bundle dependency, Swift Package Manager automatically handles dependency resolution, platform matching, metadata parsing, build configuration injection, and linking. Understanding this pipeline helps you debug issues and verify that your artifact bundles are correctly integrated.

This article explains each step of the processing pipeline and provides debugging commands to inspect how SPM processes your artifact bundles.

## Understand the processing pipeline

SPM performs these steps automatically when you add an artifact bundle dependency:

```
1. Dependency Resolution
   ↓
2. Platform Triple Matching
   ↓
3. Metadata Parsing & Caching
   ↓
4. Build Configuration Injection
   ↓
5. Linking
```

Each step transforms the artifact bundle from a remote or local package into linked binary code in your application.

### Dependency resolution

For **remote binaries**, SPM:
- Downloads the artifact bundle or index file
- Verifies the checksum against your Package.swift
- Extracts files to `~/Library/Caches/org.swift.swiftpm/`
- Caches the bundle for future builds

For **local binaries**, SPM:
- Uses the path directly from Package.swift
- Skips downloading and checksum verification
- Provides faster iteration during development and testing

### Platform triple matching

SPM determines the current platform triple (for example, `arm64-apple-macosx`) and searches the artifact bundle's `variants` array:

```swift
// Matching logic (simplified):
let hostTriple = detectHostPlatform()  // e.g., "arm64-apple-macosx"

for variant in artifactBundle.variants {
    if variant.supportedTriples.contains(hostTriple) {
        useVariant(variant)
        break
    }
}
```

When no match is found, the build fails with the error "No suitable variant found for platform." To fix this, add the missing platform to your artifact bundle. See <doc:BuildingCrossPlatformLibraries> for guidance on building for multiple platforms.

### Metadata parsing and caching

SPM parses `info.json` and extracts:
- Binary paths
- Header search paths
- Module map locations
- Platform support information

**Caching behavior:**
```
First build:  Parse info.json → Cache metadata
Later builds: Use cached metadata (faster)
```

Cache location: `~/Library/Developer/Xcode/DerivedData/` or the `.build/` directory

**Cache invalidation commands:**
- `swift package clean` - Clears build artifacts
- `swift package reset` - Clears all package state
- `swift package update` - Re-resolves dependencies

The build system maintains a separate cache for artifact bundle metadata. Each unique artifact bundle path has its own cached metadata. When you change `info.json` (for example, header paths or module map location), SPM invalidates the build settings cache even if the `.a` file is unchanged.

### Build configuration injection

SPM automatically injects build settings from your artifact bundle without any manual configuration:

| Build Setting | Value Source | Purpose |
|--------------|--------------|---------|
| `HEADER_SEARCH_PATHS` | From `headerPaths` in info.json | C/C++ header discovery |
| `OTHER_CFLAGS` | Generated from `moduleMapPath` | Module map for C compilation |
| `OTHER_SWIFT_FLAGS` | Generated from `moduleMapPath` | Module map for Swift compilation |
| Library search path | From variant `path` | Linking the binary |

For example, given this artifact bundle structure:

```json
{
  "artifacts": {
    "MyLibrary": {
      "type": "staticLibrary",
      "variants": [{
        "path": "mylib/libMyLib-macos-arm64.a",
        "supportedTriples": ["arm64-apple-macosx"],
        "staticLibraryMetadata": {
          "headerPaths": ["include", "include/support"],
          "moduleMapPath": "include/module.modulemap"
        }
      }]
    }
  }
}
```

SPM generates these exact flags:

```bash
# HEADER_SEARCH_PATHS (added for each headerPath):
-I/Users/name/.build/artifacts/example/MyLibrary/MyLibrary.artifactbundle/include
-I/Users/name/.build/artifacts/example/MyLibrary/MyLibrary.artifactbundle/include/support

# OTHER_CFLAGS (for C/C++ compilation):
-fmodule-map-file=/Users/name/.build/artifacts/example/MyLibrary/MyLibrary.artifactbundle/include/module.modulemap

# OTHER_SWIFT_FLAGS (for Swift compilation):
-Xcc -fmodule-map-file=/Users/name/.build/artifacts/example/MyLibrary/MyLibrary.artifactbundle/include/module.modulemap

# Library path (passed to linker):
/Users/name/.build/artifacts/example/MyLibrary/MyLibrary.artifactbundle/mylib/libMyLib-macos-arm64.a
```

When you use multiple artifact bundles per target, the build system merges their settings into the target's build configuration.

### Linking

During the link phase:
- SPM passes the static library path to the linker
- The library is statically linked into your executable
- Symbols are resolved from the `.a` file

## Recognize what you don't need to configure

Because SPM handles artifact bundles automatically, you don't need to:

- ❌ Manually set header search paths
- ❌ Configure module map paths
- ❌ Add linker flags for the binary
- ❌ Conditionally compile for different platforms

Just add the binary target to your Package.swift and SPM handles the rest.

## Understand internal file type identifiers

For developers integrating with Xcode or build systems:

- **File Type**: `wrapper.artifactbundle`
- **UTI**: `org.swift.artifactbundle`
- **Extensions**: `.artifactbundle` (directory), `.artifactbundleindex` (index file)

Xcode project files and SPM use these identifiers for dependency resolution. The build system uses UTI conformance checking (via `fileType.conformsTo(identifier: "wrapper.artifactbundle")`), not just extension matching. This approach is more robust and handles edge cases like symlinks and case-insensitive filesystems.

## Debug the processing pipeline

Use these commands to see what SPM is doing:

```bash
# Verbose dependency resolution
swift package resolve --verbose

# Verbose build output (shows compiler flags)
swift build --verbose

# See exact flags passed to compiler
swift build --verbose 2>&1 | grep -A5 "clang\|swiftc"
```

### Inspect build settings injection

To see exactly what build settings SPM injects from artifact bundles:

```bash
# Show all compiler invocations with full flags
swift build --verbose 2>&1 | grep -A10 "swiftc.*MyTarget"

# Extract artifact bundle specific module map flags
swift build --verbose 2>&1 | grep -o "\-Xcc -fmodule-map-file=[^ ]*"

# See header search paths from artifact bundles
swift build --verbose 2>&1 | grep -o "\-I[^ ]*artifactbundle[^ ]*"

# See all flags for a specific target
swift build --verbose 2>&1 | sed -n '/Compile.*MyTarget/,/^$/p'
```

Expected output for artifact bundle flags:

```bash
# Header search paths
-I/Users/name/.build/artifacts/example/MyLibrary/MyLibrary.artifactbundle/include

# Module map for Swift compilation
-Xcc -fmodule-map-file=/Users/name/.build/artifacts/example/MyLibrary/MyLibrary.artifactbundle/include/module.modulemap

# Module map for C/C++ compilation (in clang invocations)
-fmodule-map-file=/Users/name/.build/artifacts/example/MyLibrary/MyLibrary.artifactbundle/include/module.modulemap
```

### Verify artifact bundle usage

Use these commands to verify that your artifact bundle is being used correctly:

```bash
# List all artifact bundles in build directory
ls -la .build/artifacts/

# Check if artifact bundle was downloaded
ls -la ~/Library/Caches/org.swift.swiftpm/artifacts/

# Verify artifact bundle structure
tree .build/artifacts/example/MyLibrary/

# Check info.json was parsed correctly
jq . .build/artifacts/example/MyLibrary/MyLibrary.artifactbundle/info.json
```

### Troubleshoot common issues

| Issue | Command | What to Check |
|-------|---------|---------------|
| Headers not found | `swift build -v 2>&1 \| grep HEADER_SEARCH_PATHS` | Verify -I paths include artifact bundle |
| Module not found | `swift build -v 2>&1 \| grep module-map-file` | Verify module map path is correct |
| Wrong binary used | `swift build -v 2>&1 \| grep "\.a"` | Check which .a file is being linked |
| Artifact not downloaded | `ls ~/Library/Caches/org.swift.swiftpm/artifacts/` | Verify artifact was fetched |

For more troubleshooting guidance, see <doc:TroubleshootingArtifactBundles>.
