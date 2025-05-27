#  ``PackageDescription/Package``

## Topics

### Creating a Package

- ``Package/init(name:defaultLocalization:platforms:pkgConfig:providers:products:dependencies:targets:swiftLanguageModes:cLanguageStandard:cxxLanguageStandard:)``
- ``Package/init(name:defaultLocalization:platforms:pkgConfig:providers:products:traits:dependencies:targets:swiftLanguageModes:cLanguageStandard:cxxLanguageStandard:)``
- ``Package/init(name:defaultLocalization:platforms:pkgConfig:providers:products:dependencies:targets:swiftLanguageVersions:cLanguageStandard:cxxLanguageStandard:)``
- ``Package/init(name:platforms:pkgConfig:providers:products:dependencies:targets:swiftLanguageVersions:cLanguageStandard:cxxLanguageStandard:)``
- ``Package/init(name:pkgConfig:providers:products:dependencies:targets:swiftLanguageVersions:cLanguageStandard:cxxLanguageStandard:)-(_,_,_,_,_,_,[Int]?,_,_)``
- ``Package/init(name:pkgConfig:providers:products:dependencies:targets:swiftLanguageVersions:cLanguageStandard:cxxLanguageStandard:)-(_,_,_,_,_,_,[SwiftVersion]?,_,_)``


### Naming the Package

- ``Package/name``

### Localizing Package Resources

- ``Package/defaultLocalization``
- ``LanguageTag``

### Configuring Products

- ``Package/products``
- ``Product``

### Configuring Targets

- ``Package/targets``
- ``Target``

### Declaring Supported Platforms

- ``Package/platforms``
- ``SupportedPlatform``
- ``Platform``

### Configuring System Packages

- ``SystemPackageProvider``
- ``Package/pkgConfig``
- ``Package/providers``

### Configuring Traits

- ``Package/traits``
- ``Trait``

### Declaring Package Dependencies

- ``Package/dependencies``
- ``Package/Dependency``

### Declaring Supported Languages

- ``SwiftLanguageMode``
- ``CLanguageStandard``
- ``CXXLanguageStandard``
- ``Package/swiftLanguageModes``
- ``Package/cLanguageStandard``
- ``Package/cxxLanguageStandard``
- ``SwiftVersion``
- ``Package/swiftLanguageVersions``
