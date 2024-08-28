# Package Security

This document provides an overview of security features that SwiftPM implements.

## Trust on First Use

SwiftPM records **fingerprints** of downloaded package versions so that
it can perform [trust-on-first-use](https://en.wikipedia.org/wiki/Trust_on_first_use)
(TOFU). That is, when a package version is downloaded for the first time,
SwiftPM trusts that it has downloaded the correct contents and requires
subsequent downloads of the same package version to have the same
fingerprint. If the fingerprint changes, it might be an indicator that the
package has been compromised and SwiftPM will either warn or return an error.

Depending on where a package version is downloaded from, different value is
used as its fingerprint:
                             
| Package Version Origin | Fingerprint |
| ---------------------- | ----------- |
| Git repository         | Git hash of the revision |
| Package registry       | Checksum of the source archive |

All version fingerprints of a package are kept in a single file
under the `~/.swiftpm/security/fingerprints` directory.
  - For a Git repository package, the fingerprint filename takes the form of `{PACKAGE_NAME}-{REPOSITORY_URL_HASH}.json` (e.g., `LinkedList-5ddbcf15.json`).
  - For a registry package, the fingerprint filename takes the form of `{PACKAGE_ID}.json` (e.g., `mona.LinkedList.json`).

### Using fingerprints for TOFU

When a package version is downloaded from Git repository or registry for
the first time, SwiftPM simply saves the fingerprint to the designated
file in the `~/.swiftpm/security/fingerprints` directory.
                                    
Otherwise, SwiftPM compares fingerprint of the downloaded package version
with that saved from previous download. The two fingerprint values must match or
else SwiftPM will throw an error. This can be tuned down to warning by setting
the build option `--resolver-fingerprint-checking` to `warn` (default is `strict`).                                
                                                                              
Note that in case of registry packages, a package version's fingerprint
must be consistent across registries or else there will be a TOFU failure.
As an example, suppose a package version was originally downloaded from
registry A and the source archive checksum was saved as the fingerprint. Later
the package version is downloaded again but from registry B and has a different
fingerprint. This would trigger a TOFU failure since the fingerprint should
be consistent across the registries.
