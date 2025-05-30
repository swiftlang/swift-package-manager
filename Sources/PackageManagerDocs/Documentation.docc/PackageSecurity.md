# Package Security

Learn about the security features that the package manager implements.

## Trust on First Use

The package manager records **fingerprints** of downloaded package versions so that
it can perform [trust-on-first-use](https://en.wikipedia.org/wiki/Trust_on_first_use)
(TOFU). 
That is, when a package version is downloaded for the first time, the package manager trusts that 
it has downloaded the correct contents and requires subsequent downloads of the same 
package version to have the same fingerprint. 
If the fingerprint changes, it might be an indicator that the package has been
compromised and the package manager either warns or returns an error.

Depending on where a package version is downloaded from, a different value is
used as its fingerprint:
                             
| Package Version Origin | Fingerprint |
| ---------------------- | ----------- |
| Git repository         | Git hash of the revision |
| Package registry       | Checksum of the source archive |

The package manager keeps version fingerprints for each package in a single file
under the `~/.swiftpm/security/fingerprints` directory.
  - For a Git repository package, the fingerprint filename takes the form of `{PACKAGE_NAME}-{REPOSITORY_URL_HASH}.json` (such as `LinkedList-5ddbcf15.json`).
  - For a registry package, the fingerprint filename takes the form of `{PACKAGE_ID}.json` (such as `mona.LinkedList.json`).

For packages retrieved from a registry, the package manager expects all registries to provide consistent fingerprints for packages they host.
If registries have conflicting fingerprints, package manager reports that as an error.
This can be tuned down to warning by setting the [build](<doc:SwiftBuild>) option `--resolver-fingerprint-checking` 
to `warn` (default is `strict`).
