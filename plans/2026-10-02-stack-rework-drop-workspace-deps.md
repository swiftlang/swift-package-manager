# gh-Stack Rework — Drop Workspace Dependencies / `.workspaceInherited`

**Date:** 2026-10-02
**Driver:** Design redesign dropping `Workspace.dependencies:` + `.package(workspaceInherited:)`. The multi-root resolver already unifies external deps across all member roots; Phase 8D's member-level overrides handle local redirection; a `swift workspace update-dependencies` command (Phase 18) covers bulk version bumps.

**Approach:** B — surgical rebase mid-stack via `gh stack` tooling. Each phase remains self-consistent after rework.

**Backups:** 35 branches backed up to `backup/2026-10-02/<original-name>` on 2026-10-02. Stack metadata JSON at `.stack-backup-2026-10-02/stack-view.json`.

---

## Prework

- [x] **A1 — Resolve 3 AUDIT_NEEDED branches** (audit results 2026-10-02):
  - [x] `poc_workspaces_phase1` → **EDIT_IN_PLACE**. Ships `Workspace.dependencies:` DSL field + `WorkspaceManifest.dependencies` model field + `WorkspaceManifestJSONParser.swift` serialization + related plumbing. Needs removal of all four.
  - [x] `poc_workspaces_phase4` → **EDIT_IN_PLACE**. `Fixtures/Workspaces/S04_CwdInsideMember/packages/app/Package.swift` uses `.package(workspaceInherited: "some-lib")`. Rewrite the fixture to declare `some-lib` directly (e.g. `.package(path: "../../external/some-lib")`).
  - [x] `poc_workspaces_phase9` → **EDIT_IN_PLACE**. `Sources/Workspace/InitWorkspace.swift` emits an empty `dependencies:` block in the scaffolded `Workspace.swift`. Remove the emission (and any `--dependencies` CLI option if present).
  - [x] `poc_workspaces_phase13-make-package-describe-workspace-aware` → **KEEP_AS_IS for inherited**. The `.workspaceInherited` case in `DescribedPackageDependency` was added in `phase15-error-handling-workspace-and-traits-validation` (already DELETE_ENTIRELY), not here.

## Deletion pass (3 branches to drop entirely)

Execute via `gh stack unstack <stack-number>` or `git branch -D` + stack rewiring. Each deletion requires rebasing the next downstream branch onto the previous one.

