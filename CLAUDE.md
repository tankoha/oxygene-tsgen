# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Rules

- This project uses RemObjects Oxygene (Object Pascal for .NET).
- Never write C# code. Always output valid Oxygene syntax.

## Project Status

Phase 1 (design) is complete. Phase 2 (implementation) has a working MVP,
hardened well past the original bullet list: `src/Tsgen` is a CLI (`tsgen
generate --assembly <dll> --source <dir> --out <dir>`) covering Stage 1
(Loader, via `MetadataLoadContext`), a Tokenizer-based NRT source scanner
feeding an `INullabilityProvider` chain, a lightweight Stage 2 IR with
generics support (`List<T>`/`Dictionary<K,V>`/`Nullable<T>`/arrays/
user-defined-type references), and a single-file Stage 4 `DtsEmitter` —
see `HANDOFF.md` §12/§23 for what was built, how, and its known
limitations. Still missing: cycle detection (deliberately deferred, see
below), the pluggable type-mapping/plugin chain, split-file output, and
the Inertia.js-specific entry-point scanner (spiked and confirmed
feasible, not yet implemented — `HANDOFF.md` §22). `docs/DESIGN.md`
§10.2 has the post-MVP order.

**Automated snapshot tests exist now:** run `tools/run-tests.ps1` (builds
the CLI + every fixture under `tests/fixtures/`, then diffs `tsgen`
output against committed `expected/*.d.ts` snapshots per fixture's
`cases.json`). Pass `-UpdateSnapshots` to regenerate expectations after
an intentional output change. See `HANDOFF.md` §15. Five fixtures exist,
12 cases total: `SampleModel` (enums, explicit NRT, all three
`--nrt-unknown-policy` values via its deliberately-still-`Unknown` `Notes`
field — see `HANDOFF.md` §21.3 for why that field exists),
`TokenizerEdgeCases` (NRT keywords inside comments/string literals, no
trailing newline, also covers `mark-unknown`), `MultiTypeAndIndexer`
(multiple types sharing one `type` section, indexer-style properties —
see `HANDOFF.md` §18), `NestedTypeCollision` (a nested type's
annotated property must not overwrite an outer, same-named member's
nullability — see `HANDOFF.md` §20), and `Generics` (`List<T>`/
`Dictionary<K,V>`/`Nullable<T>`/arrays/self-referential named-type
references — see `HANDOFF.md` §23.4). Nested types themselves remain
uncovered and out of scope for real
support: `AssemblyLoader` filters out every `t.IsNested` type before it
reaches the IR, and `DtsEmitter` has no nested-`interface` output path
either, so giving a nested type's own members their own output would need
coordinated Loader + IR + Emitter changes, not a scanner fix. That's
distinct from `NullabilityScanner` correctly *ignoring* nested-type
members without corrupting an outer member's data, which the scanner
alone is responsible for and now does (`HANDOFF.md` §20 — a `(depth =
typeDepth)` guard was missing on the property-scanning branch). See
`HANDOFF.md` §18.1/§20 for the full explanation.

**Nullability is resolved through the `INullabilityProvider` chain**
(`src/Tsgen/Nrt/NullabilityProviders.pas`, `HANDOFF.md` §21), not a
direct dictionary lookup: `IrBuilder.Build` tries
`OxygeneSourceScanProvider` (the source scan's explicit annotations)
first, then `ValueTypeDefaultProvider` (known CLR value types are
non-nullable unless explicitly annotated otherwise) — first non-`Unknown`
answer wins. Consequence worth remembering: an unannotated *value-typed*
member (`Int32`, `Boolean`, etc.) is no longer `Unknown` at all, so
`--nrt-unknown-policy` has nothing to act on for it — only unannotated
*reference-typed* members stay genuinely `Unknown`. `--nrt-unknown-policy`
has three values: `nullable` | `non-null` | `mark-unknown` (the last
renders the same bare type as `non-null` plus a trailing `// nrt:
unknown` comment, since TypeScript can't express "undetermined" as a
distinct type). Provider 2 (reflection-attribute-based, for C#/VB
dependency assemblies) remains genuinely unimplemented — don't add a stub
for it without a real need.

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
brace-containing code sample inside one (confirmed the hard way,
`HANDOFF.md` §23.6).

**Cycle detection (Tarjan SCC, `docs/DESIGN.md` §3) is deliberately not
implemented.** §3.3 already states cycles can generally be ignored for
`DtsEmitter` specifically (TS `interface`/`type` tolerates circular
references natively) — its real value is the zod `SchemaEmitter` (not
built) and single-file output ordering (cosmetic). Don't add it
speculatively; revisit once the zod emitter actually needs `lazy()`
wrapping.

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
- **Unresolved:** the same vendor reply implies Trial usage itself may be
  capped at 3 days, separately from the distribution restriction above.
  Exact meaning unconfirmed as of 2026-08-01 (calendar days since install?
  cumulative days of use? evaluation sessions?) — see `HANDOFF.md` §9.2.
  Don't assume extended Trial access is available for Phase 2 work
  without checking this first. A follow-up asking the vendor to confirm
  whether "3 days" was a typo for "30 days" was sent 2026-08-02
  (`HANDOFF.md` §17 item 2); no reply yet as of that writing. Check
  `HANDOFF.md` §9.2/§17 for the current answer before treating the 3-day
  figure as settled.

## Documentation conventions

- `docs/DESIGN.md` (English) is canonical; `docs/DESIGN_jp.md` is a full
  Japanese translation. Keep both in sync and mirror section numbering when
  editing either.
- `README.md` is bilingual: English and Japanese text are interleaved per
  paragraph/section in a single file, not split into separate files.
- Diagrams in the design documents use Mermaid `flowchart` blocks, not ASCII
  art.
