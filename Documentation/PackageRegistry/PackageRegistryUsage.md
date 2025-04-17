# Package Registry Usage

## Table of Contents

  * [Getting Started](#getting-started)
    + [Configuring a registry](#configuring-a-registry)
    + [Adding a registry package dependency](#adding-a-registry-package-dependency)
    + [Registry authentication](#registry-authentication)
  * [Dependency Resolution Using Registry](#dependency-resolution-using-registry)
    + [Using registry for source control dependencies](#using-registry-for-source-control-dependencies)
  * [Dependency Download From Registry](#dependency-download-from-registry)
    + [Checksum TOFU](#checksum-tofu)
    + [Validating signed packages](#validating-signed-packages)
      - [Trusted vs. untrusted certificate](#trusted-vs-untrusted-certificate)
      - [Certificate policies](#certificate-policies)
      - [Publisher TOFU](#publisher-tofu)
  * [Publishing to Registry](#publishing-to-registry)
    + [Package release metadata](#package-release-metadata)
    + [Package signing](#package-signing)
      - [Signature formats](#signature-formats)
      - [Signed contents](#signed-contents)
        * [Source archive](#source-archive)
        * [Package release metadata](#package-release-metadata-1)
        * [Package manifest(s)](#package-manifest-s-)
  * [SwiftPM Registry Configuration](#swiftpm-registry-configuration)
    + [Registry-to-scope mappings](#registry-to-scope-mappings)
      - [`swift package-registry set` subcommand](#-swift-package-registry-set--subcommand)
    + [Security configuration](#security-configuration)

## Getting Started

SwiftPM supports downloading dependencies from any package registry that implements 
[SE-0292](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0292-package-registry-service.md)
and the corresponding [service specification](Registry.md). 

In a registry, packages are identified by [package identifier](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0292-package-registry-service.md#package-identity)
in the form of `scope.package-name`.

### Configuring a registry

A registry can be configured in SwiftPM at two levels:
 - Project: the registry will be used for packages within the project. Settings are stored in `.swiftpm/configuration/registries.json`.
 - User: the registry will be used for all projects for the user. Settings are stored in `~/.swiftpm/configuration/registries.json`.

One could use the [`swift package-registry set` subcommand](#swift-package-registry-set-subcommand) 
to assign a registry URL:

```bash
$ swift package-registry set https://packages.example.com 
```

The above sets registry to `https://packages.example.com` at project level. Pass 
the `--global` option to set registry at user level:

```bash
$ swift package-registry set --global https://packages.example.com 
```

The resulting `registries.json` would look something like:

```json
{
  "registries" : {
    "[default]" : {
      "url": "https://packages.example.com"
    }   
  },
  "version" : 1
}
```

The JSON key `[default]` means that the registry at `https://packages.example.com` is 
"unscoped" and will be applied when there is no registry association found for 
a given scope. 

In this example, `https://packages.example.com` will be applied to all scopes.

### Adding a registry package dependency

A registry package dependency is declared in `Package.swift` using the
package identifier. For example: 

```swift
dependencies: [
    .package(id: "mona.LinkedList", .upToNextMajor(from: "1.0.0")),
],
```

SwiftPM will query the registry mapped to a package's scope to 
resolve and download the appropriate release version.  

### Registry authentication

If a registry requires authentication, it can be set up by using the 
[`swift package-registry login` subcommand](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0378-package-registry-auth.md#new-login-subcommand)
introduced by SE-0378:

```bash
$ swift package-registry login
OVERVIEW: Log in to a registry

USAGE: swift package-registry login [<url>] [--username <username>] [--password <password>] [--token <token>] [--no-confirm]

ARGUMENTS:
  <url>                   The registry URL

OPTIONS:
  --username <username>   Username
  --password <password>   Password
  --token <token>         Access token
  --no-confirm            Allow writing to netrc file without confirmation
```

Currently, basic and token authentication are supported.

Provide the credentials either by setting the corresponding options
(i.e., one of username/password or access token) or when prompted:

```bash
$ swift package-registry login https://packages.example.com
```

SwiftPM will save the credentials to the operating system's credential store
(e.g., Keychain in macOS) or netrc file (which by default is located at `~/.netrc`) 
and apply them automatically when making registry API requests.

## Dependency Resolution Using Registry

Resolving a registry dependency involves these steps:
1. Fetch a package's available versions by calling the [list package releases](Registry.md#41-list-package-releases) API.
2. Compute the dependency graph by [fetching manifest(s) for a package release](Registry.md#43-fetch-manifest-for-a-package-release).
3. Pinpoint the package version to use.

### Using registry for source control dependencies 

Here is an example of a source control dependency:

```swift
dependencies: [
    .package(id: "https://github.com/mona/LinkedList", .upToNextMajor(from: "1.0.0")),
],
```

Registry can be used for source control dependencies as well. This is 
particularly useful when there is a "mixed" graph (i.e., a dependency 
graph that has both source control and registry dependencies). SwiftPM
considers packages with different origins to be different, so if a
package is referenced as both a registry (e.g., `mona.LinkedList`) and
source control (e.g., `https://github.com/mona/LinkedList`) dependency,
they are considered different even though they are the same package,
and would result in symbol clashes.

SwiftPM can deduplicate packages by performing a 
[lookup on the source control URL](Registry.md#endpoint-5)
(e.g., `https://github.com/mona/LinkedList`) to see if it is associated with 
any package identifier (e.g., `mona.LinkedList`).

One can control if/how SwiftPM should use registry in conjunction with 
source control dependencies by setting one of these flags:
- `--disable-scm-to-registry-transformation` (default): SwiftPM will not transform source control dependency to registry dependency. Source control dependency will be downloaded from its corresponding URL, while registry dependency will be resolved and downloaded using the configured registry (if any).
- `--use-registry-identity-for-scm`: SwiftPM will look up source control dependencies in the registry and use their registry identity whenever possible to help deduplicate packages across the two origins. In other words, suppose `mona.LinkedList` is the package identifier for `https://github.com/mona/LinkedList`, then SwiftPM will treat both references in the dependency graph as the same package. 
- `--replace-scm-with-registry`: SwiftPM will look up source control dependencies in the registry and use the registry to retrieve them instead of source control when possible. In other words, SwiftPM will attempt to download a source control dependency from the registry first, and fall back to cloning the source repository iff the dependency is not found in the registry.

## Dependency Download From Registry

After a registry dependency is resolved, SwiftPM can
[download source archive](Registry.md#endpoint-4)
of the computed package version from the registry.

### Checksum TOFU 

SwiftPM performs checksum TOFU 
([trust-on-first-use](https://en.wikipedia.org/wiki/Trust_on_first_use)) 
on the downloaded source archive. If the archive is downloaded
for the first time, SwiftPM 
[fetches metadata of the package release](Registry.md#endpoint-2)
to obtain the expected checksum. Otherwise, SwiftPM
compares the checksum with that in local storage (`~/.swiftpm/security/fingerprints/`)
saved from previous download.

If checksum of the downloaded archive doesn't match the expected
or previous value, SwiftPM will fail the build. This can be
tuned down from error to warning by setting the build option 
`--resolver-fingerprint-checking` to `warn` (default is `strict`).

Checksum TOFU is also done for manifests downloaded from registry. 

### Validating signed packages

[SE-0391](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md#package-signing)
adds package signing support to SwiftPM. SwiftPM determines if
a downloaded archive is signed by checking for presence of the
`X-Swift-Package-Signature-Format` and `X-Swift-Package-Signature`
headers in the HTTP response.

SwiftPM then performs a series of validations based on user's
[security configuration](#security-configuration).
- If the archive is unsigned, SwiftPM will error/prompt/warn/allow 
based on the `signing.onUnsigned` configuration. 
- If the archive is signed, SwiftPM will validate the signature and
the signing certificate chain. (see the following sections for details)

#### Trusted vs. untrusted certificate

A certificate is trusted if it is chained to any root in SwiftPM's 
trust store, which consists of:
- SwiftPM's default trust store, if `signing.includeDefaultTrustedRootCertificates` is `true`.
- Custom root(s) in the configured trusted roots directory at `signing.trustedRootCertificatesPath`. Certificates must be DER-encoded.

Otherwise, a certificate is untrusted and handled according to the 
`signing.onUntrustedCertificate` configuration. If user opts to
continue with the untrusted certificate, SwiftPM will proceed with
the archive as if it were an unsigned package.

#### Certificate policies

SwiftPM requires all certificates used for package signing to have 
the "code signing" extended key usage extension. They must also 
satisfy the core policies from 
[RFC 5280](https://www.rfc-editor.org/rfc/rfc5280), as implemented
by [swift-certificates](https://github.com/apple/swift-certificates). 

User can configure certificate expiry and revocation check 
through the `signing.validationChecks.certificateExpiration` 
and `signing.validationChecks.certificateRevocation` configuration,
respectively. Note that revocation check implicitly requires
expiry check.
   
An invalid signing certificate would result in SwiftPM rejecting
the archive.

#### Publisher TOFU

Some certificates allow SwiftPM to extract additional information 
about the signing identity. For packages signed with these certificates, 
SwiftPM will perform publisher TOFU to ensure the signer remains the 
same across all versions of the package. 

The `--resolver-signing-entity-checking` option controls whether publisher 
mismatch should result in a warning (`warn`) or error (`strict`). 
Data used by publisher TOFU is saved to `~/.swiftpm/security/signing-entities/`.

## Publishing to Registry

[`swift package-registry publish`](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md#new-package-registry-publish-subcommand)
is an all-in-one command for publishing a package release to registry:

```bash
OVERVIEW: Publish to a registry

USAGE: swift package-registry publish <package-id> <package-version> [--url <url>] [--scratch-directory <scratch-directory>] [--metadata-path <metadata-path>] [--signing-identity <signing-identity>] [--private-key-path <private-key-path>] [--cert-chain-paths <cert-chain-paths> ...] [--dry-run]

ARGUMENTS:
  <package-id>            The package identifier.
  <package-version>       The package release version being created.

OPTIONS:
  --url, --registry-url <url>
                          The registry URL.
  --scratch-directory <scratch-directory>
                          The path of the directory where working file(s) will be written.
  --metadata-path <metadata-path>
                          The path to the package metadata JSON file if it is not 'package-metadata.json' in the package directory.
  --signing-identity <signing-identity>
                          The label of the signing identity to be retrieved from the system's identity store if supported.
  --private-key-path <private-key-path>
                          The path to the certificate's PKCS#8 private key (DER-encoded).
  --cert-chain-paths <cert-chain-paths>
                          Path(s) to the signing certificate (DER-encoded) and optionally the rest of the certificate chain. Certificates
                          should be ordered with the leaf first and the root last.
  --dry-run               Dry run only; prepare the archive and sign it but do not publish to the registry.
```
 
The command creates source archive for the package release,
optionally signs the package release, and 
[publishes the package release](Registry.md#endpoint-6)
to the registry.

If authentication is required for package publication, 
package author should [configure registry login](#registry-authentication)
before running `publish`.

### Package release metadata

Package author can specify a custom location of the package 
release metadata file by setting the `--metadata-path` option 
of the `publish` subcommand. Otherwise, by default SwiftPM 
looks for a file named `package-metadata.json` in the 
package directory.

Contents of the metadata file must conform to the 
[JSON schema](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md#package-release-metadata-standards)
defined in SE-0391. Also refer to registry documentation 
for any additional requirements.
 
### Package signing

A registry may support or require signing. To sign a package
release, package author will need to set either the `signing-identity`
(for reading from operating system's identity store such as Keychain in macOS),
or `private-key-path` and `cert-chain-paths` (for reading from files)
options of the `publish` subcommand such that SwiftPM can
locate the signing key and certificate.

If the certificate chain's root and intermediates are known by SwiftPM,
then package author would only need to provide the leaf signing
certificate in `cert-chain-paths`. 

Otherwise, the entire certificate chain should be provided as 
`cert-chain-paths` so that all of the certificates will be 
included in the signature and make it possible for SwiftPM 
to reconstruct the certificate chain for validation later. 
This is applicable to `signing-identity` as well 
(i.e., `signing-identity` can be used in combination with 
`cert-chain-paths` to provide the entire certificate chain).

If the root of the signing certificate is not in SwiftPM's
default trust store, package author is responsible for 
telling package users to include the root certificate in their local 
[trust roots](#trusted-vs-untrusted-certificate) 
directory, or else [signature validation](#validating-signed-packages) 
may fail upon download because the signing certificate is not trusted.

Refer to registry documentation for its certificate policy.

#### Signature formats

| Signature Format | Specification |
| ---------------- | ------------- |
| `cms-1.0.0`      | [SE-391](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0391-package-registry-publish.md#package-signature-format-cms-100) |

Since there is only one supported signature format, all
signatures produced by SwiftPM are in `cms-1.0.0`.

#### Signed contents

##### Source archive

The signature is detached and sent as part of the HTTP request to the
publish API. It is included in the source archive download response as
HTTP headers, and is part of the package release metadata.

##### Package release metadata

The signature is detached and sent as part of the HTTP request to the
publish API. The current API specification does not include an endpoint
for fetching this metadata in its original form.

##### Package manifest(s)

`Package.swift` and version-specific manifests are individually signed.
The signature is embedded in the corresponding manifest file. The source
archive is generated and signed **after** manifest signing. 

```swift
// swift-tools-version: 5.7

import PackageDescription
let package = Package(
    name: "library",
    products: [ .library(name: "library", targets: ["library"]) ],
    targets: [ .target(name: "library") ]
)

// signature: cms-1.0.0;l1TdTeIuGdNsO1FQ0ptD64F5nSSOsQ5WzhM6/7KsHRuLHfTsggnyIWr0DxMcBj5F40zfplwntXAgS0ynlqvlFw==
```

When a manifest is fetched from the registry, SwiftPM checks if the
containing source archive is signed by fetching the package release 
metadata. It is a failure if the source archive is signed but the 
manifest is not. SwiftPM will extract and parse signature from 
the manifest then validate it similar to what is done for 
[source archive signature](#validating-signed-packages).

SwiftPM performs publisher TOFU to ensure it remains consistent
for the package. This implies the signer of manifests and source
archive must be the same.

To reduce the amount of logging and thus noise, diagnostics related 
to manifest signature validation are set to DEBUG level. Only when 
user chooses the `prompt` option for unsigned packages or packages 
signed with an untrusted certificate would SwiftPM behave like 
source archive validation.  

## SwiftPM Registry Configuration

### Registry-to-scope mappings

When resolving or downloading registry packages, SwiftPM looks at the
registry-to-scope mappings in project and user-level configuration to
determine which registry is assigned for a package's scope.

For example, given the following configuration files:

```json
// User-level configuration (~/.swiftpm/configuration/registries.json)
{
  "registries": {
    "[default]": {
      "url": "https://global.example.com"
    },
    "foo": {
      "url": "https://global.example.com"
    },
  },
  "version": 1
}

// Local configuration (.swiftpm/configuration/registries.json)
{
  "registries": {
    "foo": {
      "url": "https://local.example.com"
    }
  },
  "version": 1
}
```

- For package `foo.LinkedList`, the registry at `https://local.example.com` is used. (Local configuration has higher precedence than user-level configuration.)
- For package `bar.LinkedList`, the registry at `https://global.example.com` is used. (No mapping for scope `bar` is found, so `[default]` is used.)

#### `swift package-registry set` subcommand

```bash
$ swift package-registry set 
OVERVIEW: Set a custom registry

USAGE: swift package-registry set [--global] [--scope <scope>] <url>

ARGUMENTS:
  <url>                   The registry URL

OPTIONS:
  --global                Apply settings to all projects for this user
  --scope <scope>         Associate the registry with a given scope
```

This subcommand is used to assign registry at project or user-level:

```bash
# project-level
$ swift package-registry set https://packages.example.com 

# user-level
$ swift package-registry set --global https://global.example.com 
```

For a specific scope:

```bash
# project-level
$ swift package-registry set --scope foo https://local.example.com

# user-level
$ swift package-registry set --scope foo --global https://global.example.com  
```

To remove a registry assignment, use the `swift package-registry unset` subcommand.
  
### Security configuration

Registry security configuration are specified in the user-level `registries.json`
(`~/.swiftpm/configuration/registries.json`):

```json
{
  "security": {
    "default": {
      "signing": {
        "onUnsigned": "prompt", // One of: "error", "prompt", "warn", "silentAllow"
        "onUntrustedCertificate": "prompt", // One of: "error", "prompt", "warn", "silentAllow"
        "trustedRootCertificatesPath": "~/.swiftpm/security/trusted-root-certs/",
        "includeDefaultTrustedRootCertificates": true,
        "validationChecks": {
          "certificateExpiration": "disabled", // One of: "enabled", "disabled"
          "certificateRevocation": "disabled"  // One of: "strict", "allowSoftFail", "disabled"
        }
      }
    },
    "registryOverrides": {
      // The example shows all configuration overridable at registry level
      "packages.example.com": {
        "signing": {
          "onUnsigned": "warn",
          "onUntrustedCertificate": "warn",
          "trustedRootCertificatesPath": <STRING>,
          "includeDefaultTrustedRootCertificates": <BOOL>,
          "validationChecks": {
            "certificateExpiration": "enabled",
            "certificateRevocation": "allowSoftFail"
          }
        }
      }
    },
    "scopeOverrides": {
      // The example shows all configuration overridable at scope level
      "mona": {
        "signing": {
          "trustedRootCertificatesPath": <STRING>,
          "includeDefaultTrustedRootCertificates": <BOOL>
        }
      }
    },
    "packageOverrides": {
      // The example shows all configuration overridable at package level
      "mona.LinkedList": {
        "signing": {
          "trustedRootCertificatesPath": <STRING>,
          "includeDefaultTrustedRootCertificates": <BOOL>
        }
      }
    }
  },
  ...
}
```

There are multiple levels of overrides. Configuration for a 
package is computed using values from the following 
(in descending precedence):
1. `packageOverrides` (if any)
1. `scopeOverrides` (if any)
1. `registryOverrides` (if any)
1. `default`

The `default` JSON object in the example above contains all 
configurable security options and their default value when 
there is no override.

- `signing.onUnsigned`: Indicates how SwiftPM will handle an unsigned package.

  | Option        | Description                                               |
  | ------------- | --------------------------------------------------------- |
  | `error`       | SwiftPM will reject the package and fail the build. |
  | `prompt`      | SwiftPM will prompt user to see if the unsigned package should be allowed. <ul><li>If no, SwiftPM will reject the package and fail the build.</li><li>If yes and the package has never been downloaded, its checksum will be stored for [checksum TOFU](#checksum-tofu). Otherwise, if the package has been downloaded before, its checksum must match the previous value or else SwiftPM will reject the package and fail the build.</li></ul> SwiftPM will record user's response to prevent repetitive prompting. |
  | `warn`        | SwiftPM will not prompt user but will emit a warning before proceeding. |
  | `silentAllow` | SwiftPM will allow the unsigned package without prompting user or emitting warning. |

- `signing.onUntrustedCertificate`: Indicates how SwiftPM will handle a package signed with an [untrusted certificate](#trusted-vs-untrusted-certificate).

  | Option        | Description                                               |
  | ------------- | --------------------------------------------------------- |
  | `error`       | SwiftPM will reject the package and fail the build. |
  | `prompt`      | SwiftPM will prompt user to see if the package signed with an untrusted certificate should be allowed. <ul><li>If no, SwiftPM will reject the package and fail the build.</li><li>If yes, SwiftPM will proceed with the package as if it were an unsigned package.</li></ul> SwiftPM will record user's response to prevent repetitive prompting. |
  | `warn`        | SwiftPM will not prompt user but will emit a warning before proceeding. |
  | `silentAllow` | SwiftPM will allow the package signed with an untrusted certificate without prompting user or emitting warning. |

- `signing.trustedRootCertificatesPath`: Absolute path to the directory containing custom trusted roots. SwiftPM will include these roots in its [trust store](#trusted-vs-untrusted-certificate), and certificates used for package signing must chain to roots found in this store. This configuration allows override at the package, scope, and registry levels.
- `signing.includeDefaultTrustedRootCertificates`: Indicates if SwiftPM should include default trusted roots in its [trust store](#trusted-vs-untrusted-certificate). This configuration allows override at the package, scope, and registry levels.
- `signing.validationChecks`: Validation check settings for the package signature.

  | Validation               | Description                                               |
  | ------------------------ | --------------------------------------------------------------- |
  | `certificateExpiration`  | <ul><li>`enabled`: SwiftPM will check that the current timestamp when downloading falls within the signing certificate's validity period. If it doesn't, SwiftPM will reject the package and fail the build.</li><li>`disabled`: SwiftPM will not perform this check.</li></ul> |
  | `certificateRevocation`  | With the exception of `disabled`, SwiftPM will check revocation status of the signing certificate. Currently, SwiftPM only supports revocation check done through [OCSP](https://www.rfc-editor.org/rfc/rfc6960).<ul><li>`strict`: Revocation check must complete successfully and the certificate must be in good status. SwiftPM will reject the package and fail the build if the revocation status is revoked or unknown (including revocation check not supported or failed).</li><li>`allowSoftFail`: SwiftPM will reject the package and fail the build iff the certificate has been revoked. SwiftPM will allow the certificate's revocation status to be unknown (including revocation check not supported or failed).</li><li>`disabled`: SwiftPM will not perform this check.</li></ul> |
