import Testing
import Foundation
@testable import ServerTemplate

struct CrudServerFilesTests {
    @Test
    func testGenTelemetryFileContainsLoggingConfig() {
        let logPath = URL(fileURLWithPath: "/tmp/test.log")

        let logURLPath = CLIURL(logPath)
        
        let generated = CrudServerFiles.genTelemetryFile(
            logLevel: .info,
            logPath: logPath,
            logFormat: .json,
            logBufferSize: 2048
        )

        #expect(generated.contains("file:///tmp/test.log"))
        #expect(generated.contains("let logBufferSize: Int = 2048"))
        #expect(generated.contains("Logger.Level.info"))
        #expect(generated.contains("LogFormat.json"))
    }
}



struct EntryPointTests {
    @Test
    func testGenEntryPointFileContainsServerAddressAndPort() {
        
        let serverAddress = "127.0.0.1"
        let serverPort = 9090
        let code = CrudServerFiles.genEntryPointFile(serverAddress: serverAddress, serverPort: serverPort)
        #expect(code.contains("\"\(serverAddress)\","))
        #expect(code.contains("port: \(serverPort)"))
        #expect(code.contains("configureDatabase"))
        #expect(code.contains("configureTelemetryServices"))
    }
}


struct OpenAPIConfigTests {
    @Test
    func testOpenAPIConfigContainsGenerateSection() {
        let config = CrudServerFiles.getOpenAPIConfig()
        #expect(config.contains("generate:"))
        #expect(config.contains("- types"))
        #expect(config.contains("- server"))
    }
}


struct APIHandlerTests {
    @Test
    func testGenAPIHandlerIncludesOperations() {
        let code = CrudServerFiles.genAPIHandler()
        #expect(code.contains("func listTODOs"))
        #expect(code.contains("func createTODO"))
        #expect(code.contains("func getTODODetail"))
        #expect(code.contains("func deleteTODO"))
        #expect(code.contains("func crash"))
    }
}



