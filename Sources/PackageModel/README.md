# PackageModel Library

This library defines the model objects for describing Packages.

The intent of this library is that these should be pure model objects and
contain a complete specification of a single local package. The convention
system is encoded in the model via the
[`PackageLoading`](../PackageLoading/README.md) library, and then the individual
packages are combined into a cohesive
[`PackageGraph`](../PackageGraph/README.md) for the high-level operations.

NOTE: This library contains types which shadows definitions from the
[`PackageDescription`](../PackageDescription/README.md) library, but they are
fundamentally different -- those model objects describe the model of the package
*manifest* itself, not the overall package.
