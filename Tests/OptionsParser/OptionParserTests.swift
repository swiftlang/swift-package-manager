 import OptionsParser
import XCTest

class OptionsParserTests: XCTestCase {
    func testNoArguments() throws {
        let (mode, flags): (Mode?, [Flag]) = try parse(arguments: [])

        XCTAssertNil(mode)
        XCTAssertEqual(flags.count, 0)
    }

    func testModeA() throws {
        let (mode, flags): (Mode?, [Flag]) = try parse(arguments: ["--A"])

        XCTAssertEqual(mode, .A)
        XCTAssertEqual(flags.count, 0)
    }

    func testModeB() throws {
        let (mode, flags): (Mode?, [Flag]) = try parse(arguments: ["--B"])

        XCTAssertEqual(mode, .B)
        XCTAssertEqual(flags.count, 0)
    }

    func testModeAFlagD() throws {
        let (mode, flags): (Mode?, [Flag]) = try parse(arguments: ["--A", "--D"])

        XCTAssertEqual(mode, .A)
        XCTAssertEqual(flags, [Flag.D])
    }

    func testModeAFlagDE() throws {
        let (mode, flags): (Mode?, [Flag]) = try parse(arguments: ["--A", "--D", "--E"])

        XCTAssertEqual(mode, .A)
        XCTAssertEqual(flags, [Flag.D, Flag.E])
    }

    func testMultiModes() {
        do {
            let _: (Mode?, [Flag]) = try parse(arguments: ["--A", "--B"])
            XCTFail()
        } catch Error.MultipleModesSpecified(let args) {
            XCTAssertEqual(args, ["A", "B"])
        } catch {
            XCTFail()
        }
    }

    func testAssociatedValue() throws {
        let (_, flags): (Mode?, [Flag]) = try parse(arguments: ["--F", "foo", "--G", "123"])

        XCTAssertEqual(flags, [.F("foo"), .G(123)])
    }

    func testThrowsIfNoAssociatedValue() {
        do {
            let _: (Mode?, [Flag]) = try parse(arguments: ["--F"])
            XCTFail()
        } catch Error.ExpectedAssociatedValue {
            // güd
        } catch {
            XCTFail("\(error)")
        }
    }

    func testThrowsIfAssociatedValueWithWrongFlag() {
        do {
            let _: (Mode?, [Flag]) = try parse(arguments: ["--E=foo", "--G=123"])
            XCTFail()
        } catch Error.UnexpectedAssociatedValue {
            // güd
        } catch {
            XCTFail("\(error)")
        }
    }

    func testThrowsIfAssociatedValueWithWrongMode() {
        do {
            let _: (Mode?, [Flag]) = try parse(arguments: ["--A=foo", "--G=123"])
            XCTFail()
        } catch Error.UnexpectedAssociatedValue {
            // güd
        } catch {
            XCTFail("\(error)")
        }
    }

    func testAssignedAssociatedValue() throws {
        let (mode, flags): (Mode?, [Flag]) = try parse(arguments: ["--F=foo", "--G=123"])

        XCTAssertNil(mode)
        XCTAssertEqual(flags, [.F("foo"), .G(123)])
    }

    func testCanUnderstandMultipleShortFlags() throws {
        let (mode, flags): (Mode?, [Flag]) = try parse(arguments: ["-HJI"])

        XCTAssertNil(mode)
        XCTAssertEqual(flags, [.H, .J, .I])
    }

    func testCanUnderstandMultipleShortFlagsWithAFinalAssociatedValue() throws {
        let (mode, flags): (Mode?, [Flag]) = try parse(arguments: ["-HJIKHJI"])

        XCTAssertNil(mode)
        XCTAssertEqual(flags, [.H, .J, .I, .K("HJI")])
    }
}


//MARK: Mode/Flag

enum Mode: String, Argument {
    case A, B, C

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "--A":
            self = A
        case "--B":
            self = B
        case "--C":
            self = C
        default:
            return nil
        }
    }
}

enum Flag: Argument, Equatable {
    case D, E, F(String), G(Int), H, I, J, K(String)

    init?(argument: String, pop: () -> String?) throws {
        switch argument {
        case "--D":
            self = D
        case "--E":
            self = E
        case "--F":
            guard let str = pop() else { throw Error.ExpectedAssociatedValue("") }
            self = F(str)
        case "--G":
            guard let str = pop(), int = Int(str) else { throw Error.ExpectedAssociatedValue("") }
            self = G(int)
        case "-H":
            self = .H
        case "-I":
            self = .I
        case "-J":
            self = .J
        case "-K":
            guard let str = pop() else { throw Error.ExpectedAssociatedValue("") }
            self = .K(str)
        default:
            return nil
        }
    }
}

func ==(lhs: Flag, rhs: Flag) -> Bool {
    switch (lhs, rhs) {
    case (.D, .D), (.E, .E):
        return true
    case (.F(let a), .F(let b)) where a == b:
        return true
    case (.G(let a), .G(let b)) where a == b:
        return true
    case (.H, .H), (.I, .I), (.J, .J):
        return true
    case (.K(let a), .K(let b)) where a == b:
        return true
    default:
        return false
    }
}
