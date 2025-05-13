internal import Testing
private import SystemPackage
private import BinaryArtifactAudit

@Suite
struct ObjdumpSymbolProviderTests {
    private func getSymbols(_ dump: String) throws -> ReferencedSymbols {
        var symbols = ReferencedSymbols()
        try ObjdumpSymbolProvider(objdumpPath: FilePath()).parse(output: dump, symbols: &symbols)
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
        let output = try getSymbols("0000000000000000      DF *UND*  0000000000000000 (GLIBC_2.17) __tls_get_addr")

        #expect(output.defined.isEmpty)
        #expect(output.undefined.contains("__tls_get_addr"))
    }

    @Test
    func treatsCommonSymbolsAsDefined() throws {
        let output = try getSymbols("0000000000000004       O *COM*  0000000000000004 __libc_enable_secure_decided")

        #expect(output.defined.contains("__libc_enable_secure_decided"))
        #expect(output.undefined.isEmpty)
    }
}
