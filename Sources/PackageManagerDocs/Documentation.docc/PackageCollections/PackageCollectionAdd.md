# swift package-collection add

@Metadata {
    @PageImage(purpose: icon, source: command-icon)
    @Available("Swift", introduced: "5.5")
}

Add a new collection.

## Overview

This subcommand adds a package collection hosted on the web (HTTPS required):

```bash
$ swift package-collection add https://www.example.com/packages.json
Added "Sample Package Collection" to your package collections.
```

Or found in the local file system:

```bash
$ swift package-collection add file:///absolute/path/to/packages.json
Added "Sample Package Collection" to your package collections.
```

The optional `order` hint can be used to order collections and may potentially influence ranking in search results:

```bash
$ swift package-collection add https://www.example.com/packages.json [--order N]
Added "Sample Package Collection" to your package collections.
```

### Signed package collections

Package collection publishers may [sign a collection to protect its contents](<doc:PackageCollections#Signing-and-protecting-package-collections>) from being tampered with. 
If a collection is signed, SwiftPM will check that the 
signature is valid before importing it and return an error if any of these fails:
- The file's contents, signature excluded, must match what was used to generate the signature. 
In other words, this checks to see if the collection has been altered since it was signed.
- The signing certificate must meet all the [requirements](<doc:PackageCollections#Requirements-on-signing-certificate>).

```bash
$ swift package-collection add https://www.example.com/bad-packages.json
The collection's signature is invalid. If you would like to continue please rerun command with '--skip-signature-check'.
```

Users may continue adding the collection despite the error or preemptively skip the signature check on a package collection by passing the `--skip-signature-check` flag:

```bash
$ swift package-collection add https://www.example.com/packages.json --skip-signature-check
```

For package collections hosted on the web, publishers may ask SwiftPM to [enforce the signature requirement](<doc:PackageCollections#Protecting-package-collections>). If a package collection is
expected to be signed but it isn't, user will see the following error message:

```bash
$ swift package-collection add https://www.example.com/bad-packages.json
The collection is missing required signature, which means it might have been compromised.
```

Users should NOT add the package collection in this case.

##### Trusted root certificates

Since generating a collection signature requires a certificate, part of the signature check involves validating the certificate and its chain and making sure that the root certificate is trusted.

On Apple platforms, all root certificates that come preinstalled with the OS are automatically trusted. Users may include additional certificates to trust by placing 
them in the `~/.swiftpm/config/trust-root-certs` directory. 

On non-Apple platforms, there are no trusted root certificates by default other than those shipped with the [certificate-pinning configuration](<doc:PackageCollections#Protecting-package-collections>). Only those 
found in `~/.swiftpm/config/trust-root-certs` are trusted. This means that the signature check will always fail unless the `trust-root-certs` directory is set up:

```bash
$ swift package-collection add https://www.example.com/packages.json
The collection's signature cannot be verified due to missing configuration.
```

Users can explicitly specify they trust a publisher and any collections they publish, by obtaining that publisher's root certificate and saving it to `~/.swiftpm/config/trust-root-certs`. The 
root certificates must be DER-encoded. Since SwiftPM trusts all certificate chains under a root, depending on what roots are installed, some publishers may already be trusted implicitly and 
users don't need to explicitly specify each one. 

#### Unsigned package collections

Users will get an error when trying to add an unsigned package collection:

```bash
$ swift package-collection add https://www.example.com/packages.json
The collection is not signed. If you would still like to add it please rerun 'add' with '--trust-unsigned'.
```

To continue user must confirm their trust by passing the `--trust-unsigned` flag:

```bash
$ swift package-collection add https://www.example.com/packages.json --trust-unsigned
```

The `--skip-signature-check` flag has no effects on unsigned collections.


## Usage

```
package-collection add <collection-url> [--order=<order>] [--trust-unsigned] [--skip-signature-check] [--package-path=<package-path>] [--cache-path=<cache-path>] [--config-path=<config-path>] [--security-path=<security-path>] [--scratch-path=<scratch-path>]     [--swift-sdks-path=<swift-sdks-path>] [--toolset=<toolset>...] [--pkg-config-path=<pkg-config-path>...]   [--enable-dependency-cache|disable-dependency-cache]  [--enable-build-manifest-caching|disable-build-manifest-caching] [--manifest-cache=<manifest-cache>] [--enable-experimental-prebuilts|disable-experimental-prebuilts] [--verbose] [--very-verbose|vv] [--quiet] [--color-diagnostics|no-color-diagnostics] [--disable-sandbox] [--netrc] [--enable-netrc|disable-netrc] [--netrc-file=<netrc-file>] [--enable-keychain|disable-keychain] [--resolver-fingerprint-checking=<resolver-fingerprint-checking>] [--resolver-signing-entity-checking=<resolver-signing-entity-checking>] [--enable-signature-validation|disable-signature-validation] [--enable-prefetching|disable-prefetching] [--force-resolved-versions|disable-automatic-resolution|only-use-versions-from-resolved-file] [--skip-update] [--disable-scm-to-registry-transformation] [--use-registry-identity-for-scm] [--replace-scm-with-registry]  [--default-registry-url=<default-registry-url>] [--configuration=<configuration>] [--=<Xcc>...] [--=<Xswiftc>...] [--=<Xlinker>...] [--=<Xcxx>...]    [--triple=<triple>] [--sdk=<sdk>] [--toolchain=<toolchain>]   [--swift-sdk=<swift-sdk>] [--sanitize=<sanitize>...] [--auto-index-store|enable-index-store|disable-index-store]   [--enable-parseable-module-interfaces] [--jobs=<jobs>] [--use-integrated-swift-driver] [--explicit-target-dependency-import-check=<explicit-target-dependency-import-check>] [--build-system=<build-system>] [--=<debug-info-format>]      [--enable-dead-strip|disable-dead-strip] [--disable-local-rpath] [--version] [--help]
```

- term **collection-url**:

*URL of the collection to add.*


- term **--order=\<order\>**:

*Sort order for the added collection.*


- term **--trust-unsigned**:

*Trust the collection even if it is unsigned.*


- term **--skip-signature-check**:

*Skip signature check if the collection is signed.*


- term **--package-path=\<package-path\>**:

*Specify the package path to operate on (default current directory). This changes the working directory before any other operation.*


- term **--cache-path=\<cache-path\>**:

*Specify the shared cache directory path.*


- term **--config-path=\<config-path\>**:

*Specify the shared configuration directory path.*


- term **--security-path=\<security-path\>**:

*Specify the shared security directory path.*


- term **--scratch-path=\<scratch-path\>**:

*Specify a custom scratch directory path. (default .build)*


- term **--swift-sdks-path=\<swift-sdks-path\>**:

*Path to the directory containing installed Swift SDKs.*


- term **--toolset=\<toolset\>**:

*Specify a toolset JSON file to use when building for the target platform. Use the option multiple times to specify more than one toolset. Toolsets will be merged in the order they're specified into a single final toolset for the current build.*


- term **--pkg-config-path=\<pkg-config-path\>**:

*Specify alternative path to search for pkg-config `.pc` files. Use the option multiple times to
specify more than one path.*


- term **--enable-dependency-cache|disable-dependency-cache**:

*Use a shared cache when fetching dependencies.*


- term **--enable-build-manifest-caching|disable-build-manifest-caching**:


- term **--manifest-cache=\<manifest-cache\>**:

*Caching mode of Package.swift manifests. Valid values are: (shared: shared cache, local: package's build directory, none: disabled)*


- term **--enable-experimental-prebuilts|disable-experimental-prebuilts**:

*Whether to use prebuilt swift-syntax libraries for macros.*


- term **--verbose**:

*Increase verbosity to include informational output.*


- term **--very-verbose|vv**:

*Increase verbosity to include debug output.*


- term **--quiet**:

*Decrease verbosity to only include error output.*


- term **--color-diagnostics|no-color-diagnostics**:

*Enables or disables color diagnostics when printing to a TTY. 
By default, color diagnostics are enabled when connected to a TTY and disabled otherwise.*


- term **--disable-sandbox**:

*Disable using the sandbox when executing subprocesses.*


- term **--netrc**:

*Use netrc file even in cases where other credential stores are preferred.*


- term **--enable-netrc|disable-netrc**:

*Load credentials from a netrc file.*


- term **--netrc-file=\<netrc-file\>**:

*Specify the netrc file path.*


- term **--enable-keychain|disable-keychain**:

*Search credentials in macOS keychain.*


- term **--resolver-fingerprint-checking=\<resolver-fingerprint-checking\>**:


- term **--resolver-signing-entity-checking=\<resolver-signing-entity-checking\>**:


- term **--enable-signature-validation|disable-signature-validation**:

*Validate signature of a signed package release downloaded from registry.*


- term **--enable-prefetching|disable-prefetching**:


- term **--force-resolved-versions|disable-automatic-resolution|only-use-versions-from-resolved-file**:

*Only use versions from the Package.resolved file and fail resolution if it is out-of-date.*


- term **--skip-update**:

*Skip updating dependencies from their remote during a resolution.*


- term **--disable-scm-to-registry-transformation**:

*Disable source control to registry transformation.*


- term **--use-registry-identity-for-scm**:

*Look up source control dependencies in the registry and use their registry identity when possible to help deduplicate across the two origins.*


- term **--replace-scm-with-registry**:

*Look up source control dependencies in the registry and use the registry to retrieve them instead of source control when possible.*


- term **--default-registry-url=\<default-registry-url\>**:

*Default registry URL to use, instead of the registries.json configuration file.*


- term **--configuration=\<configuration\>**:

*Build with configuration*


- term **--=\<Xcc\>**:

*Pass flag through to all C compiler invocations.*


- term **--=\<Xswiftc\>**:

*Pass flag through to all Swift compiler invocations.*


- term **--=\<Xlinker\>**:

*Pass flag through to all linker invocations.*


- term **--=\<Xcxx\>**:

*Pass flag through to all C++ compiler invocations.*


- term **--triple=\<triple\>**:


- term **--sdk=\<sdk\>**:


- term **--toolchain=\<toolchain\>**:


- term **--swift-sdk=\<swift-sdk\>**:

*Filter for selecting a specific Swift SDK to build with.*


- term **--sanitize=\<sanitize\>**:

*Turn on runtime checks for erroneous behavior, possible values: address, thread, undefined, scudo.*


- term **--auto-index-store|enable-index-store|disable-index-store**:

*Enable or disable indexing-while-building feature.*


- term **--enable-parseable-module-interfaces**:


- term **--jobs=\<jobs\>**:

*The number of jobs to spawn in parallel during the build process.*


- term **--use-integrated-swift-driver**:


- term **--explicit-target-dependency-import-check=\<explicit-target-dependency-import-check\>**:

*A flag that indicates this build should check whether targets only import their explicitly-declared dependencies.*


- term **--build-system=\<build-system\>**:


- term **--=\<debug-info-format\>**:

*The Debug Information Format to use.*


- term **--enable-dead-strip|disable-dead-strip**:

*Disable/enable dead code stripping by the linker.*


- term **--disable-local-rpath**:

*Disable adding $ORIGIN/@loader_path to the rpath by default.*


- term **--version**:

*Show the version.*


- term **--help**:

*Show help information.*

