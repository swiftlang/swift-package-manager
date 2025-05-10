Manually generated the docc content stubs using the swift argument parser tool `generate-docc-reference-tool`:

The `generate-docc-reference` doesn't work for automatically creating all these because of a quirk in swift-package-manager, which is a driver
executable and expects to be called with different names. The heurstics in swift-argument-parser's generation tool don't accomodate this use case.

```bash
swift build -c release
.build/debug/generate-docc-reference-tool .build/release/swift-test -o Sources/PackageManagerDocs/Documentation.docc --style docc
.build/debug/generate-docc-reference-tool .build/release/swift-bootstrap -o Sources/PackageManagerDocs/Documentation.docc --style docc
.build/debug/generate-docc-reference-tool .build/release/swift-sdk -o Sources/PackageManagerDocs/Documentation.docc --style docc
.build/debug/generate-docc-reference-tool .build/release/swift-run -o Sources/PackageManagerDocs/Documentation.docc --style docc
.build/debug/generate-docc-reference-tool .build/release/swift-package -o Sources/PackageManagerDocs/Documentation.docc --style docc
.build/debug/generate-docc-reference-tool .build/release/swift-package-registry -o Sources/PackageManagerDocs/Documentation.docc --style docc
.build/debug/generate-docc-reference-tool .build/release/swift-package-collection -o Sources/PackageManagerDocs/Documentation.docc --style docc
.build/debug/generate-docc-reference-tool .build/release/swift-build -o Sources/PackageManagerDocs/Documentation.docc --style docc
.build/debug/generate-docc-reference-tool .build/release/swift-build-prebuilts -o Sources/PackageManagerDocs/Documentation.docc --style docc
```

As of May 2025, the generation tool generates a single large markdown file in DocC format, which we then split up manually into small pieces
for the CLI content.

Use the following command to preview documentation changes for this target:

```bash
swift package --disable-sandbox preview-documentation --target PackageManagerDocs
```
