# ``PackageDescription/Platform/!=(_:_:)``

@Metadata {
   @DocumentationExtension(mergeBehavior: override)
}

Returns a Boolean value indicating whether two values are not equal.

- Parameters:
  - lhs: A value to compare.
  - rhs: Another value to compare.

Inequality is the inverse of equality. For any values a and b, `a != b` implies that `a == b` is `false`.

This is the default implementation of the not-equal-to operator (`!=`) for any type that conforms to `Equatable`.
