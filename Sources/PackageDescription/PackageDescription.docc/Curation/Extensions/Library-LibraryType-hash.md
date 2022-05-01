# ``PackageDescription/Product/Library/LibraryType/hash(into:)``

@Metadata {
   @DocumentationExtension(mergeBehavior: override)
}

Hashes the essential components of this value by feeding them into the given hasher.

Implement this method to conform to the Hashable protocol. The components used for hashing must be the same as the components compared in your type’s == operator implementation. Call hasher.combine(_:) with each of these components.

> Important:
> Never call finalize() on hasher. Doing so may become a compile-time error in the future.

- Parameter into: The hasher to use when combining the components of this instance.
