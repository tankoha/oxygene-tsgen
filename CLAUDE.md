# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Rules

- This project uses RemObjects Oxygene (Object Pascal for .NET).
- Never write C# code. Always output valid Oxygene syntax.

## Project Status

Phase 1 (design) is complete. Phase 2 (implementation) has a working MVP,
hardened well past the original bullet list: `src/Tsgen` is a CLI (`tsgen
generate --assembly <dll> --source <dir> --out <dir> [--mode
assembly|inertia]`) covering Stage 1 (Loader, via `MetadataLoadContext`),
a Tokenizer-based NRT source scanner feeding an `INullabilityProvider`
chain, a lightweight Stage 2 IR with generics support (`List<T>`/
`Dictionary<K,V>`/`Nullable<T>`/arrays/user-defined-type references), a
single-file Stage 4 `DtsEmitter`, and now (`--mode inertia`) the
Inertia.js entry-point-driven mode itself, including all three of
`docs/DESIGN.md` §2.6's Inertia-specific targets: Page Props, Form/
`useForm()` error types, and Shared Data types — see `HANDOFF.md`
§12/§22/§23/§24/§26/§27 for what was built, how, and its known
limitations. Member/property names go through a `--naming-policy
camelCase|as-written` conversion (default `camelCase`, matching
`System.Text.Json`'s own default) applied uniformly regardless of
`--mode` — see `HANDOFF.md` §28. Still missing: cycle detection
(deliberately deferred, see below), the `[JsonPropertyName]` attribute
override (§5.1's naming-conversion story is only half-done), and the
pluggable type-mapping/plugin chain/split-file output. `docs/DESIGN.md`
§10.2 has the post-MVP order.

**Automated snapshot tests exist now:** run `tools/run-tests.ps1` (builds
the CLI + every fixture under `tests/fixtures/`, then diffs `tsgen`
output against committed `expected/*.d.ts` snapshots per fixture's
`cases.json`). Pass `-UpdateSnapshots` to regenerate expectations after
an intentional output change. See `HANDOFF.md` §15. **The comparison is
case-sensitive on purpose (`-ceq`, not PowerShell's default `-eq`) —
PowerShell's `-eq` is case-insensitive for strings, which silently made
the whole suite blind to case-only regressions until this was found and
fixed alongside the `--naming-policy` bug, `HANDOFF.md` §28. Don't
"simplify" it back to `-eq`.** Seven fixtures exist, 17 cases total:
`SampleModel` (enums, explicit NRT, all three `--nrt-unknown-policy`
values via its deliberately-still-`Unknown` `Notes` field — see
`HANDOFF.md` §21.3 for why that field exists — plus `as-written` for
`--naming-policy`, `HANDOFF.md` §28; also a `Status`-typed unannotated
enum property, a `DateOnly`-typed unannotated property, and a `Rating`
`record`/struct type referenced by an unannotated property, covering
`HANDOFF.md` §§33-35 respectively),
`ExternalDependency` (a same-folder sibling dependency DLL a target
assembly's own type inherits from — regression coverage for
`AssemblyLoader.Load`'s dependency-resolution fix, `HANDOFF.md` §31;
its own `Vendor/*.elements` subproject is built by `tools/run-tests.ps1`
before the fixture's top-level project, see the script for why),
`TokenizerEdgeCases` (NRT keywords inside comments/string literals, no
trailing newline, also covers `mark-unknown`), `MultiTypeAndIndexer`
(multiple types sharing one `type` section, indexer-style properties —
see `HANDOFF.md` §18), `NestedTypeCollision` (a nested type's
annotated property must not overwrite an outer, same-named member's
nullability — see `HANDOFF.md` §20), `Generics` (`List<T>`/
`Dictionary<K,V>`/`Nullable<T>`/arrays/self-referential named-type
references — see `HANDOFF.md` §23.4), and `InertiaMode` (`--mode
inertia`: call-site detection, reachability BFS, an unresolvable prop
value falling back to `unknown` + diagnostic, the paired
`XxxFormErrors` type per page, a props-less page exercising its
`Partial<Record<never, string>>` fallback, an `AddInertiaSharedData(...)`
registration proving Shared Data detection + its own reachability
seeding, a bare `Inertia.Share(...)` call proving the
detected-but-excluded diagnostic path, a shared field name that collides
with a `SharedData` floor key after the naming-policy transform proving
the duplicate-member skip-and-warn path, and its own `as-written` case
proving `ClassLike`/`FormErrorsLike` casing stay consistent with each
other under either naming policy — see `HANDOFF.md`
§24.5/§26/§27/§29/§30). Also: enum-valued flags (`--mode`,
`--enum-style`, `--nrt-unknown-policy`, `--naming-policy`) reject an
unrecognized value with a clean error instead of silently defaulting
(`HANDOFF.md` §30) — don't reintroduce a silent-fallback `else` branch
for one of these without a matching rejection case.
Nested types themselves remain uncovered and out of scope for real
support: `AssemblyLoader` filters out every `t.IsNested` type before it
reaches the IR, and `DtsEmitter` has no nested-`interface` output path
either, so giving a nested type's own members their own output would need
coordinated Loader + IR + Emitter changes, not a scanner fix. That's
distinct from `NullabilityScanner` correctly *ignoring* nested-type
members without corrupting an outer member's data, which the scanner
alone is responsible for and now does (`HANDOFF.md` §20 — a `(depth =
typeDepth)` guard was missing on the property-scanning branch). See
`HANDOFF.md` §18.1/§20 for the full explanation.

**structs (Oxygene `record`) ARE supported, unlike nested types** —
don't conflate the two scope decisions above. `AssemblyLoader.Load`
admits a public, non-nested, non-generic, non-enum, non-primitive
`t.IsValueType` type the same way it admits a class (`RawTypeKind
.ClassLike`, same property/field reflection); no Loader+IR+Emitter
compound change was actually needed here, unlike the nested-type case
this might otherwise look similar to (`HANDOFF.md` §35). One real gap
remains, deliberately unfixed: an unannotated member whose type is one
of the target assembly's own structs still renders `| null` — only
enum-typed members get the "assembly-defined value type defaults to
non-null" treatment so far (`RawTypeRef.IsEnum`, `HANDOFF.md` §33); see
§35's own "follow-up finding" for the small, contained change this would
need if it's ever prioritized.

**Nullability is resolved through the `INullabilityProvider` chain**
(`src/Tsgen/Nrt/NullabilityProviders.pas`, `HANDOFF.md` §21), not a
direct dictionary lookup: `IrBuilder.Build` tries
`OxygeneSourceScanProvider` (the source scan's explicit annotations)
first, then `ValueTypeDefaultProvider` (known CLR value types are
non-nullable unless explicitly annotated otherwise) — first non-`Unknown`
answer wins. Consequence worth remembering: an unannotated *value-typed*
member (`Int32`, `Boolean`, `DateOnly`/`TimeOnly`, etc.) is no longer
`Unknown` at all, so `--nrt-unknown-policy` has nothing to act on for
it — only unannotated *reference-typed* members (and, still, unannotated
*struct-typed* members — see the "structs ARE supported" note above,
`HANDOFF.md` §35) stay genuinely `Unknown`. Since `HANDOFF.md` §33,
`ValueTypeDefaultProvider` also recognizes an unannotated member typed
as one of the TARGET ASSEMBLY'S OWN enums as non-nullable, via
`RawTypeRef.IsEnum` (propagated from `RawType.Kind = Enum` at both
`RawTypeRef`-building call sites — `AssemblyLoader.BuildTypeRef`
*and* `InertiaScanner.Scan`'s `aKnownTypes` construction, since an
Inertia props/shared-data field's type is resolved by written name from
source, not reflection; both needed the fix, see §33) — not by adding
every possible enum name to `IsKnownValueType`'s hardcoded list, which
could never enumerate a target assembly's own type names up front the
way it can the fixed BCL primitive set. `--nrt-unknown-policy` has three
values: `nullable` | `non-null` | `mark-unknown` (the last renders the
same bare type as `non-null` plus a trailing `// nrt: unknown` comment,
since TypeScript can't express "undetermined" as a distinct type).
Provider 2 (reflection-attribute-based, for C#/VB dependency assemblies)
remains genuinely unimplemented — don't add a stub for it without a real
need.

**`InertiaScanner.ResolveTypeName` also recognizes Oxygene's own
"more Pascal-ish" standard-library aliases** (`Integer`→`Int32`,
`SmallInt`→`Int16`, `ShortInt`→`SByte`, `Word`→`UInt16`,
`Cardinal`/`LongWord`→`UInt32`, `IntMax`/`UIntMax`→`Int64`/`UInt64`),
confirmed against https://docs.elementscompiler.com/API/StandardTypes/Integers/
— not `Real` for `Double`, despite that being a common historical
Pascal/Delphi name: the current Elements Floats standard-types page does
not document it as a recognized alias, so it was deliberately left out
rather than guessed (`HANDOFF.md` §32). `Integer` specifically matters
because real Oxygene code overwrites `Int32` with it almost universally
— a target app's props-value locals spelled `var count: Integer := ...;`
silently failed to resolve before this fix.

**Generics resolve through `RawTypeRef` (`src/Tsgen/Loading/RawModel.pas`)
+ recursive `TypeMapper.MapTypeRef`** (`HANDOFF.md` §23), not a flat
`ClrTypeName` string — built from `System.Type` via
`AssemblyLoader.BuildTypeRef` using `GetElementType()`/
`GetGenericArguments()` directly, never `Type.FullName`'s mangled
assembly-qualified generic syntax. Covers arrays, `List<T>`-family →
`T[]`, `Dictionary<K,V>`-family → `Record<K,V>` (string/number keys
only), and `Nullable<T>`/`Task<T>`/`ValueTask<T>` unwrapping. A leaf type
that isn't a known BCL primitive but matches one of the assembly's own
emitted types (tracked as `DtsEmitter.Emit`'s `aKnownTypes` set) resolves
to a fully-qualified `Namespace.Name` reference instead of falling to
`unknown` — always fully qualified (never the bare short name), since
TS's `declare namespace A.B` blocks accept dotted references regardless
of which namespace block the reference site is in. Named-type references
are never structurally expanded, so self-/mutually-referential types
already work without cycle detection (deliberately deferred, see below).
**Gotcha**: Oxygene's `{ }` block comments don't nest — never put a
brace-containing code sample inside one. Hit this twice in one session
(`HANDOFF.md` §23.6, §24.3) before it stuck; write comments with plain
prose or quoted phrases instead of literal TS/braces syntax.

**Cycle detection (Tarjan SCC, `docs/DESIGN.md` §3) is deliberately not
implemented.** §3.3 already states cycles can generally be ignored for
`DtsEmitter` specifically (TS `interface`/`type` tolerates circular
references natively) — its real value is the zod `SchemaEmitter` (not
built) and single-file output ordering (cosmetic). Don't add it
speculatively; revisit once the zod emitter actually needs `lazy()`
wrapping.

**`--mode inertia` implements entry-point-driven discovery**
(`src/Tsgen/Inertia/`, `docs/DESIGN.md` §3.5, `HANDOFF.md` §22 spike →
§24 implementation): `InertiaScanner` finds `Inertia.Render(component,
propsVar)` call sites and the `propsVar['key'] := value;` assignments
that built `propsVar` in the same method (the *only* pattern real
Oxygene code can produce — Oxygene has no working object/collection-
initializer syntax, `HANDOFF.md` §22.3); `InertiaIrBuilder` then does a
reachability BFS from each resolved field's type (reusing
`IrBuilder.BuildType`, refactored out of `IrBuilder.Build` for exactly
this reuse) so only types actually referenced from Page Props — not the
whole assembly — get emitted, plus one synthesized interface per page
(always namespace-wrapped under a shared `'Props'` namespace, never left
bare at top level, since a bare top-level `export` silently turns the
whole `.d.ts` into an ES module). v1 resolves literal/identifier/
non-generic `new NamedType(...)` prop values only; anything else
(anonymous `new class(...)` literals, cross-method props construction,
conditional key-setting, `Inertia.Defer`/`Inertia.Merge`) falls back to
`unknown` + a diagnostic rather than guessing — see `HANDOFF.md` §24.6
for the full, deliberate limitations list before extending this.
`InertiaIrBuilder.Build` also emits a paired `IrTypeKindLite.FormErrorsLike`
type per page (`docs/DESIGN.md` §2.6 item 3/§5.4, `HANDOFF.md` §26) —
`Partial<Record<'field1' | 'field2' | ..., string>>` reusing the *same*
field-name list as the page's Props type, not a separate DataAnnotations
scan of some request DTO (a deliberate, smaller-scope v1 choice, not what
§5.4 originally proposed). `DtsEmitter.EmitType` renders this as a type
alias, not an `interface`; an empty field list (a legitimate props-less
page) falls back to `Partial<Record<never, string>>` since a union of
zero string literals isn't valid TS.

**Shared Data (`docs/DESIGN.md` §2.6 item 2/§7.1/§8.2, `HANDOFF.md`
§27, spiked by a background Opus 5 agent before implementation)**:
`InertiaIrBuilder.Build` also emits one `SharedData` interface in the
`'Props'` namespace, and every page's Props interface `extends
Props.SharedData` (`IrTypeLite` gained `BaseTypeNames: List<String>` for
this — `DtsEmitter.EmitType` appends `' extends ' + ...` to the
interface header when non-empty). `SharedData` always includes three
keys InertiaNetCore injects into every page's payload unconditionally
(`flash`, `timestamp`, `errors` — confirmed against InertiaNetCore's own
source, not assumed), plus whatever fields `InertiaScanner` finds via
`AddInertiaSharedData(Func<HttpContext, InertiaProps>)` middleware-
registration call sites (detected by tracking a props var *newly
declared inside* the call's argument span — same
`propsFields`/`ParseVarDecl`/`ParsePropsAssignment` machinery as Page
Props, zero new token IDs needed). A bare `Inertia.Share(key, value)`
call is deliberately NOT treated as shared data in v1 — InertiaNetCore
uses that same call for both app-global data and a single page's own
extra prop, so the call shape alone can't classify it; it's detected and
reported via diagnostic (`ParseShareCallExcluded`) but excluded, a
scope decision the user can revisit later behind a CLI flag (not built
yet). The reachability BFS is seeded from shared fields' types too, not
just each page's own fields, so e.g. a shared `Auth: AuthUserDto` field
gets `AuthUserDto` emitted and referenced instead of falling to
`unknown`.

When adding an NRT fixture, include both a `--nrt-unknown-policy
non-null` case and at least one deliberately-unannotated *reference-type*
member: under the default policy an `Unknown` member and one that wrongly
picked up a leaked annotation both render `| null`, so a default-only
snapshot hides exactly the bug class the fixture exists to catch
(`HANDOFF.md` §16.3) — and since `ValueTypeDefaultProvider`, an
unannotated value-typed member won't stay `Unknown` long enough to
demonstrate the policy at all (`HANDOFF.md` §21.3).

**`metadata.fx` does not carry NRT info** — confirmed hands-on
(`HANDOFF.md` §14), closing the lead from §9.4. The Tokenizer-based
source scan (`src/Tsgen/Nrt/NullabilityScanner.pas`) remains the only
viable path to nullable/not-nullable info for Oxygene-authored code; no
design change resulted from this check.

**Building requires a workaround, not just `EBuild.exe`:** run
`tools/dev-build.ps1` (not `EBuild.exe` directly) — EBuild has a known gap
where it doesn't fully register non-framework references (NuGet or local)
in the generated `deps.json` for `Mode=Echoes`/`TargetFramework=.NETCore`
executables, so a plain build compiles fine but the exe fails at launch
with `FileNotFoundException` (see `HANDOFF.md` §10.2 and §12.3). The
script also assumes RemObjects Elements 13.0.0.3101 and a locally
installed .NET 10 SDK; adjust the version constant at the top if either
changes.

Before continuing implementation work, read `HANDOFF.md` (session handoff
notes, open questions, Phase 2 task priority order — §11 and §12
especially, for the MVP scope decisions and what's already built) and the
full design document, `docs/DESIGN.md` (English, canonical) /
`docs/DESIGN_jp.md` (Japanese translation).

## Architecture (from docs/DESIGN.md)

The tool loads .NET assemblies via reflection and generates TypeScript output
through a 5-stage pipeline built around a shared intermediate representation
(IR), so the output emitters don't each duplicate the same analysis:

1. **Assembly Loader** — loads the target + dependency assemblies as metadata
   only (no execution) → `RawAssemblyModel`.
2. **Semantic Analyzer / IR Builder** — integrates types, members,
   attributes, and XML docs; performs NRT analysis, cycle detection (Tarjan
   SCC), generics resolution, and enum-strategy decisions → `IrAssembly`.
   Everything downstream reads only the IR, never the raw reflection data.
3. **Type Mapping Layer (pluggable)** — resolves `IrType → TsTypeExpression`
   through a priority chain: user overrides → plugin rules → built-in rules,
   where the first rule whose `CanHandle` returns true wins (an explicit
   chain rather than a scoring system, chosen for debuggability).
4. **Emitters** (per output kind, can run in parallel) — `DtsEmitter`
   (`.d.ts`), `SchemaEmitter` (zod/io-ts), `ApiClientEmitter` (fetch
   wrappers).
5. **Writer / Diff Engine** — writes files, or in `--check` mode diffs
   against already-committed output for CI drift detection.

Other cross-cutting extension points follow the same "first match in a
priority chain wins" pattern as the type mapper: `ITypeMappingRule`,
`INullabilityProvider` (implemented, see below), `INamingStrategy`,
`ISchemaBackend`, `IEmitterExtension` (see `docs/DESIGN.md` §6).

**Pipeline stages report problems via `Tsgen.Diagnostics`, not direct
console I/O.** `AssemblyLoader.Load` and `DtsEmitter.Emit` both take a
`DiagnosticList` parameter and call `.AddWarning(...)` instead of
`writeLn` — this keeps them pure data transforms (matching the pipeline
design above), and lets `Program.pas` (the CLI entry point, the only
place allowed to touch the console beyond its own progress lines) print
everything together, once, to stderr at the end. The deduplication itself
happens inside `DtsEmitter.Emit`, not `Program.pas`: it collapses repeated
warnings about the same unmapped CLR type across many members into one
line before handing the result to `Program.pas` to print. See
`HANDOFF.md` §19 for why this was added and how it works.

**`AssemblyLoader.Load` can now load a real, multi-assembly application,
not just a self-contained fixture DLL** (`HANDOFF.md` §31, fixed after
`TeaTimeTracker`'s M3 validation pass hit this as a hard blocker before
any of its other findings could even run). Its `PathAssemblyResolver`
search paths now include, in priority order: the target assembly itself,
every other DLL in the target's own folder (e.g. a NuGet dependency
copy-located next to it), each shared framework named in the target's
own `<assembly>.runtimeconfig.json` (`Microsoft.AspNetCore.App`, etc. —
resolved under `C:\Program Files\dotnet\shared\`, with a same-major-
version fallback if the exact version isn't installed), and finally the
.NET runtime directory hosting `tsgen.exe` itself (the original,
pre-fix behavior, now the last-resort fallback). The `for each t in
asm.GetTypes()` loop also gained a per-type `try`/`except`: a type whose
resolution still fails (e.g. a genuinely unresolvable third-party
dependency) is skipped individually with a diagnostic instead of
crashing the whole process — this is what closed the gap the
"Pipeline stages report problems via `Tsgen.Diagnostics`" rule above
already called for but this loop didn't actually follow before. Don't
reintroduce a bare `for each t in asm.GetTypes() do begin ... end;`
without the per-type guard.

## Known unresolved technical risk

**Resolved 2026-08-01** (hands-on verification, see `HANDOFF.md` §8):
Oxygene's Echoes (.NET) backend does **not** emit
`NullableAttribute`/`NullableContextAttribute` for Oxygene-authored code.
Reflection alone therefore cannot recover NRT info for types Oxygene
itself wrote; the design relies on a source-level token scan built on the
Elements SDK's official tokenizer surface (`RemObjects.Elements.Code.TokenStream`,
reworked from an earlier `SimpleTokenizer`-based implementation — see
`HANDOFF.md` §7/§12.2/§16) as the primary `INullabilityProvider` chain
link (`OxygeneSourceScanProvider`, `HANDOFF.md` §21). `docs/DESIGN.md` §4 was
revised on 2026-08-02 to reflect all of this (done by the Fable5 review
agent at the user's request, together with the matching §10.1/§11-item-1
touch-ups and the full `DESIGN_jp.md` mirror), closing the doc-drift item
previously tracked in `HANDOFF.md` §8.3 — the design doc and this
conclusion now agree.

**Resolved 2026-08-02** (hands-on verification, see `HANDOFF.md` §10):
`System.Reflection.MetadataLoadContext` **is** usable directly from
Oxygene/Echoes (`HANDOFF.md` §4 item 2 / `docs/DESIGN.md` §11 item 2) —
metadata-only assembly loading for Stage 1 (Loader) is confirmed
technically viable, no custom ECMA-335 parser needed.

A separate, unrelated risk surfaced during that verification: EBuild's
`NuGetReference` packaging did not reliably populate `deps.json`'s
runtime-asset entries for the NuGet package the test required (compiled
fine, failed to run until `deps.json` was hand-patched). Before Phase 2's
CLI skeleton takes on any NuGet package as a runtime dependency, verify
the built output actually runs — don't assume a successful `EBuild`
compile implies correctly deployable output (`HANDOFF.md` §10.2).

No other unverified technical risk currently blocks starting §4 item 3
(minimal CLI skeleton + MVP implementation) — see `HANDOFF.md` §4 for the
full Phase 2 task priority order.

## Model selection for implementation work (Phase 2+)

- **Default: Sonnet 5** for the bulk of implementation, matching the
  Phase 1 (Fable5, design) → Phase 2 (Sonnet, implementation) handoff
  intent already stated at the top of `HANDOFF.md`. Oxygene is a niche
  language with sparse training data, so even boilerplate-looking code
  benefits from a stronger model — don't reflexively downgrade a task
  just because it looks mechanical.
- **Fable 5**: bring back for design-level judgment calls, not code — e.g.
  finalizing the "lightweight IR" scope left open in `HANDOFF.md` §2.1, or
  the still-pending `docs/DESIGN.md` §4 rewrite to reflect the NRT
  findings (`HANDOFF.md` §8.3).
- **Opus 5**: worth considering (via the `Agent` tool's `model` override)
  for algorithmically hard, bug-costly cores where reasoning depth matters
  more than breadth — Tarjan SCC cycle detection, the Tokenizer-based
  NRT/`Inertia.Render` scanner (see the multi-line/generics/alias fragility
  concerns in `HANDOFF.md` §2.9), and type-mapping-chain/generics
  interactions.
- **Haiku 4.5**: only for narrow, already-templated repetition done under
  review — e.g. replicating a type-mapping rule after the first instance
  is written by a stronger model. Given Oxygene's rarity in training data,
  the review overhead can outweigh the savings on a project this size;
  don't force it just to save cost.
- **Practical note:** switching this conversation's own model is a
  user-side choice made at session start, not something Claude can do
  mid-turn. The `Agent` tool's `model` parameter (`sonnet`/`opus`/`haiku`/
  `fable`) can delegate a self-contained, fully-specified subtask to a
  different model, but each such agent starts without this conversation's
  context — suited to isolated, spec-complete chunks of work, not
  interactive build/debug loops like the EBuild round-trips in
  `HANDOFF.md` §10.

## License constraints

The Elements install used for this project is a **Trial** license,
confirmed directly with RemObjects by email (2026-08-01 — see
`HANDOFF.md` §9):

- Never commit or publish built output (`bin/`, `obj/`, `*.dll`, `*.exe`,
  `*.pdb`, etc.) — distributing anything built with the Trial edition
  requires at least a Personal or Academic license. Source code is
  unaffected and may be published freely (RemObjects explicitly welcomed
  this).
- Casually using the Elements SDK's public API surface (e.g. the
  `Tokenizer` class) as a runtime dependency, without redistributing the
  DLLs themselves, is vendor-confirmed as permitted — not reverse
  engineering. This confirmation is narrow: it does not extend to
  decompilation, disassembly, or anything not explicitly asked about (see
  `HANDOFF.md` §9.1 scope note).
- **Resolved 2026-08-07** (vendor confirmation, see `HANDOFF.md` §9.2):
  the "3 days" figure in the original 2026-08-01 reply was a typo — the
  Trial edition's actual usage window is **30 days**, confirmed directly
  by RemObjects support in reply to the 2026-08-02 follow-up
  (`HANDOFF.md` §17 item 2). Not a hard blocker for Phase 2 work as
  originally feared; still worth tracking the 30-day window against the
  install date (2026-08-01) if a Personal/Academic license isn't
  obtained before then.

## Documentation conventions

- `docs/DESIGN.md` (English) is canonical; `docs/DESIGN_jp.md` is a full
  Japanese translation. Keep both in sync and mirror section numbering when
  editing either.
- `README.md` is bilingual: English and Japanese text are interleaved per
  paragraph/section in a single file, not split into separate files.
- Diagrams in the design documents use Mermaid `flowchart` blocks, not ASCII
  art.
