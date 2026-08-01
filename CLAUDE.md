# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Rules

- This project uses RemObjects Oxygene (Object Pascal for .NET).
- Never write C# code. Always output valid Oxygene syntax.

## Project Status

Phase 1 (design) is complete; Phase 2 (implementation) has not started. `src/`
and `tests/` are currently empty (only `.gitkeep`). There is no build, lint,
or test tooling in this repository yet — do not assume any commands exist
until Phase 2 scaffolding is added.

Before starting implementation work, read `HANDOFF.md` (session handoff
notes, open questions, Phase 2 task priority order) and the full design
document, `docs/DESIGN.md` (English, canonical) / `docs/DESIGN_jp.md`
(Japanese translation).

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

The current top unverified technical risk instead: whether a
`System.Reflection.MetadataLoadContext`-equivalent (metadata-only assembly
loading) is usable directly from Oxygene/Echoes (`HANDOFF.md` §4 item 2 /
`docs/DESIGN.md` §11 item 2) — not yet investigated hands-on.

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
