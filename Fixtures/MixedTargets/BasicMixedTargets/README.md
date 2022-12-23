# BasicMixedTargets

A collection of targets to test SPM's support of mixed language targets. 

## BasicMixedTarget
Represents a simple mixed package where:
- Swift part of the target used types from the Objective-C part of the module
- Objective-C p of the target used types from the Swift part of the module

## MixedTargetWithResources
Represents a simple mixed package with a bundled resource where:
- resource can be accessed from an Swift context using `Bundle.module`
- resource can be accessed from an Objective-C context using 
  `SWIFTPM_MODULE_BUNDLE` macro
  
## MixedTargetWithCustomModuleMap
- Represents a simple mixed package that contains a custom module map.

## MixedTargetWithCustomModuleMapAndResources
- Represents a simple mixed package that contains a custom module map and 
  a bundled resource. 
  
TODO(ncooke3): Fill the rest of this out.
