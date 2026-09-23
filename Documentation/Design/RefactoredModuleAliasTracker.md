# Refactored Module Alias Tracker

## Motivation

The legacy `ModuleAliasTracker` suffered from a lack of proper documentation and data models; several dictionaries representing the relationships between modules and products, as well as aliases and these modules were constantly referenced in nested function calls. This created a tense entrypoint for developers seeking to understand or even begin to debug this area of the code. Additionally, the computed properties used in the Module objects were never memoized, causing the same expensive computations of recursively dependent modules to be done at every iterationl; this was a non-trivial runtime cost to the aliasing algorithm, where the current model ensures that previous computations are memoized for quick and intuitive reference.

The new model seeks to accurately group and represent this relational data in a more human-friendly manner, memoizing computations where necessary to avoid increased runtimes and to section each stage of the alias tracking into concise steps in the initializer for ease of use.

## Data models

The key data models in this new tracker are the following:

### **ModuleAlias**

```swift
public class ModuleAlias: Identifiable { 
    public typealias ID = ModuleAliasID
    var module: Module
    var vendingProducts: Set<String> = []
    let package: PackageIdentity
    var aliases: IdentifiableSet<Alias> = []
    var reverseLookupAliases: [Alias.AliasId: [Alias.AliasId]] = [:]
    public private(set) var terminalAliases: [Alias] = []
}
```

This structure aims to represent a single module being aliased; it references its canonical origin (package, module) and tracks any link in the chain of aliasing that is identified. The end result should enforce a singular alias chain comprised of all the `Alias`es that have been added to it, with a single "terminal" alias (i.e. the final name for which the module is being aliased to).

### **ProductModules**

This structure represents a single unique product from a package, and all of its relationships with other modules and products across the package graph. Namely, it recognizes which modules it vends directly (i.e. the modules it explicitly declares that it exports), the modules it transitively depends on within the same package, cross-package modules that it depends on, cross-package products it depends on, and finally the products across the entire package graph that depend on it. The benefit provided by this model is that we will have quick and immediate access (O(1)) when inquiring about whether a given module/product is at all related in any meaningful way to this product. Additionally, it provides an easy mechanism to identify possible conflicts with module aliasing (e.g. colliding module names).

### **ModuleInfo**



### **ProposedAlias**

The purpose of this model is to capture a proxy stage for which the tracker is identifying which modules need to become aware of a particular module alias mapping. There is a set of criteria for a module to add a module alias map to its awareness, as well as other criteria that prohibit the addition of this mapping.

## Stages

The tracker's initializer runs through the following stages sequentially:

1. **Build the product and package module maps**

For each package, `addProductAndPackageModules` computes a mapping of the available modules in a given package, as well as the modules that a product within that package vends. The `packageModules` map stored in the `ModuleAliasTracker` is keyed by a package's `PackageIdentity`, and returns a set of `ModuleInfo`. Similarly, the tracker stores a `productModules` mapping which is keyed by a product's identity (via `ProductModules.ID`) and returns the `ProductModules` struct representing that product and carries the intra-package module dependencies for it.

2. **Compute full module reachability**

After stage 1, all products for every package will have a `ProductModules` struct representing (at this moment) its intra-package module dependencies. This second stage serves as a mechanism to compute the fuller dependency graph relationships between all modules and products in the graph. For every product, `computeAllReachableModules` will compute all intra- and cross-package module dependencies, storing the distance of that module dependency relative to the level of the product's package node in the dependency graph.

Afterwards, the `ProductModules` `crossPackageReachableModules` will be populated and keyed by `PackageIdentity`, for which it will return a set of modules that are reachable by that product via other packages. In parallel, `reachableModulesByName` is constructed with the intent to be keyed by a module name, for which a set of `ReachableModule`s are returned that have that same name.

3. **Compute reverse dependent products**

This next stage establishes a reverse relationship between all the products in the dependency graph. `computeAllDependentProducts` will mirror the previous stage but in reverse, where for every product it will compute every other product that depends on it.

4. **Register declared aliases**

