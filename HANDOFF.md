# HANDOFF: oxygene-tsgen

> 🇯🇵 [日本語版はこちら / Japanese version](./HANDOFF_jp.md)

This file is for handoff between sessions (Phase 1 design session on Fable5 →
Phase 2 implementation sessions on Sonnet, and beyond). Sessions starting
Phase 2 work should read this file and `docs/DESIGN.md` before doing anything
else.

---

## 1. What this session (Phase 1 / Fable5) did

- `docs/DESIGN.md`: wrote the full-scope design document (architecture, type
  mapping layer, cycle detection, NRT analysis policy, metadata reflection,
  output structure, plugin mechanism, IR data structures, API integration, CI
  design, MVP scope and implementation order).
- `README.md`: wrote the project overview and status.
- Created `src/`, `tests/`, `.github/workflows/` as empty directories only.
- No implementation code was written. No packages were installed.
- `git push` was not run (local commits only; `origin` was never touched).

## 2. Points that were difficult to decide while writing DESIGN.md, and why each alternative was chosen

### 2.1 Pipeline stage count: 5 stages with an IR in between, vs. a simplified 2-stage design

- Alternative considered: a simplified pipeline where the Loader assembles the
  TS AST directly.
- Adopted: a 5-stage pipeline with an IR (`IrAssembly`) in between
  (`docs/DESIGN.md` §1).
- Why: multiple output formats (`.d.ts` / zod schemas / API clients) need to
  share the same analysis results (NRT analysis, cycle detection, etc.), so
  using the IR as a common foundation avoids duplicating that analysis per
  emitter.
- Point of hesitation: this could be seen as over-engineering for a
  tool of MVP scale. The plan is for the MVP to start from a "lightweight IR"
  that simplifies Stage 2 (NRT analysis, etc.), but the concrete scope of
  what that lightweight IR omits still needs to be decided first thing in
  Phase 2 (see the task list in §3).

### 2.2 Type-mapping rule priority scheme: scoring vs. an explicit chain

- Alternative considered: a scoring scheme that automatically picks the "most
  specifically matching rule" when multiple rules' `CanHandle` return true.
- Adopted: an explicit priority chain where "the first rule whose
  `CanHandle` returns true wins" (`docs/DESIGN.md` §2.2, §2.3).
- Why: a scoring scheme is implicit, and plugin authors would have a hard
  time understanding "why isn't my rule being called" — debuggability was
  prioritized.

### 2.3 Plugin distribution: dynamic assembly loading vs. declarative config files

- Three options considered (comparison table in `docs/DESIGN.md` §6.3):
  (A) dynamically loading .NET assemblies, (B) declarative rules in
  JSON/YAML, (C) protocol communication with an external process.
- Adopted: implement B first; keep A only as a future extension interface.
  C is out of scope for now.
- Why: by analogy with how common code-generation tools operate in practice
  (TypeGen, NSwag, OpenAPI Generator, etc.), most customization needs are
  expected to be covered by declarative rules. Actual demand is unverified,
  though, and priority should be revisited if user feedback comes in during
  Phase 2 or later.

### 2.4 Default behavior when NRT info is unknown: safe side (treat as nullable) vs. type-usefulness side (treat as non-null)

- Adopted: rather than committing to either default, treat the `Unknown`
  state as first-class in the `INullabilityProvider` chain, and let the user
  choose the policy via `--nrt-unknown-policy` (`docs/DESIGN.md` §4.2, §4.3).
- Why: if the tool makes an implicit safety judgment, it creates risk either
  way — either runtime errors from over-relying on the safe side and writing
  designs that wrongly disallow null, or reduced type usefulness from
  over-widening to nullable. Letting the user choose explicitly was judged
  the more honest approach.

### 2.5 Cycle-detection algorithm: plain DFS vs. Tarjan's SCC

- Adopted: Tarjan's strongly-connected-components decomposition
  (`docs/DESIGN.md` §3.2).
- Why: not just "does a cycle exist" but "which group of types the cycle
  contains" is needed for zod schema `lazy()`-wrapping and for deciding
  output order (topological sort), so designing around SCCs from the start
  keeps things consistent with downstream stages. Plain DFS detection is
  simpler to implement, but it would mean re-deriving the grouping
  information separately — extra, duplicated work.

### 2.6 API integration: generate the OpenAPI spec itself, or only integrate with an existing OpenAPI spec

