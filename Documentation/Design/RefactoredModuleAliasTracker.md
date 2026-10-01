# Refactored Module Alias Tracker

## Motivation

The legacy `ModuleAliasTracker` suffered from a lack of proper documentation and data models; several dictionaries representing the relationships between modules and products, as well as aliases and these modules were constantly referenced in nested function calls. This created a tense entrypoint for developers seeking to understand or even begin to debug this area of the code.

The new model seeks to accurately package and represent this relational data in a more human-friendly manner, memoizing computations where necessary to avoid increased runtimes and to section each stage of the alias tracking into concise steps in the initializer for ease of use.

## Data models

The key data models in this new tracker are the following:

* ModuleAlias

This structure aims to represent a single module being aliased; it references its canonical origin (package, module) and tracks any link in the chain of aliasing that is identified. The end result should enforce a singular alias chain comprised of all the `Alias`es that have been added to it, with a single "terminal" alias (i.e. the final name for which the module is being aliased to).

* ProductModules

This structure represents a single unique product from a package, and all of its relationships with other modules and products across the package graph. Namely, it recognizes which modules it vends directly (i.e. the modules it explicitly declares that it exports), the modules it transitively depends on within the same package, cross-package modules that it depends on, cross-package products it depends on, and finally the products across the entire package graph that depend on it. The benefit provided by this model is that we will have quick and immediate access (O(1)) when inquiring about whether a given module/product is at all related in any meaningful way to this product. Additionally, it provides an easy mechanism to identify possible conflicts with module aliasing (e.g. colliding module names).

* ModuleInfo

* ProposedAlias

The purpose of this model is to capture a proxy stage for which the tracker is identifying which modules need to become aware of a particular module alias mapping. There is a set of criteria for a module to add a module alias map to its awareness, as well as other criteria that prohibit the addition of this mapping.
