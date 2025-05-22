# Showing Package Collection Metadata

Discover more about package collections and their packages.

## Overview

The [`describe` subcommand](<doc:PackageCollectionDescribe>) shows metadata for a collection or a package included in an imported collection. The result can optionally be returned as JSON using `--json` for
integration into other tools.

### Metadata and packages of a collection

`describe` can be used for both collections that have been previously added to the list of the user's configured collections, as well as to preview any other collections.

```bash
$ swift package-collection describe [--json] https://www.example.com/packages.json
Name: Sample Package Collection
Source: https://www.example.com/packages.json
Description: ...
Keywords: best, packages
Created At: 2020-05-30 12:33
Packages:
    https://github.com/jpsim/yams
    ...
```

#### Signed package collections

If a collection is signed, SwiftPM will check that the signature is valid before showing a preview.

```bash
$ swift package-collection describe https://www.example.com/bad-packages.json
The collection's signature is invalid. If you would like to continue please rerun command with '--skip-signature-check'.
```

Users may continue previewing the collection despite the error or preemptively skip the signature check on a package collection by passing the `--skip-signature-check` flag:

```bash
$ swift package-collection describe https://www.example.com/packages.json --skip-signature-check
```

### Metadata of a package

`describe` can also show the metadata of a package included in an imported collection:

```bash
$ swift package-collection describe [--json] https://github.com/jpsim/yams
Description: A sweet and swifty YAML parser built on LibYAML.
Available Versions: 4.0.0, 3.0.0, ...
Stars: 14
Readme: https://github.com/jpsim/Yams/blob/master/README.md
Authors: @norio-nomura, @jpsim
--------------------------------------------------------------
Latest Version: 4.0.0
Package Name: Yams
Modules: Yams, CYaml
Supported Platforms: iOS, macOS, Linux, tvOS, watchOS
Supported Swift Versions: 5.3, 5.2, 5.1, 5.0
License: MIT
```

### Metadata of a package version

User may view additional metadata for a package version by passing `--version`:

```bash
$ swift package-collection describe [--json] --version 4.0.0 https://github.com/jpsim/yams
Package Name: Yams
Version: 4.0.0
Modules: Yams, CYaml
Supported Platforms: iOS, macOS, Linux, tvOS, watchOS
Supported Swift Versions: 5.3, 5.2, 5.1, 5.0
License: MIT
```
