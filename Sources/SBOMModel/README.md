# SBOMModel - SBOM Version Management

This document describes how to manage SBOM specification versions in SwiftPM.

## Overview

The `SBOMVersionRegistry` maintains the most recent minor version for each major version of supported SBOM specifications (CycloneDX and SPDX).

### Version Support Policy

SwiftPM supports **only the most recent minor version** of each **major version**:
- When a new minor version is released (e.g., CycloneDX 1.8), drop the old minor (1.7)
- When a new major version is released (e.g., CycloneDX 2.0), maintain both major versions

## Current Supported Versions

### CycloneDX
- **v1.x**: Latest minor version is 1.7

### SPDX
- **v3.x**: Latest minor version is 3.0.1

## Updating Minor Versions

When a new minor version is released (e.g., CycloneDX 1.8 or SPDX 3.1), follow these steps:

### Step 1: Update Version Constant

In [`SBOMVersionRegistry.swift`](Core/SBOMVersionRegistry.swift), change the version string:

```swift
// Before:
internal static let cycloneDX1LatestMinor = "1.7"

// After:
internal static let cycloneDX1LatestMinor = "1.8"
```

### Step 2: Replace Schema File

In the Resources directory:
- **Delete**: `Sources/SBOMModel/CycloneDX/Resources/cyclonedx-1.7.schema.json`
- **Add**: `Sources/SBOMModel/CycloneDX/Resources/cyclonedx-1.8.schema.json`

### Step 3: Update Tests

Update test expectations to use the new version:

```swift
// Before:
XCTAssertEqual(spec.version, "1.7")

// After:
XCTAssertEqual(spec.version, "1.8")
```

### Step 4: Verify Constants

The constants should automatically use the new version:
- `CycloneDXConstants.cyclonedx1SpecVersion` → "1.8"
- `CycloneDXConstants.cyclonedx1Schema` → "...bom-1.8.schema.json"
- `CycloneDXConstants.cyclonedx1SchemaFile` → "cyclonedx-1.8.schema"

### Step 5: Test Thoroughly

- Run all SBOM tests
- Generate sample SBOMs and validate against new schema
- Verify backward compatibility if needed

## Adding New Major Versions

When a new major version is released (e.g., CycloneDX 2.0 or SPDX 4.0), follow these steps:

### Step 1: Update SBOMVersionRegistry.swift

Uncomment and set the appropriate version constant:

```swift
internal static let cycloneDX2LatestMinor = "2.0"  // or spdx4LatestMinor = "4.0"
```

Add the case to `getLatestVersion(for:)`:

```swift
case .cyclonedx2:
    return cycloneDX2LatestMinor
```

### Step 2: Update SBOMSpec.swift

Add new case to the `Spec` enum:

```swift
case cyclonedx2  // or spdx4
```

Update all switch statements to handle the new case.

### Step 3: Create New Constants

Add to [`CycloneDXConstants.swift`](CycloneDX/CycloneDXConstants.swift) (or [`SPDXConstants.swift`](SPDX/SPDXConstants.swift)):

```swift
internal static var cyclonedx2SpecVersion: String {
    SBOMVersionRegistry.cycloneDX2LatestMinor
}
internal static var cyclonedx2Schema: String {
    "http://cyclonedx.org/schema/bom-\(cyclonedx2SpecVersion).schema.json"
}
internal static var cyclonedx2SchemaFile: String {
    "cyclonedx-\(cyclonedx2SpecVersion).schema"
}
```

### Step 4: Update Encoder and Converter

In [`SBOMEncoder.swift`](Encoder/SBOMEncoder.swift):
- Update `encodeSBOMData(spec:)` switch statement
- Update `getSchemaFilename(from:)` switch statement

In [`CycloneDXConverter.swift`](Converter/CycloneDXConverter.swift) (or [`SPDXConverter.swift`](Converter/SPDXConverter.swift)):
- Add converter methods for new major version if format changed
- Or reuse existing converter if format is compatible

### Step 5: Add Schema File

Add the schema file to Resources:
- `Sources/SBOMModel/CycloneDX/Resources/cyclonedx-2.0.schema.json`
- Or: `Sources/SBOMModel/SPDX/Resources/spdx-4.0.schema.json`

### Step 6: Update Tests

- Add test fixtures for new major version
- Update test expectations
- Verify both old and new major versions work correctly

## Version Resolution

The registry provides a central method to get the latest supported version for any spec type:

```swift
let version = SBOMVersionRegistry.getLatestVersion(for: spec)
```
