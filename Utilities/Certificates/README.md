# Temporary manual solution for embedding certificates into SwiftPM

Running `./generate.sh` will use SwiftPM's 5.9 feature for embedding resources to generate code and then the script copies it into the `PackageSigning` and `PackageCollectionsSigning` target directories. Whenever there are new certificates to embed, copy them into this directory and update the package manifest. The updated generated source file needs to be checked in.
