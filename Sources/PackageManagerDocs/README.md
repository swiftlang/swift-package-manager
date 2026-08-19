The CLI documentation content is generated from the `help` configurations of the 
code, and needs the binary `generate-docc-reference-tool` to work against locally
built versions to generate up the docc-flavored markdown files.

This README presumes that you have local dependencies as neighbor enlistments to the package manager repository, such as a local Swift toolchain checkout.
You can use the version of Swift Argument Parser that SwiftPM manages as a dependency. Using a local build, start by running `swift package resolve` from the root of the SwiftPM project, then:

```bash
export SWIFTCI_USE_LOCAL_DEPS=1
swift package resolve
pushd .build/checkouts/swift-argument-parser
swift build --target generate-docc-reference
popd
export DOCC_REF_PATH=".build/checkouts/swift-argument-parser/.build/debug"
swift build -c release # to generate the CLIs
```

The `generate-docc-reference` doesn't work for automatically creating all these because
of a quirk in swift-package-manager, which the driver executable that expects to be
called with different names rather than as a singular executable binary. 
The heurstics in swift-argument-parser's generation tool don't accomodate this use case,
so we invoke it differently to create the raw markdown output:

```bash
${DOCC_REF_PATH}/generate-docc-reference .build/release/swift-test -o Sources/PackageManagerDocs/Documentation.docc --style docc
${DOCC_REF_PATH}/generate-docc-reference .build/release/swift-bootstrap -o Sources/PackageManagerDocs/Documentation.docc --style docc
${DOCC_REF_PATH}/generate-docc-reference .build/release/swift-sdk -o Sources/PackageManagerDocs/Documentation.docc --style docc
${DOCC_REF_PATH}/generate-docc-reference .build/release/swift-run -o Sources/PackageManagerDocs/Documentation.docc --style docc
${DOCC_REF_PATH}/generate-docc-reference .build/release/swift-package -o Sources/PackageManagerDocs/Documentation.docc --style docc
${DOCC_REF_PATH}/generate-docc-reference .build/release/swift-package-registry -o Sources/PackageManagerDocs/Documentation.docc --style docc
${DOCC_REF_PATH}/generate-docc-reference .build/release/swift-package-collection -o Sources/PackageManagerDocs/Documentation.docc --style docc
${DOCC_REF_PATH}/generate-docc-reference .build/release/swift-build -o Sources/PackageManagerDocs/Documentation.docc --style docc
${DOCC_REF_PATH}/generate-docc-reference .build/release/swift-build-prebuilts -o Sources/PackageManagerDocs/Documentation.docc --style docc
```

The sequence of commands above results in a set of new markdown files that need 
to be split and moved based on command and subcommand:

```
Sources/PackageManagerDocs/Documentation.docc/build-prebuilts.md
Sources/PackageManagerDocs/Documentation.docc/build.md
Sources/PackageManagerDocs/Documentation.docc/package-collection.md
Sources/PackageManagerDocs/Documentation.docc/package-registry.md
Sources/PackageManagerDocs/Documentation.docc/package.md
Sources/PackageManagerDocs/Documentation.docc/run.md
Sources/PackageManagerDocs/Documentation.docc/sdk.md
Sources/PackageManagerDocs/Documentation.docc/swift-bootstrap.md
Sources/PackageManagerDocs/Documentation.docc/test.md
```

As of May 2025, the generation tool generates a single large markdown file in DocC
format, which we then split up manually into small pieces for the CLI content. 

Use the following command to preview documentation changes for this target:

```bash
swift package --disable-sandbox preview-documentation --target PackageManagerDocs
```