- Considered: the tool could generate an OpenAPI spec (JSON/YAML) from
  scratch by itself, but the OpenAPI-generation ecosystem for ASP.NET Core
  (Swashbuckle, etc.) is already mature, so to avoid reinventing the wheel
  only an integration mode was designed, combining "an existing OpenAPI spec
  + high-precision types from the assembly" (`docs/DESIGN.md` §8.1).
- Unresolved: the concrete convention/implementation for linking
  `operationId` to the controller/action's fully-qualified name needs
  investigation (reflected in the §3 task list).

### 2.7 Language of README / DESIGN / HANDOFF

- Written primarily in Japanese (because interaction with the user is in
  Japanese). Only the very top of the README carries a one-line English
  summary (for general discoverability on GitHub). If OSS publication becomes
  a stronger consideration going forward, adding an English README is worth
  considering (left as a Phase 2+ decision).

### 2.8 English translation of DESIGN.md (added: work done in a separate session)

- `docs/DESIGN.md` (formerly the Japanese version) was renamed to
  `docs/DESIGN_jp.md`, and a new English `docs/DESIGN.md` was created as a
  full translation. Both files cross-link to each other at the top
  (🇯🇵/🇬🇧). Going forward, `docs/DESIGN.md` is "primary" and
  `docs/DESIGN_jp.md` is the Japanese translation.
