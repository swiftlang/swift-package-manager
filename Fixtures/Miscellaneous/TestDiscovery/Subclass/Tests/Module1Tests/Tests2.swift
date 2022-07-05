import XCTest

class Tests3: Tests2 {
    override func test11() {
      print("->Module1::Tests3::test11")
    }

    override func test21() {
      print("->Module1::Tests3::test21")
    }

    func test31() {
      print("->Module1::Tests3::test31")
    }

    func test32() {
      print("->Module1::Tests3::test32")
    }

    func test33() {
      print("->Module1::Tests3::test33")
    }
}

class Tests2: Tests1 {
    func test21() {
      print("->Module1::Tests2::test21")
    }

    func test22() {
      print("->Module1::Tests2::test22")
    }
}
