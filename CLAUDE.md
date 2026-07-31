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

It has not been verified whether Oxygene's Echoes (.NET) backend emits
`NullableAttribute`/`NullableContextAttribute` — the Roslyn-specific IL
convention C# uses to encode nullable reference type info. This is the
top-priority item to verify at the start of Phase 2 (see `HANDOFF.md` §3–4).
The NRT design (`docs/DESIGN.md` §4) is deliberately built as a swappable
`INullabilityProvider` chain to absorb this uncertainty.

## Documentation conventions

- `docs/DESIGN.md` (English) is canonical; `docs/DESIGN_jp.md` is a full
  Japanese translation. Keep both in sync and mirror section numbering when
  editing either.
- `README.md` is bilingual: English and Japanese text are interleaved per
  paragraph/section in a single file, not split into separate files.
- Diagrams in the design documents use Mermaid `flowchart` blocks, not ASCII
  art.
