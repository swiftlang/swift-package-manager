
public enum FontWeight {
  case thin
  case normal
  case medium
  case semiBold
  case bold
}

public protocol ExpressibleByFontLiteral {
  init(fontLiteralName: String, size: Int, weight: FontWeight)
}

/// Font literal similar to, e.g., #colorLiteral.
@freestanding(expression) public macro fontLiteral<T>(name: String, size: Int, weight: FontWeight) -> T = #externalMacro(module: "MacroImpl", type: "FontLiteralMacro")
  where T: ExpressibleByFontLiteral