- The `docs/DESIGN.md#10-mvpスコープと将来拡張の境界線` link inside
  `README.md` (a Markdown anchor pointing at a Japanese heading) broke
  because the English translation changed the heading. **Option B (point it
  at the English DESIGN.md's English heading anchor instead)** was adopted,
  fixing it to
  `docs/DESIGN.md#10-mvp-scope-and-the-boundary-for-future-extensions`.
  - Why: the top of the README already carries an English summary, matching
    the policy that the design document referenced by the plain filename
    `docs/DESIGN.md` should be the English version. Readers who want Japanese
    can navigate to `DESIGN_jp.md` via the language-switch link at the top of
    each file, so redirecting the README's link to the Japanese version
    (Option A) was judged unnecessary.
- References of the form `docs/DESIGN.md §X` elsewhere in this file (section
  number references without a URL anchor) needed no changes, since the
  section numbering is fully identical between the English and Japanese
  versions (as instructed).

### 2.9 Reconsidering the input method: parsing Oxygene source vs. reflection over compiled assemblies

(Discussion as of 2026-08-01, after the shift to an Inertia.js focus in §6)

- Considered: after §6 revealed that the Inertia.js target backend is
  Oxygene-only, a shift was considered from DLL reflection to directly
  parsing the Oxygene source code (including project files). With source
  parsing, NRT (`nullable`/`not nullable`) could be read directly from
  syntax rather than depending on the presence of IL attributes
  (`NullableAttribute`, etc.), and detecting `Inertia.Render` calls
  (`docs/DESIGN.md` §3.5) would just mean walking the syntax tree — this
  had the potential to resolve both of the two major open technical
  uncertainties (item 4 in §3 of this file, and `docs/DESIGN.md` §3.5) at
  once.
- Rejected (full-parser option only): the user confirmed that RemObjects
  Elements/Oxygene has no independent parser/AST (abstract syntax tree)
  public API available for external tools to use (the only public material
  is the syntax/namespace reference at
  https://www.remobjects.com/elements/oxygene/language — there is no
  compiler API equivalent to Roslyn's `Microsoft.CodeAnalysis`). Writing a
  **complete** from-scratch parser/AST for Oxygene's grammar would carry a
  far larger implementation cost, and an ongoing cost of tracking language
  spec changes, than the existing reflection-based design — so this option
  is rejected.
- A separate option left undecided (distinct from the full-parser option,
  not yet rejected): rather than "complete grammar parsing," a **lightweight,
  partial source-text scan** aimed only at detecting `nullable`/`not
  nullable` tokens and text-pattern-matching `Inertia.Render(...)` call
  sites (roughly regex- or simple-tokenizer-level, without building a full
  syntax tree) may not be subject to the same rejection reasons as the full
  parser (implementation cost, spec-tracking cost), and was left
  unevaluated as something to assess separately. However, this approach has
  its own specific risk of being fragile against calls spanning multiple
  lines, generics, aliases, and indirect calls via helper methods, so it
  should not be adopted just because it's "cheap" without further thought —
  it should be concretely evaluated in Phase 2 (after adding a task to the
  §4 list below to check what's bundled with the SDK, revisit the
  cost/benefit of this scan-based approach as well).
- Conclusion: given the above open question, the plan for now remains to
  keep the compiled-assembly reflection approach as the main axis. Note,
  however, that this does not resolve `docs/DESIGN.md` §3.5 (entry-point-
  driven type discovery): as that section points out, anonymous types lose
  their name information at the IL level, so IL/expression-tree analysis
  can actually be *harder* than source access for this particular problem.
  So keeping the reflection approach doesn't "solve" the §3.5 problem, it
  merely "carries it forward unresolved" — and it may mean giving up on what
  could have been the easiest resolution path (source access). The technical
  uncertainty around §4 (NRT analysis) likewise remains unresolved in the
  same way (the priority of the verification tasks at the start of Phase 2
  is unchanged, still top priority).
- Room for reconsideration: if RemObjects ever offers a public parser/AST
  API in the future, or if the Fire/Water IDE's completion feature exposes
  syntax information externally via something equivalent to the Language
  Server Protocol (LSP), a hybrid approach (parse this project's own source,
  use reflection for external dependencies like the BCL/NuGet) would be
  worth reconsidering. This can be checked, ahead of a full-blown LSP
  protocol investigation, via a cheap first step (see §4 below).

---

## 3. Constraints and caveats found while researching Oxygene's `System.Reflection` compatibility

Findings from web research (as of July 2026). RemObjects Elements is a
weekly-release product, so re-verifying primary sources at the start of
Phase 2 is recommended.

1. **The .NET target backend is named "Echoes".** Multiple front-end
   languages (Oxygene/C#/Swift/etc.) generate IL through this shared
   backend; RemObjects' official description states it "compiles to IL code
   just like Microsoft's Visual C#/VB compilers, and runs anywhere the CLR
   runs." → Standard metadata (types, members, custom attributes in
   general) should be readable without issue via `System.Reflection`-
   compatible APIs, but this is only the general picture — the specific
   behaviors below (2, 3) need separate verification.

2. **【Highest priority, unverified】Whether NRT (`nullable`/`not nullable`)
   is emitted in IL as `System.Runtime.CompilerServices.NullableAttribute` /
   `NullableContextAttribute` could not be confirmed within the scope of
   official documentation researched.** These attributes are an output
   convention specific to the C# compiler (Roslyn), not a CLR standard
   feature. There is no guarantee Oxygene follows the same convention.
   - Strongly recommend that, very early in Phase 2, a small test assembly
     using `nullable`/`not nullable` be built in Oxygene, and the IL
     disassembled with `ildasm`/`monodis`/`dotnet-ildasm`/etc. to check for
     the presence of `NullableAttribute`/`NullableContextAttribute` (see §4
     for the concrete task).
   - If a different attribute is used instead, this can be accommodated by
     adding an `OxygeneNativeNullabilityProvider` to the
     `INullabilityProvider` chain designed in `docs/DESIGN.md` §4.2 (the
     design should be able to absorb this, but it's unverified).

3. **Whether Oxygene's documentation-comment syntax outputs the same XML doc
   format as C# (`AssemblyName.xml`) is unconfirmed.** Oxygene appears to
   support `///`-style comments (needs re-confirmation), but how the
   equivalent of MSBuild's `<GenerateDocumentationFile>` is enabled in
   Elements' build settings, and whether the file format is fully compatible
   with C#'s, could not be explicitly confirmed from official documentation.

4. **Whether a metadata-only assembly loading mechanism (equivalent to
   `MetadataLoadContext`) is available from Oxygene/Echoes is unverified.**
   If this tool itself is designed to "read only metadata from the target
   assembly without executing it" (a premise of the design document as a
   whole), technical verification is needed on whether .NET's standard
   `System.Reflection.MetadataLoadContext` can be called without issue from
   Oxygene, or whether a from-scratch ECMA-335 metadata parser would be
   needed instead.

5. **The feasibility of dynamic plugin assembly loading
   (`docs/DESIGN.md` §6.3 Option A) is unverified.** If the CLI is built
   with Elements' Island backend (native AOT), the dynamic-loading API
   itself may be constrained (this is generally true of AOT environments,
   not necessarily an Elements-specific issue, but needs confirming).

---

## 4. Priority order of tasks Phase 2 (the implementation phase) should tackle first

**Note on the environment for the hands-on verification tasks (1, 2, 2.5),
as of 2026-08-01:** these require an actual development environment
(RemObjects Elements/Water) — building Oxygene code, disassembling IL,
checking what's bundled with the local SDK — so they cannot be carried out
in this design-phase session's environment (web/CLI only). The next session
is expected to be done on a Windows machine with Elements/Water installed,
using the Claude desktop app (Code tab). It has been confirmed that local
sessions in the Code tab are not sandboxed, and have the same access to
local shell commands and the filesystem as the CLI version of Claude Code.
Note that using Bash on Windows requires
[Git for Windows](https://git-scm.com/downloads/win) to be installed
beforehand (it falls back to PowerShell if not installed).

1. **【Highest priority, blocker resolution】Verify Oxygene(Echoes)'s NRT
   output hands-on.** Build a small Oxygene project with classes using
   `nullable`/`not nullable`, and check via IL disassembly whether
   `NullableAttribute`/`NullableContextAttribute` are present. The result
   determines the initial `INullabilityProvider` implementation (whether
   `RoslynStyleAttributeProvider` suffices, or a custom provider is needed).
2. **Technical verification of the assembly metadata loading approach.**
   Check whether something equivalent to
   `System.Reflection.MetadataLoadContext` can be used from Oxygene, and if
   not, identify alternatives (writing an ECMA-335 parser from scratch, or
   researching existing libraries).
2.5. **【Cheap, recommended to do first】Check whether the locally installed
   Elements/Water SDK bundles a language-server binary or a hidden
   compiler flag for AST-dumping that the Fire/Water IDE's completion
   feature uses internally.** (Relevant to the "lightweight source-text
   scan" option left undecided in §2.9, and to the feasibility of the
   entry-point-driven discovery in `docs/DESIGN.md` §3.5.) Since the IDE
   provides completion and refactoring, it must be getting syntax
   information somehow — this is just a check of whether that's already
   included in the SDK in an externally callable form, so it can be started
   in minutes to hours, ahead of a full-blown LSP protocol investigation.
   If nothing is found, the §2.9 "lightweight scan vs. sticking with
   reflection" decision stands as-is.
3. **Minimal CLI skeleton + MVP implementation of Stage 1 (Loader) /
   Stage 2 (lightweight IR) / Stage 4 (DtsEmitter).** Get the MVP scope from
   `docs/DESIGN.md` §10.1 (primitives, enums, nullable, namespace-based
   output) working first. Do not implement cycle detection or the plugin
   mechanism at this point (follow the priority order in §10.2).
4. **Set up minimal test infrastructure for the MVP.** Prepare Oxygene-built
   sample test assemblies (small groups of classes covering primitives,
   enums, nullable reference types) under something like `tests/fixtures/`,
   and set up a snapshot-comparison mechanism against the expected `.d.ts`
   output first (to prevent regressions as features are added later).
5. **Implement XML Doc → JSDoc, and `[Obsolete]` → `@deprecated`.** This is
   third in §10.2's list, but since it's low implementation cost and has a
   high perceived benefit, starting on it early, right after the MVP, is
   recommended.
6. From here on, follow the priority list in `docs/DESIGN.md` §10.2 (cycle
   detection → metadata attribute reflection → custom type overrides → …).

### Other small things to confirm before starting

- The package distribution method (npm / dotnet tool / standalone binary)
  is unresolved item 4 in `docs/DESIGN.md` §11. Since it affects the shape
  of the implementation's entry point, it's worth deciding at least the
  direction before starting to write the CLI skeleton.
- How to incorporate the Elements/Oxygene build configuration (project file
  structure equivalent to `.elements`/`.sln`) into this repository (the
  layout under `src/`) should be decided at the start of Phase 2 while
  consulting Elements' CLI toolchain documentation (the design document
  deliberately stayed language-agnostic and did not go into
  Oxygene-specific project structure).

---

## 5. Points intentionally left unorganized (noted here just in case)

- `docs/DESIGN.md` is a text-based design document, and diagrams are kept at
  roughly the level of ASCII art. If more detailed sequence diagrams etc.
  become necessary, create them separately in Phase 2 or later.
- Concrete version selection/installation of external libraries (zod/io-ts,
  a test framework, etc.) has not been done (per instruction, only
  candidates were presented). Since zod's API differs between the v3 and v4
  lines, check the latest stable version and select at the start of Phase 2.
- The GitHub Actions workflow YAML only has its policy documented in
  `.github/workflows/README.md`; it has not been implemented (accepted as
  low priority per instruction).

---

## 6. 【Important — added design premise】Shift to an Inertia.js-focused use case

This section is a premise added after the existing `docs/DESIGN.md` and
§1–5 of this file were written. Whichever session next touches DESIGN.md
(whether Fable5 is brought back in, or a Phase 2 implementation session),
**read this section first, with top priority, and identify where it affects
the existing design.**

### 6.1 Intent of the change

Narrow the primary use case of this tool (oxygene-tsgen) from the general
".NET assembly → TypeScript type-definition generation" to **generating
frontend types for ASP.NET Core applications that use Inertia.js**.
Specifically, the focus becomes generating the TypeScript type for the
`data` object that a controller returns via
`Inertia.Render(componentName, data)` (assuming one of the ASP.NET Core
Inertia adapters — InertiaNetCore / InertiaCore / inertia-dotnet / etc.;
which one exactly is an open question, see §6.4) as the Props type for the
corresponding frontend page component.

### 6.2 Impact on the existing design (items that need to be surveyed)

- **§8 (API integration) may become less central.** The existing design was
  oriented toward "integrating with an OpenAPI spec" and "generating
  per-endpoint fetch-wrapper clients," but Inertia.js differs from the
  typical REST API client pattern (fetching JSON via `fetch`) — it's
  server-side routing plus props embedded at page-transition time. It needs
  to be decided first whether the §8 design should be redone for Inertia,
  or kept as a separate, coexisting use case.
- **Newly needed type-generation targets:**
  - **Page Props types**: from the anonymous type/POCO of `data` in
    `Inertia.Render("PageName", data)`, generate the Props type consumed by
    the corresponding frontend-side component (e.g.
    `resources/js/Pages/PageName.tsx`) — a mapping from component name to
    Props type.
  - **Shared Data types**: if data common to every page (authenticated user
    info, flash messages, etc.) is injected via a mechanism equivalent to
    the Inertia middleware's `share()`, this needs to be merged into a type
    together with each page's own Props (whether the existing design has a
    merge mechanism needs to be checked).
  - **Form types (for `useForm()`)**: Inertia's client-side `useForm()` hook
    requires initial values and validation-error types for form fields.
    Being able to generate the validation-error type (a field-name →
    error-message mapping) from .NET-side validation attributes (`[Required]`
    etc., already covered by the existing §5 metadata reflection) would add
    a lot of practical value.
- **Cycle detection (§3) and NRT analysis (§4) will likely still apply as-is**,
  but a new idea is needed: analysis driven by "which types are needed per
  page" (entry-point-driven type collection). The existing design assumed
  "scan the whole assembly and output all types," so a shift may be needed
  toward a discovery approach that "detects the `Inertia.Render` call sites
  in controllers, and only follows the types actually used from there" (i.e.
  static analysis may need to trace IL/expression trees inside C#-equivalent
  method bodies).

