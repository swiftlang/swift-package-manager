import MacroDef

struct Font: ExpressibleByFontLiteral {
  init(fontLiteralName: String, size: Int, weight: MacroDef.FontWeight) {
  }
}

let _: Font = #fontLiteral(name: "Comic Sans", size: 14, weight: .thin)