Once the full graph's products and modules relationships have been established, the tracker moves on to record all the module aliases that it finds (`addAliases`). To do so, it iterates over every module's dependencies to detect product dependencies (`.product(..., moduleAliases: [...])`) that declare a module alias. Afterwards, it will resolve which canonical module object the alias refers to (`resolveModule`), and it will record every intermediary module alias (if applicable) in a `ModuleAlias` model.

Module aliases cannot yet be disambiguated at this stage, therefore the `ModuleAlias` will store every link in each detected module alias chain to later be resolved.

5. **Propose aliases**

For every registered `ModuleAlias` stored in the tracker, resolve each of its module alias chains and broadcast a proposal to every module that might plausibly need to know about it (`proposeAliases`). Here, there is a set of criteria applicable to each module for which the tracker will apply the proposed alias.

6. **Disambiguate and apply aliases** 

For every module with one or more proposed aliases, resolve each proposal to a single winning name (if applicable) and add the alias mapping to that module (via `addModuleAlias`). Afterwards, iterate through each module and apply the alias (`applyAlias`).

If there are remaining aliases that were never assigned, diagnostics will be emitted indicating such.

## **Proposed alias criteria**
A module can receive a proposal for an alias (possibly for itself, or for some other module) through any combination of these:

1. **Self-rename**: The module in question **is** the canonical module being aliased. It will always record `[canonicalModuleName: terminalAliasedName]` on itself, where the `terminalAliasedName` represents the final resolved module alias computed via the existing intermediary alias links (if applicable).

   ```text
   +----------+           +-----------+
   |  ZooPkg  |           |  FarmPkg  |
   |----------|           |-----------|
   |  Animal  |---------->|   Barn    |
   | (aliased)|           +-----------+
   +----------+           Barn: Animal->Cow

   => Animal.addModuleAlias(Animal->Cow)
   ```

2. **Same-package propagation**: The module exists in the **same package** as the canonical module being aliased and depends on it -- directly or transitively -- through an intra-package `.module(...)` type dependency.

   ```text
   +------------------------+           +-----------+
   |         ZooPkg         |           |  FarmPkg  |
   |------------------------|           |-----------|
   |   Animal --> Helper    |---------->|   Barn    |
   |  (aliased)             |           +-----------+
   +------------------------+             Barn: Animal->Cow

   => Helper.addModuleAlias(Animal->Cow)
   ```

