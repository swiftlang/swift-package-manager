# Add a package

Learn how to add a package to your collection.

## Overview

The [`add` subcommand](<doc:PackageCollectionAdd>) adds a package collection hosted on the web (HTTPS required):

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

Package collection publishers may sign a collection to protect its contents from being tampered with. 
If a collection is signed, SwiftPM will check that the 
signature is valid before importing it and return an error if any of these fails:
- The file's contents, signature excluded, must match what was used to generate the signature. 
In other words, this checks to see if the collection has been altered since it was signed.
- The signing certificate must meet all the [requirements](<doc:PackageCollectionSigning>).

```bash
$ swift package-collection add https://www.example.com/bad-packages.json
The collection's signature is invalid. If you would like to continue please rerun command with '--skip-signature-check'.
```

Users may continue adding the collection despite the error or preemptively skip the signature check on a package collection by passing the `--skip-signature-check` flag:

```bash
$ swift package-collection add https://www.example.com/packages.json --skip-signature-check
```

For package collections hosted on the web, publishers may ask SwiftPM to [enforce the signature requirement](<doc:PackageCollectionSigning>). If a package collection is
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

On non-Apple platforms, there are no trusted root certificates by default other than those shipped with the [certificate-pinning configuration](<doc:PackageCollectionSigning>). Only those 
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
