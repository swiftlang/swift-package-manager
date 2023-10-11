@main
struct AsyncMain3 {
  static func main() async {
    print(getGreeting3())
  }

  static func getGreeting3() -> String {
      return "Hello, async galaxy"
  }
}