3. **Cross-package broadcast**: The module is in a *different* package, and it is *directly vended* (i.e. the product's own explicitly declared modules) by a product that is itself a transitive downstream consumer of some product that vends the canonical module being aliased.

   ```text
   +-----------+     +-----------+            +-----------+
   |  gamePkg  |     |  libPkg   |            |  appPkg   |
   |-----------|     |-----------|            |-----------|
   |   Utils   |---->|    Lib    |----------->|    App    |
   | (aliased) |     +-----------+            +-----------+
   +-----------+   Lib: Utils->GameUtils     App: GameUtils->LibUtils

   => Lib.addModuleAlias(Utils->LibUtils)
   ```

4. **Intermediary alias**: The module is a **non-terminal** **link** in the module alias chain (as in, this module declared an alias on a module, and some *other* module further downstream has overridden that alias again), *and* it cannot safely rely on the canonical module name resolving unambiguously in its own source. This could be true when either: this module's own name is literally identical to the name of some other module that it's overriding (it cannot import a dependency that shares its own name), or some other, differently-packaged module is also reachable by it and still answers to that literal name, at a distance equal to or closer than the module it's actually aliasing.

   ```text
   +----------+     +-------------+
   |  ZooPkg  |     |  JunglePkg  |
   |----------|     |-------------|
   |  Animal  |     |   Animal    |
   | (aliased)|     |   (rival)   |
   +----------+     +-------------+
         \                 /
          v               v
            +-----------+
            |  FarmPkg  |
            |-----------|
            |   Barn    |
            +-----------+
             Barn: Animal->Cow   (first link in chain -- not the terminal alias)
                 |
                 v
            +-----------+
            | RanchPkg  |
            |-----------|
            |   Coop    |
            +-----------+
             Coop: Cow->Cattle   (terminal alias)

   => Barn.addModuleAlias(Cow->Cattle)
      (Barn's own source imports "Cow" so it needs to know that name is
       now physically compiled as "Cattle", due to Coop's alias override)
   ```

## **Alias resolution criteria**
Since a module could receive multiple alias proposals for a single module, this resolution criteria serves to disambiguate and finalize what mappings will be recorded.

1. Alias candidates that trace back to the same canonical module, but represent diverging and independent chained alias paths are collapsed first; the alias chain for which its terminal alias declaration is closer to the module will win.

   ```text
           +----------+
           |   dPkg   |
           |----------|
           |  Utils   |
           | (aliased)|
           +----------+
             /       \
            v         v
       +--------+     +--------+
       |  hPkg  |     |  cPkg  |
       |--------|     |--------|
       |   H    |     |   C    |
       +--------+     +--------+
          |                 |
          v                 v
       +--------+        +--------+
       |  gPkg  |        |  bPkg  |
       |--------|        |--------|
       |   G    |        |   B    |
       +--------+        +--------+
    G: Utils->GUtils     B: Utils->YUtils
        (dead end)              |
                                v
                            +--------+
                            |  aPkg  |
                            |--------|
                            |   A    |
                            +--------+
                             A: YUtils->XUtils

   => Utils.addModuleAlias(Utils->XUtils)
   ```

2. A self-rename candidate wins outright, regardless of other possibly proposed aliases.

   ```text
   +----------+
   |  ZooPkg  |
   |----------|
   |  Animal  |
   +----------+
    Animal: Animal->Cattle

   => Animal.addModuleAlias(Animal->Cattle)  (wins outright)
   ```

3. If some other, non-aliased module is reachable and still answers to the same literal name as the module being aliased (as in, this dependency is reachable through the module's own vending products), no alias mapping will be applied at all; the plain name may still validly refer to this other unrelated module dependency of the same name.

   ```text
   +----------+     +-------------------+
   |  ZooPkg  |     |      WildPkg      |
   |----------|     |-------------------|
   |  Animal  |     |       Animal      |
   | (aliased)|     | (survivor, plain) |
   +----------+     +-------------------+
         \                     /
          v                   v
          +------------------+
          |   HomesteadPkg   |
          |------------------|
          |       Ranch      |
          +------------------+

   => nothing applied
   ```

4. If the module itself declared more than one of the remaining candidates, this is a conflict and no alias mapping will be applied. If it declared exactly one of the candidates, and this candidate is an override of another alias, it's trusted directly (will be logged as `.`). If the alias declaration is the first module alias declaration (i.e. the start of the module alias chain), an additional check still needs to be made before resolving.

   ```text
   +----------+     +-------------+
   |  ZooPkg  |     |  JunglePkg  |
   |----------|     |-------------|
   |  Animal  |     |   Animal    |
   +----------+     +-------------+
         \                 /
          v               v
          +--------------+
          | ConsumerPkg  |
          |--------------|
          |      M       |
          +--------------+
           M: Animal->Alpha, Animal->Beta  (contradiction)

   => nothing applied
   ```

   ```text
   +-----------+     +--------------+
   |  FarmPkg  |     | ConsumerPkg  |
   |-----------|     |--------------|
   |   Barn    |---->|      M       |
   +-----------+     +--------------+
    Barn: Animal->Cow    M: Cow->Cattle
          (first link)      (continuation)

   => M.addModuleAlias(Cow->Cattle)
   ```

   ```text
   +--------------+
   | ConsumerPkg  |
   |--------------|
   |      M       |
   +--------------+
    M: Animal->Epsilon (first link)

   => falls through to criterion 5
   ```

5. Lastly, the candidate that is reachable with the closest distance from the module's own vending products wins; if there is a tie here, nothing is applied.

   ```text
   +----------+     +----------+
   |   cPkg   |     |   dPkg   |
   |----------|     |----------|
   |   Log    |     |   Log    |
   +----------+     +----------+
    Log: Log->CLog    Log: Log->DLog
         \                 /
          v               v
          +--------------+
          | ConsumerPkg  |
          |--------------|
          |      B       |
          +--------------+
           (equidistant)

   => nothing applied (tie)
   ```