- [ ] **D1 — Drop `poc_workspaces_phase3`** (introduces `.workspaceInherited` DSL + 937-line WorkspaceResolveTests + Kind case + factory). Rebase `poc_workspaces_phase4` onto `poc_workspaces_phase2`.
- [ ] **D2 — Drop `poc_workspaces_phase15-error-handling-workspace-and-traits-validation`** (single commit: workspace-inherited traits per-member + `S15_InheritedTraits` fixture + describe's inherited case). Rebase next-downstream onto previous.
- [ ] **D3 — Drop `poc_workspaces_phase8_diverge-workspace_add-dependency-subcommand`** (365-line AddDependencyCommand.swift + 202-line WorkspaceManifestSyntax additions dedicated to `swift workspace add-dependency`). Rebase next-downstream onto previous.

## Edit-in-place pass (~13 branches)

Each edit removes workspace-inherited / workspace-level-dep code while preserving the rest of the branch's intent.

### Phase 8 — `swift package resolve` + trailing warnings

- [ ] **E8.1** — Change `WorkspaceOriginHashTests` + corresponding production code to compute originHash over member manifests only (drop workspace-level `dependencies:` from the hash input).

### Phase 8-override family (3 branches)

- [ ] **E8B.1** — `poc_workspaces_phase8_diverge-workspace_deps_override`: remove the `apply(_:to workspaceManifest:)` surface from `WorkspaceOverridesJSONParser`; keep base override subcommand infra.
- [ ] **E8C.1** — `poc_workspaces_phase8_diverge-workspace_deps_override_add_subcommand`: strip "workspace-level" from help text / abstract strings; `override add <identity>` targets member-declared identities only.
- [ ] **E8D.1** — `poc_workspaces_phase8_diverge-workspace_deps_override_add_subcommand_support-overridi`: drop the `.workspaceInherited` skip-line in `apply(_:to memberManifest:)` (no inherited to skip); drop the workspace-level apply arm; strip inherited references from TDD cycle logs (optional — see note on historical records at bottom).

### Phase 8-mirrors

- [ ] **EM.1** — `poc_workspaces_phase_unknown_Workspace-with-mirror`: edit mirror-substitution code so it applies to member-declared external deps (not `.workspaceInherited` deps). Update tests accordingly.

### Phase 9

- [ ] **E9.1** — If AUDIT finds `--dependencies` option in `swift workspace init`, remove the option + its scaffolding of `dependencies:` block in generated `Workspace.swift`.

### Phase 10

- [ ] **E10.1** — If `[workspace inherited]` tag exists in `DependenciesSerializer.swift`, remove it. Keep `[workspace member]` tag.

### Phase 11 / 12

- [ ] **E11.1** — Audit `S11_Update/external/{some,other}-lib` fixtures; replace `.workspaceInherited` usage with direct member declarations.

### Phase 14 — `WorkspaceManifest: Encodable`

- [ ] **E14.1** — `poc_workspaces_phase14-make-package-dump-package-workspace-aware`: remove the `dependencies` field from `WorkspaceManifest: Encodable` output (field no longer exists on the type).

### Phase 15 family (4 branches)

- [ ] **E15.1** — `poc_workspaces_phase15-improve-error-with-invalid-workspace-member-or-inherited`: drop the inherited validation arm; retain the member validation arm.
- [ ] **E15.2** — `poc_workspaces_phase15-error-handling-swift-package-edit-errors-with-workspace`: drop the `.workspaceInherited` arm from "workspace-only DSL used outside a workspace" coverage; retain `.workspaceMember` arm.
- [ ] **E15.3** — `poc_workspaces_phase15-error-handling-workspace-cyclical-dependency`: drop `S15_WorkspaceInheritedCycle/` fixture + `s15_workspaceInheritedCycle_hardErrors` test; keep the `S15_WorkspaceMemberCycle/` fixture + test.

### Phase rename branch

- [ ] **ER.1** — `poc_workspaces_update-swift-package-workspace-to-swift-workspace`: strip `swift workspace add-dependency` and inherited-related diagnostics from the rename edits.

### Phase 17 — publish workspace-aware (branch exists, implementation not yet started)

- [ ] **E17.1** — `poc_workspaces_phase17_make-swift-package-registry-publish-worspace-aware`: no code yet, but the plan doc Phase 17 section was already updated to drop inherited rewrite rules (completed 2026-10-02 as part of the redesign).

## Rebase cascade

- [ ] **R1** — After every DELETE and EDIT, run `gh stack rebase` to cascade rebases downstream. Expect conflicts at:
  - 8-override apply path (loss of workspace-level arm)
  - Phase 14 `WorkspaceManifest: Encodable` field removal
  - Phase 15 cyclical fixture removal
  - Phase 10 serializer `[workspace inherited]` tag removal

- [ ] **R2** — After the full cascade, run `gh stack push --force-with-lease` to update remote branches (only after local stack is green).

## Verification

- [ ] **V1** — `swift build --disable-sandbox` at the top of the stack (Phase 17 branch); must build without error.
- [ ] **V2** — `swift test --disable-sandbox --filter WorkspaceTests --xunit-output xunit.xml --experimental-xunit-message-failure` must pass at the top of the stack.
- [ ] **V3** — `grep -rE 'workspaceInherited|WorkspaceInherited|workspace-level dep' Sources/ Tests/` returns zero hits (allow references in `plans/` doc for historical traceability).
- [ ] **V4** — `gh stack view --json | jq '.branches | map(.needsRebase) | all(. == false)'` returns `false` (i.e. no branch needs further rebase).

## Note on historical TDD cycle records

The 8B/8C/8D sub-slice cycle logs in the plan doc (`plans/2026-08-24-swiftpm-workspaces-implementation.md`) reference workspace-level override apply and `.workspaceInherited` skip-line cycles. Per the redesign note at the top of the plan doc, these records are retained for traceability even though the underlying code paths are being removed from the stack. The cycle-log edits in E8B.1 / E8C.1 / E8D.1 are code-only; the plan doc's historical cycle entries stay as-is.

## Rollback

If anything goes irrecoverably wrong:

```bash
# Full stack restore from backups:
gh stack unstack --local
for b in $(git branch --list "backup/2026-10-02/*" | sed 's|^..backup/2026-10-02/||'); do
  git branch -f "$b" "backup/2026-10-02/$b"
done
# Then re-init the stack from backup branches in original order (see stack-view.json)
```
