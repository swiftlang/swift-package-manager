# Test Case Refactoring: Unified Graph and Expectations

## Overview

This refactoring addresses the suggestion to tie together the `ModulesGraph`, `ResolvedPackagesStore`, and `TestExpectations` in a single data structure, making tests more maintainable and reducing the risk of mismatched test data.

## Changes Made

### 1. New `SBOMTestCase` Structure

Created a unified test case structure in [`SBOMTestModulesGraphHelpers.swift`](Tests/SBOMModelTests/SBOMTestModulesGraphHelpers.swift:20-130):

```swift
struct SBOMTestCase {
    let name: String
    let graph: ModulesGraph
    let store: ResolvedPackagesStore
    let expectations: TestExpectations
    
    struct TestExpectations {
        let totalComponentCount: Int
        let expectedPackageIds: Set<String>
        let rootPackage: String
        let rootPackagePrefix: String
        let expectedRootProductCount: Int
        let expectedRootProductNames: Set<String>
    }
}
```

### 2. Factory Methods

Added three factory methods that create complete test cases with graph, store, and expectations bundled together:

- [`SBOMTestCase.createSimpleTestCase()`](Tests/SBOMModelTests/SBOMTestModulesGraphHelpers.swift:38-52) - Simple test graph with MyApp and Utils
- [`SBOMTestCase.createSPMTestCase(rootPath:)`](Tests/SBOMModelTests/SBOMTestModulesGraphHelpers.swift:54-88) - Swift Package Manager test graph
- [`SBOMTestCase.createSwiftlyTestCase(rootPath:)`](Tests/SBOMModelTests/SBOMTestModulesGraphHelpers.swift:90-124) - Swiftly project test graph

### 3. Updated Test Methods

Refactored all test methods in [`SBOMExtractComponentsTests.swift`](Tests/SBOMModelTests/SBOMExtractComponentsTests.swift) to use the unified test case structure.

**Before:**
```swift
@Test("extractComponents with sample SPM ModulesGraph")
func extractComponentsFromSPMModulesGraph() async throws {
    let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
    let store = try SBOMTestStore.createSPMResolvedPackagesStore()
    let extractor = SBOMExtractor(modulesGraph: graph, dependencyGraph: nil, store: store)
    let components = try await extractor.extractDependencies().components
    self.verifyComponents(components: components, graph: graph, expectations: Self.spmExpectations)
}
```

**After:**
```swift
@Test("extractComponents with sample SPM ModulesGraph")
func extractComponentsFromSPMModulesGraph() async throws {
    let testCase = try SBOMTestCase.createSPMTestCase()
    let extractor = SBOMExtractor(modulesGraph: testCase.graph, dependencyGraph: nil, store: testCase.store)
    let components = try await extractor.extractDependencies().components
    self.verifyComponents(components: components, graph: testCase.graph, expectations: testCase.expectations)
}
```

## Benefits

1. **Cohesion**: Graph, store, and expectations are now tied together, preventing mismatches
2. **Maintainability**: When updating test data, all related components are in one place
3. **Readability**: Test intent is clearer with named test cases
4. **Reusability**: Test cases can be easily shared across different test methods
5. **Type Safety**: The structure enforces that expectations match the graph being tested

## Migration Guide

To use the new test case structure:

1. Replace separate graph and store creation:
   ```swift
   let graph = try SBOMTestModulesGraph.createSPMModulesGraph()
   let store = try SBOMTestStore.createSPMResolvedPackagesStore()
   ```
   
   With unified test case creation:
   ```swift
   let testCase = try SBOMTestCase.createSPMTestCase()
   ```

2. Access components via the test case:
   ```swift
   testCase.graph
   testCase.store
   testCase.expectations
   ```

3. Update method signatures to use `SBOMTestCase.TestExpectations` instead of the old `TestExpectations` type.

## Future Enhancements

- Add more test case factory methods for additional scenarios
- Consider adding test case builders for custom configurations
- Extend to dependency graph tests in [`SBOMExtractDependenciesTests.swift`](Tests/SBOMModelTests/SBOMExtractDependenciesTests.swift)