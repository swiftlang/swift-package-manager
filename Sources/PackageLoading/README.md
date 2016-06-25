# PackageLoading Library

This library defines the logic which translates between the Swift package
manager conventions and the underlying project model.

The intent is that it is largely a transformation taking the input project model
objects descripted in a manifest, applying the conventions and

Ultimately, this library should *only* deal with the content which is _local_ to
a single package. Any cross-package information should be managed by the
[`PackageGraph`](../PackageGraph/README.md) module.
