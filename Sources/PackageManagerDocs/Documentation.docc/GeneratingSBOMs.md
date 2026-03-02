# Generating Software Bill of Materials (SBOM)

Create an inventory of components and dependencies using SBOM documents.

## Overview

Swift Package Manager generates Software Bill of Materials (SBOM) documents for Swift packages and products.

Swift Package Manager currently supports two SBOM formats: CycloneDX and SPDX. 

Generate SBOMs using either the [`swift build`](doc:SwiftBuild) command with SBOM flags or the dedicated [`swift package generate-sbom`](doc:PackageGenerateSBOM) subcommand.

### Use swift build

Generate SBOMs through SwiftBuild to factor in build-time conditionals.

Using the `--sbom-spec` and `--target` flags together causes an error.

```bash
swift build --build-system swiftbuild --sbom-spec cyclonedx
swift build --build-system swiftbuild --sbom-spec spdx
swift build --build-system swiftbuild \
    --sbom-spec cyclonedx \
    --sbom-spec spdx
```

The following examples generate SBOMs without using the Swift Build build backend.

```bash
swift build --sbom-spec cyclonedx
swift build --sbom-spec spdx
swift build --sbom-spec cyclonedx \
    --sbom-spec spdx
```

### Use swift package generate-sbom

[`swift package generate-sbom`](doc:PackageGenerateSBOM) generates an SBOM without building.
This SBOM is less accurate than an SBOM from `swift build` because build-time conditionals aren't applied and the package graph might change before generation.

For the highest accuracy, generate SBOMs through `swift build` whenever possible.

Not specifying `--sbom-spec` will generate all SBOM specs supported by Swift Package Manager.

```bash
swift package generate-sbom --sbom-spec cyclonedx
swift package generate-sbom --sbom-spec spdx
swift package generate-sbom --sbom-spec cyclonedx \
    --sbom-spec spdx
swift package generate-sbom
```

### Configure Additional Flags

The following flags apply to both `swift build` and `swift package generate-sbom`:

Generate an SBOM for a specific product in a package using the `--product` flag.

```bash
swift build --build-system swiftbuild --product MyProduct \
    --sbom-spec cyclonedx
swift package generate-sbom --product MyProduct \
    --sbom-spec spdx
```

Filter an SBOM by packages or products. By default, the SBOM includes both packages and products. 
Swift Package Manager always includes the primary component, regardless of the applied filter.

```bash
swift build --build-system swiftbuild --sbom-spec cyclonedx \
    --sbom-filter package
swift package generate-sbom --sbom-spec spdx \
    --sbom-filter product
```

Swift Package Manager places generated SBOMs in `<build_output>/sboms` by default.
Use `--sbom-output-dir` to specify a different directory for generated SBOMs.

```bash
swift build --build-system swiftbuild --sbom-spec cyclonedx \
    --sbom-output-dir /path/to/some/directory
swift package generate-sbom --sbom-spec spdx \
    --sbom-output-dir /path/to/some/directory
```

By default, if SBOM generation fails, the `build` or `package` command also fails.
The `--sbom-warning-only` flag converts all SBOM generation errors to warnings.

```bash
swift build --build-system swiftbuild --sbom-spec cyclonedx \
    --sbom-output-dir / --sbom-warning-only
swift package generate-sbom --sbom-spec spdx \
    --sbom-output-dir / --sbom-warning-only
```

### Configure Environment Variables

Trigger and configure SBOM generation using environment variables.
CLI flags take precedence over environment variables.

Configure the following environment variables:

- `SWIFTPM_BUILD_SBOM_SPEC`
- `SWIFTPM_BUILD_SBOM_OUTPUT_DIR`
- `SWIFTPM_BUILD_SBOM_FILTER`
- `SWIFTPM_BUILD_SBOM_WARNING_ONLY`

```bash
SWIFTPM_BUILD_SBOM_SPEC=cyclonedx,spdx swift build \
    --build-system swiftbuild
```

When you use environment variables, SBOM generation only triggers if `SWIFTPM_BUILD_SBOM_SPEC` is set. 
