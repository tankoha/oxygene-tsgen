# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Rules

- This project uses RemObjects Oxygene (Object Pascal for .NET).
- Never write C# code. Always output valid Oxygene syntax.

## Project Status

Phase 1 (design) is complete. Phase 2 (implementation) has a working MVP:
`src/Tsgen` is a CLI (`tsgen generate --assembly <dll> --source <dir>
--out <dir>`) covering Stage 1 (Loader, via `MetadataLoadContext`), a
Tokenizer-based NRT source scanner, a lightweight Stage 2 IR, and a
single-file Stage 4 `DtsEmitter` — see `HANDOFF.md` §12 for what was
built, how, and its known limitations. Still missing: cycle detection,
generics, the pluggable type-mapping/plugin chain, split-file output, and
automated tests (`docs/DESIGN.md` §10.2 has the post-MVP order).

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
`INullabilityProvider`, `INamingStrategy`, `ISchemaBackend`,
`IEmitterExtension` (see `docs/DESIGN.md` §6).

## Known unresolved technical risk

**Resolved 2026-08-01** (hands-on verification, see `HANDOFF.md` §8):
Oxygene's Echoes (.NET) backend does **not** emit
`NullableAttribute`/`NullableContextAttribute` for Oxygene-authored code.
Reflection alone therefore cannot recover NRT info for types Oxygene
itself wrote; the design now relies on a source-level token scan using
the official `RemObjects.Elements.Code.Oxygene.Tokenizer` class
(`RemObjects.Elements.Oxygene.dll`, see `HANDOFF.md` §7) as the primary
`INullabilityProvider` implementation. `docs/DESIGN.md` §4 still needs to
be revised to reflect this (tracked in `HANDOFF.md` §8.3) — don't assume
the doc's current text matches this conclusion until that revision lands.

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
  without checking this first.

## Documentation conventions

- `docs/DESIGN.md` (English) is canonical; `docs/DESIGN_jp.md` is a full
  Japanese translation. Keep both in sync and mirror section numbering when
  editing either.
- `README.md` is bilingual: English and Japanese text are interleaved per
  paragraph/section in a single file, not split into separate files.
- Diagrams in the design documents use Mermaid `flowchart` blocks, not ASCII
  art.