### 6.3 New investigation items to consider (add to the start-of-Phase-2 task list)

- Selecting which ASP.NET Core Inertia adapter to adopt (InertiaNetCore /
  InertiaCore / spark-inertiajs / inertia-dotnet / etc. — multiple forks and
  implementations currently exist, so compare by update frequency and
  feature coverage before deciding).
- Confirming how the chosen adapter types the `data` argument of
  `Inertia.Render(componentName, data)` (is it an `object` parameter, does
  it use generics?).
- Technical verification of how to detect `Inertia.Render` calls from inside
  controller method bodies (will Roslyn-style expression-tree analysis be
  needed, or is IL analysis sufficient?).
- The shape of the generated Props type (`interface Props { ... }` vs. a
  type for `defineProps<...>()`, etc.) changes depending on the frontend
  framework assumed (React / Vue / Svelte). The target framework needs to be
  settled.

### 6.4 Open questions

- Selection of the adapter and frontend framework above is unresolved —
  settle this in the next session, or the next conversation with the user.
- Whether to replace the existing §8 (generic API integration) with an
  Inertia-oriented version, or keep both as coexisting modes, needs a
  decision (from an over-engineering-avoidance standpoint, unifying around
  Inertia for now is the simpler choice for the MVP).

---

## 7. Task 2.5 results: investigating LSP/AST-dump functionality bundled with the SDK (Windows hands-on, 2026-08-01)

