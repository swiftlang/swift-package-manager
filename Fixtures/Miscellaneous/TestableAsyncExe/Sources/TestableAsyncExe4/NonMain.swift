@main
struct AsyncMain4 {
  static func main() async {
    print(await getGreeting4())
  }

  static func getGreeting4() async -> String {
      return "Hello, async universe"
  }
}
