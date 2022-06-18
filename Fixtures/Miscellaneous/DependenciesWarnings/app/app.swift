import dep1
import dep2

@main
struct App {
  var deprecated: DeprecatedApp

  public static func main() {
    print("hello, world!")
  }
}

@available(*, deprecated)
struct DeprecatedApp {
}
