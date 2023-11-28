@main
struct AsyncMain3 {
  static func main() async {
    print(await getGreeting3())
  }

  static func getGreeting3() async -> String {
      return "Hello, async galaxy"
  }
}
