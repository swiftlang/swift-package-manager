# Generating Software Bill of Materials (SBOM)

Create an inventory of components and dependencies using SBOM documents.

## Overview

Swift Package Manager generates Software Bill of Materials (SBOM) documents for Swift packages and products.

Swift Package Manager currently supports two SBOM formats: CycloneDX and SPDX. 

Generate SBOMs using either the [`swift build`](doc:SwiftBuild) command with SBOM flags or the dedicated [`swift package generate-sbom`](doc:PackageGenerateSBOM) subcommand.

### Use the build command to generate SBOMs

Use the command `swift build` to compile your project and generate SBOMs.
Using the `--sbom-spec` and `--target` flags together causes an error.

Generating SBOMs through the Swift Build build backend factors in build-time conditionals.

```bash
swift build --build-system swiftbuild --sbom-spec cyclonedx
swift build --build-system swiftbuild --sbom-spec spdx
swift build --build-system swiftbuild --sbom-spec cyclonedx --sbom-spec spdx
```

The following examples generate SBOMs without using the Swift Build build backend. SBOMs generated without Swift Build may not be fully accurate, as build-time conditionals aren't applied to the SBOMs.

```bash
swift build --sbom-spec cyclonedx
swift build --sbom-spec spdx
swift build --sbom-spec cyclonedx --sbom-spec spdx
```

### Use the package command to generates SBOMs

[`swift package generate-sbom`](doc:PackageGenerateSBOM) generates an SBOM without building.
This SBOM is less accurate than an SBOM generated from `swift build --build-system swiftbuild` because build-time conditionals aren't applied.

For the highest accuracy, generate SBOMs using the command `swift build --build-system swiftbuild`.

Not specifying `--sbom-spec` generates all SBOM specs supported by Swift Package Manager.

```bash
swift package generate-sbom --sbom-spec cyclonedx
swift package generate-sbom --sbom-spec spdx
swift package generate-sbom --sbom-spec cyclonedx --sbom-spec spdx
swift package generate-sbom
```

### Configure additional flags

The following flags apply to both `swift build` and `swift package generate-sbom`:

#### Generate SBOM for a single product

Generate an SBOM for a specific product in a package using the `--product` flag.

```bash
swift build --build-system swiftbuild --product MyProduct --sbom-spec cyclonedx
swift package generate-sbom --product MyProduct --sbom-spec spdx
```

#### Filter SBOM contents

Filter an SBOM by packages or products by using `--sbom-filter <type>`. By default, an SBOM includes both packages and products.
Swift Package Manager always includes the primary component, regardless of the applied filter.

```bash
swift build --build-system swiftbuild --sbom-spec cyclonedx --sbom-filter package
swift package generate-sbom --sbom-spec spdx --sbom-filter product
```

#### Output SBOM to custom directory

Swift Package Manager places generated SBOMs in `<build_output>/sboms` by default.
Use `--sbom-output-dir` to specify a different directory for generated SBOMs.

```bash
swift build --build-system swiftbuild --sbom-spec cyclonedx --sbom-output-dir <path>
swift package generate-sbom --sbom-spec spdx --sbom-output-dir <path>
```

#### Reduce SBOM generation errors to warnings

By default, if SBOM generation fails, the `build` or `package` command also fails.
The `--sbom-warning-only` flag converts all SBOM generation errors to warnings.

```bash
swift build --build-system swiftbuild --sbom-spec cyclonedx --sbom-warning-only
swift package generate-sbom --sbom-spec spdx --sbom-warning-only
```

### Configure environment variables

Generating SBOMs can be triggered and configured using environment variables that you set prior to running `swift build` or `swift package generate-sbom`.
When you use CLI flags, they take precedence over environment variables.

Configure the following environment variables:

- `SWIFTPM_BUILD_SBOM_SPEC`
- `SWIFTPM_BUILD_SBOM_OUTPUT_DIR`
- `SWIFTPM_BUILD_SBOM_FILTER`
- `SWIFTPM_BUILD_SBOM_WARNING_ONLY`

```bash
SWIFTPM_BUILD_SBOM_SPEC=cyclonedx,spdx swift build --build-system swiftbuild
SWIFTPM_BUILD_SBOM_SPEC=cyclonedx swift package generate-sbom
```

When generating SBOMs using `swift build` and environment variables, `swift build` will generate SBOMS if, and only if, the `SWIFTPM_BUILD_SBOM_SPEC` is set.