Environment: RemObjects Elements 13.0.0.3101 (develop),
`C:\Program Files (x86)\RemObjects Software\Elements\`

### 7.1 Investigation method

- Searched under `bin/` for filename patterns (server/lsp/ast/dump) → the
  only hits were the Data Abstract (a separate product) `ServerAccess`
  templates, judged unrelated to a language server.
- Checked `EBuild.exe --help` → no hidden AST-dump/parse-only-style flags.
  A `--host` (interactive host mode) option exists, but its purpose is
  unverified (most likely aimed at speeding up incremental builds, doesn't
  look aimed at exposing an AST).
- Loaded the major DLLs (`RemObjects.Elements.Compiler.dll`,
  `RemObjects.Elements.dll`, `RemObjects.Elements.Oxygene.dll`,
  `RemObjects.Elements.Tools.dll`, etc.) via .NET reflection and searched
  for type names related to AST/Syntax/Parser/Tokenizer/LanguageServer.

### 7.2 Findings

1. **【Important】A real, public, instantiable Oxygene tokenizer exists.**
   `RemObjects.Elements.Code.Oxygene.Tokenizer` in
   `RemObjects.Elements.Oxygene.dll` (constructor argument:
   `RemObjects.Elements.Code.TokenStream`, also `public`) is a `public`
   class — the production-quality lexer the IDE itself uses for completion.
   It exposes token kind and row/column position.
   → For the "lightweight source-text scan" left undecided in §2.9,
   **recommend building on this official Tokenizer rather than a
   hand-rolled regex/simple tokenizer**. It correctly ignores string
   literals, comments, and interpolated strings while detecting
   `nullable`/`not nullable` tokens and handling paren-matching for
   `Inertia.Render(...)` call detection — a big reduction in
   language-spec-tracking cost compared to hand-rolled lexing. It does not,
   however, provide a syntax tree (nested expression structure), so a
   lightweight parser still needs to be layered on top of the token stream
   for things like calls spanning multiple lines or disambiguating generic
   `<>` — though this remains far lighter-weight than a full parser.

2. **A large number of AST-like node types exist as public types inside the
   compiler (`RemObjects.Elements.Compiler.dll`).**
   `RemObjects.Elements.Code.CallExpressionTransform`,
   `IfStatementTransform`, `TypeStatementTransform`,
   `MethodStatementTransform`, etc. — types for each kind of
   expression/statement are exported as `public`. However, these are node
   types internal to the compiler's pass-transform pipeline, and no simple
   public entry point equivalent to Roslyn's
   `SyntaxFactory.ParseSyntaxTree` ("source string → syntax tree") was
   found. Setting up a full compilation unit/project context would likely
   be required, and this doesn't look like something simple to invoke
   (not investigated further, needs additional research).

3. **`RemObjects.Elements.Tools.dll` has an `IOxygeneCodeModelParser`
   (`Parse(string) : System.CodeDom.CodeCompileUnit`), but the
   implementation class is named `WinFormsCodeParser`, and it's judged to be
   a CodeDOM-based, limited parser intended for reading/writing the
   declarative code used by the WinForms designer (equivalent to
   `InitializeComponent()`).** CodeDOM's expressiveness is limited and
   doesn't support general expression evaluation, so this isn't suited to
   general-purpose analysis like detecting `Inertia.Render(...)` calls
   inside arbitrary method bodies.

4. No standalone LSP implementation or "hidden AST-dump-only CLI flag" was
   found. The Water/Fire IDE's completion feature is presumably calling the
   compiler's internal code-quality-check machinery (item 2 above) directly
   within the host process, and does not appear to be factored out as an
   LSP server for external processes.

### 7.3 Impact on §2.9 / §4 (direction)

- Recommend adopting the "lightweight source-text scan" option **based on
  the official `RemObjects.Elements.Code.Oxygene.Tokenizer`**. This
  decision lets the comparison against the reflection-based approach (left
  pending in §2.9) resume early in Phase 2.
- The full-AST approach (item 2 above) has an unclear public entry point
  and a high additional-investigation cost, so it's deferred for now;
  revisit later in Phase 2 if there's spare capacity.

---

## 8. Task 1 results: verifying Oxygene's NRT output hands-on (Windows hands-on, 2026-08-01)

**Conclusion (highest-priority blocker resolved): Oxygene's Echoes backend
emits no `nullable`/`not nullable` information whatsoever into compiled
assembly metadata.** Not only were `NullableAttribute`/
`NullableContextAttribute` absent, but so was any similar custom attribute
or custom modifier (modopt/modreq). The unverified item from §3-2 is now
settled — and with a result that has a bigger design impact than
"Oxygene uses a different custom attribute than Roslyn": it turns out
Oxygene **leaves no trace of this information in IL/metadata at all**.

### 8.1 Verification method

1. Created a minimal class-library project with fields, properties, and
   method parameters/return values using `nullable String` /
   `not nullable String` (an `.elements` project file,
   `TargetFramework=.NETStandard`, `Mode=Echoes`).
2. Built it with `EBuild.exe` (Release configuration). A secondary fact
   discovered during the build: **fields/properties declared
   `not nullable` are required by the compiler to be initialized at the
   declaration site** (`E: Not nullable type requires initialization`) —
   i.e. the nullable check itself is a real language feature enforced by
   the Oxygene compiler (not just decorative syntax).
3. Inspected the resulting `NrtProbe.dll` via .NET reflection
   (`System.Reflection.Assembly.LoadFile` + `CustomAttributeData`),
   enumerating custom attributes at every level — assembly, module, type,
   field, property, and method parameter/return value. Also checked
   modopt/modreq via `GetOptionalCustomModifiers()` /
   `GetRequiredCustomModifiers()`.

### 8.2 Verification results

- Assembly-level attributes: only `DebuggableAttribute` and
  `TargetFrameworkAttribute` (nothing Nullable-related).
- Module-level attributes: none.
- Type-level attributes (`NrtProbe.Sample`): none.
- Field attributes: none on `NullableField` / `NotNullableField` /
  `PlainField` (the auto-generated backing fields for properties only carry
  `CompilerGeneratedAttribute`, unrelated to nullability).
- Property attributes: none on `NullableProp` / `NotNullableProp` /
  `PlainProp`.
- Method parameter/return-value attributes: none on either the parameters
  or return values of `NullableParamMethod` / `NotNullableParamMethod`.
- Field custom modifiers (modopt/modreq): empty for every field.
- No type definitions with "Nullable" in the name exist in the assembly
  either (i.e. no self-contained definition of
  `NullableAttribute`/`NullableContextAttribute`, which Roslyn sometimes
  embeds for older TFMs).
- Cross-verification against raw IL via `ildasm` or similar was not
  performed, since the tool wasn't installed — but `CustomAttributeData`
  reads directly from the metadata tables, so the "no attributes present"
  result stands on its own as conclusive.

### 8.3 Impact on the design (`docs/DESIGN.md` §4 needs revisiting)

- **A reflection-based `INullabilityProvider` chain alone cannot recover any
  NRT information for code Oxygene itself wrote.**
  `RoslynStyleAttributeProvider` will always return "Unknown" for
  Oxygene-built assemblies (it's only useful for C#-written dependency
  assemblies).
- For this tool's primary use case (Inertia.js Page Props/controllers
  themselves being written in Oxygene, see §6), the conclusion is that
  **source-level detection is required if NRT information is needed at
  all**. This is exactly where the official
  `RemObjects.Elements.Code.Oxygene.Tokenizer` found in §7 (Task 2.5)
  becomes directly useful: a lightweight scan that picks up `nullable`/
  `not nullable` tokens from source needs to be adopted as the highest
  priority, essentially as the only practically viable implementation for
  the `INullabilityProvider` chain (since the reflection-based alternative
  simply doesn't work for Oxygene code within the same assembly).
- The design in `docs/DESIGN.md` §4.2/§4.3 (safe side vs. usefulness side,
  selectable via `--nrt-unknown-policy`) still holds as-is, but it should be
  noted explicitly that the "Unknown" case is not a "rare exception" — via
  the reflection path it's close to being the constantly-occurring default
  state.
- Whichever session next touches DESIGN.md should update §4 based on this
  section's results, making the "token-scan approach" the primary axis of
  the initial `INullabilityProvider` implementation.
