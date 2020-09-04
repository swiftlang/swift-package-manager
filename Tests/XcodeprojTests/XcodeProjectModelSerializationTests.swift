/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import TSCBasic
import SPMTestSupport
import Xcodeproj
import XCTest

class XcodeProjectModelSerializationTests: XCTestCase {
    
    func testBasicProjectSerialization() {
        // Create a project.
        let proj = Xcode.Project()
        
        // Serialize it to a property list.
        let plist = proj.generatePlist()
        
        // Assert various things about the property list.
        guard case let .dictionary(topLevelDict) = plist else {
            XCTFail("top-level of plist must be a dictionary")
            return
        }
        XCTAssertFalse(topLevelDict.isEmpty)
        
        // FIXME: We should factor out all of the following using helper assert
        // functions that deal with the enum casing.
        
        // Archive version should be 1.
        guard case let .string(archiveVersionStr) = topLevelDict["archiveVersion"]! else {
            XCTFail("top-level plist dictionary must have an `archiveVersion` string")
            return
        }
        XCTAssertEqual(archiveVersionStr, "1")
        
        // Object version should be 46 (Xcode 8.0).
        guard case let .string(objectVersionStr) = topLevelDict["objectVersion"]! else {
            XCTFail("top-level plist dictionary must have an `objectVersion` string")
            return
        }
        XCTAssertEqual(objectVersionStr, "46")
        
        // There should be a root object.
        guard case let .identifier(rootObjectID) = topLevelDict["rootObject"]! else {
            XCTFail("top-level plist dictionary must have a `rootObject` string")
            return
        }
        XCTAssertFalse(rootObjectID.isEmpty)
        
        // There should be a dictionary mapping identifiers to object dictionaries.
        guard case let .dictionary(objectDict) = topLevelDict["objects"]! else {
            XCTFail("top-level plist dictionary must have a `objects` dictionary")
            return
        }
        XCTAssertFalse(objectDict.isEmpty)
        
        // The root object should reference a PBXProject dictionary.
        guard case let .dictionary(projectDict) = objectDict[rootObjectID]! else {
            XCTFail("object dictionary must have an entry for the project")
            return
        }
        XCTAssertFalse(projectDict.isEmpty)
        
        // Project dictionary's `isa` must be "PBXProject".
        guard case let .string(projectClassName) = projectDict["isa"]! else {
            XCTFail("project object dictionary must have an `isa` string")
            return
        }
        XCTAssertEqual(projectClassName, "PBXProject")
    }
    
    func testBuildSettingsSerialization() {
        
        // Create build settings.
        var buildSettings = Xcode.BuildSettingsTable.BuildSettings()
        
        let productNameValue = "$(TARGET_NAME:c99extidentifier)"
        buildSettings.PRODUCT_NAME = productNameValue
        
        let otherSwiftFlagValues = ["$(inherited)", "-DXcode"]
        buildSettings.OTHER_SWIFT_FLAGS = otherSwiftFlagValues

        let activeCompilationConditionsValues = ["$(inherited)", "DEBUG"]
        buildSettings.SWIFT_ACTIVE_COMPILATION_CONDITIONS = activeCompilationConditionsValues

        // Serialize it to a property list.
        let plist = buildSettings.asPropertyList()
        
        // Assert things about plist
        guard case let .dictionary(buildSettingsDict) = plist else {
            XCTFail("build settings plist must be a dictionary")
            return
        }
        
        guard
            let productNamePlist = buildSettingsDict["PRODUCT_NAME"],
            let otherSwiftFlagsPlist = buildSettingsDict["OTHER_SWIFT_FLAGS"],
            let activeCompilationConditionsPlist = buildSettingsDict["SWIFT_ACTIVE_COMPILATION_CONDITIONS"]
        else {
            XCTFail("build settings plist must contain PRODUCT_NAME and OTHER_SWIFT_FLAGS and SWIFT_ACTIVE_COMPILATION_CONDITIONS")
            return
        }
        
        guard case let .string(productName) = productNamePlist else {
            XCTFail("productName plist must be a string")
            return
        }
        XCTAssertEqual(productName, productNameValue)

        guard case let .array(otherSwiftFlagsPlists) = otherSwiftFlagsPlist else {
            XCTFail("otherSwiftFlags plist must be an array")
            return
        }

        let otherSwiftFlags = otherSwiftFlagsPlists.compactMap { flagPlist -> String? in
            guard case let .string(flag) = flagPlist else {
                XCTFail("otherSwiftFlag plist must be string")
                return nil
            }
            return flag
        }
        XCTAssertEqual(otherSwiftFlags, otherSwiftFlagValues)

        guard case let .array(activeCompilationConditionsPlists) = activeCompilationConditionsPlist else {
            XCTFail("activeCompilationConditionsPlist plist must be an array")
            return
        }

        let activeCompilationConditions = activeCompilationConditionsPlists.compactMap { flagPlist -> String? in
            guard case let .string(flag) = flagPlist else {
                XCTFail("activeCompilationConditions plist must be a string")
                return nil
            }
            return flag
        }
        XCTAssertEqual(activeCompilationConditions, activeCompilationConditionsValues)
    }

    func testSpaceSeparatedBuildSettingsSerialization() {
        var buildSettings = Xcode.BuildSettingsTable.BuildSettings()
        buildSettings.HEADER_SEARCH_PATHS = ["value", "value with spaces", "\"value with spaces\"", #"value\ with\ spaces"#]

        let plist = buildSettings.asPropertyList()

        guard case let .dictionary(buildSettingsDict) = plist else {
            XCTFail("build settings plist must be a dictionary")
            return
        }

        guard case let .array(headerSearchPathsArray) = buildSettingsDict["HEADER_SEARCH_PATHS"] else {
            XCTFail("header search paths plist must be an array")
            return
        }

        let headerSearchPaths = headerSearchPathsArray.compactMap { pathPlist -> String? in
            guard case let .string(path) = pathPlist else {
                XCTFail("headerSearchPaths plist must be a string")
                return nil
            }
            return path
        }

        XCTAssertEqual(headerSearchPaths, ["value", "\"value with spaces\"", "\"value with spaces\"", #"value\ with\ spaces"#])
    }

    func testBuildFileSettingsSerialization() {

        // Create build file settings.
        var buildFileSettings = Xcode.BuildFile.Settings()

        let attributeValues = ["Public"]
        buildFileSettings.ATTRIBUTES = attributeValues

        // Serialize it to a property list.
        let plist = buildFileSettings.asPropertyList()

        // Assert things about plist
        guard case let .dictionary(buildFileSettingsDict) = plist else {
            XCTFail("build file settings plist must be a dictionary")
            return
        }

        guard let attributesPlist = buildFileSettingsDict["ATTRIBUTES"] else {
            XCTFail("build file settings plist must contain ATTRIBUTES")
            return
        }

        guard case let .array(attributePlists) = attributesPlist else {
            XCTFail("attributes plist must be an array")
            return
        }

        let attributes = attributePlists.compactMap { attributePlist -> String? in
            guard case let .string(attribute) = attributePlist else {
                XCTFail("attribute plist must be a string")
                return nil
            }
            return attribute
        }
        XCTAssertEqual(attributes, attributeValues)
    }
}
