import Testing
import BinarySymbols
import Basics

@Suite
struct LLVMObjdumpSymbolProviderTests {
    private func getSymbols(_ dump: String) throws -> ReferencedSymbols {
        var symbols = ReferencedSymbols()
        // Placeholder executable path since we won't actually run it
        try LLVMObjdumpSymbolProvider(objdumpPath: AbsolutePath.root).parse(output: dump, symbols: &symbols)
        return symbols
    }

    @Test
    func ignoresHeaderLines() throws {
        let output = try getSymbols(
            """

            /usr/lib/aarch64-linux-gnu/libc.so.6:   file format elf64-littleaarch64

            SYMBOL TABLE:

            DYNAMIC SYMBOL TABLE:
            """
        )

        #expect(output.defined.isEmpty)
        #expect(output.undefined.isEmpty)
    }

    @Test
    func detectsDefinedSymbol() throws {
        let output = try getSymbols("00000000000e0618 g    DF .text  0000000000000018  GLIBC_2.17  __ppoll_chk")

        #expect(output.defined.contains("__ppoll_chk"))
        #expect(output.undefined.isEmpty)
    }

    @Test
    func detectsUndefinedSymbol() throws {
        let output = try getSymbols("0000000000000000         *UND*  0000000000000000 calloc")

        #expect(output.defined.isEmpty)
        #expect(output.undefined.contains("calloc"))
    }

    @Test
    func treatsCommonSymbolsAsDefined() throws {
        let output = try getSymbols("0000000000000004       O *COM*  0000000000000004 __libc_enable_secure_decided")

        #expect(output.defined.contains("__libc_enable_secure_decided"))
        #expect(output.undefined.isEmpty)
    }
}
