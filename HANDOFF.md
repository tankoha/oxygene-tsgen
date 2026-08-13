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
   researching existing libraries). **Resolved 2026-08-02, see §10: yes, it
   works** — but see §10 for an EBuild/NuGet packaging gap that must be
   worked around.
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
`Inertia.Render(componentName, data)` (targeting the **InertiaNetCore**
adapter — decided 2026-08-01, see §6.4; InertiaCore's development has
stalled and InertiaNetCore is one of the few forks still actively
maintained) as the Props type for the corresponding frontend page
component.

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

- ~~Selecting which ASP.NET Core Inertia adapter to adopt~~ **Decided:
  InertiaNetCore** (2026-08-01, see §6.4).
- Confirming how the chosen adapter types the `data` argument of
  `Inertia.Render(componentName, data)` (is it an `object` parameter, does
  it use generics?).
- Technical verification of how to detect `Inertia.Render` calls from inside
  controller method bodies (will Roslyn-style expression-tree analysis be
  needed, or is IL analysis sufficient?).
- ~~The shape of the generated Props type... The target framework needs to
  be settled.~~ **Decided: React** (2026-08-01, see §6.4) — generated Props
  types are `interface Props { ... }`-style, not a Vue `defineProps<...>()`
  or Svelte-oriented shape.

### 6.4 Open questions

- ~~Selection of the adapter~~ **Decided 2026-08-01: InertiaNetCore.**
  Rationale (from the user): InertiaCore's development has stalled, and
  InertiaNetCore is one of the few forks still seeing active development.
- ~~Frontend framework selection~~ **Decided 2026-08-01: React.** Rationale
  (from the user): Japan's Digital Agency (デジタル庁) publishes publicly
  available reference snippets/components in React.
- Whether to replace the existing §8 (generic API integration) with an
  Inertia-oriented version, or keep both as coexisting modes, needs a
  decision (from an over-engineering-avoidance standpoint, unifying around
  Inertia for now is the simpler choice for the MVP).

---

## 7. Task 2.5 results: investigating LSP/AST-dump functionality bundled with the SDK (Windows hands-on, 2026-08-01)

Environment: RemObjects Elements 13.0.0.3101 (develop),
`C:\Program Files (x86)\RemObjects Software\Elements\`

### 7.1 Investigation method

Rather than building a lexer from scratch, looked for whether the IDE's
own completion feature already exposes something usable for this —
it has to be getting token/syntax information from somewhere. Found it by
casually looking through the Elements SDK's public API surface.

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

---

## 9. RemObjects license/EULA confirmation (vendor reply, 2026-08-01)

Emailed RemObjects to confirm the Trial edition's license position on
casually using the Elements SDK's public API surface (§7) as a
dependency. Reply received same day (2026-08-01).

### 9.1 Questions and answers

1. **Does casually looking through the Elements SDK's public types (as
   done in §7) constitute "reverse engineering" under the Trial edition's
   EULA?**
   → No ("i don't believe so").
2. **Is it permitted to reference and call the public `Tokenizer` class
   as a runtime dependency, without redistributing the SDK DLLs
   themselves?**
   → Yes ("Without redistributing these yourself, sure.").
3. **Is it OK to keep the tool's source code publicly available?**
   → Yes, explicitly welcomed ("Certainly. In fact i'd love to see it!").
4. **Is it OK to publish built binaries, given they were built with the
   Trial edition?**
   → **No.** At least a Personal or Academic license is required "to
   distribute anything." This confirms and formalizes the constraint
   already tracked as a standing rule for this repo (never commit/publish
   build output built with the Trial edition).

**Scope note:** this confirms only the specific, narrow thing that was
asked — casually inspecting public API surface via reflection, and
depending on a public class at runtime. It does not extend to
decompilation, disassembly, or anything not explicitly asked about above;
don't read it more broadly than that.

### 9.2 New, unconfirmed constraint surfaced by the reply

The same answer to question 4 also stated a Personal or Academic license
is needed "to use the product longer than 3 days" — worded as a condition
separate from the distribution restriction above. This reads as a
possible hard usage cap on the Trial edition itself (independent of
whether anything is ever distributed), but the exact meaning is
unconfirmed:

- 3 calendar days from install (2026-08-01)?
- 3 cumulative days of actual use?
- 3 evaluation "sessions"?

**This is not yet resolved.** Given Phase 2 (implementation) has not
started and will require sustained hands-on use of Elements/EBuild, this
should be clarified with RemObjects (or a Personal/Academic license
should be budgeted for) before relying on extended Trial use through
Phase 2. Follow up before starting item 3 in §4 (MVP implementation) if
the 3-day window is at risk of expiring.

**Update (2026-08-02): follow-up sent, awaiting reply.** Emailed Marc
directly (same contact/thread as the original §9.1 exchange) asking him
to confirm whether "3 days" was a typo for "30 days" — the user had
independently expected a 30-day trial and wanted that checked before
trusting the 3-day reading. Not yet confirmed either way as of this
writing; by the time Phase 2 had already reached §16 (well past the
"before item 3" trigger point above) without a reply, so in practice
Trial use continued without waiting on this answer. Update this section
once Marc replies — if it *is* 30 days, the urgency behind issue-tracker
item #19 (`reports/2026-08-02-issue-tracker.csv`) drops substantially.

**Resolved 2026-08-07: confirmed a typo, actual window is 30 days.**
RemObjects Support replied to the 2026-08-02 follow-up: "Trial edition
is for no longer than '3 days.' I was initially under the impression
that the trial period was actually 30 days. [...] That was a typo,
sorry, yes. it's 30 days." This closes the open question — the Trial
edition's usage window is 30 days from install (2026-08-01), not 3.
Issue-tracker item #19 (`reports/2026-08-02-issue-tracker.csv`) is
closed accordingly. `CLAUDE.md`'s license-constraints section updated to
reflect this.

### 9.3 Impact on §11 item 4 (Distribution/packaging approach)

The "Distribution/packaging approach" open question must now be decided
jointly with licensing status, not on technical merits alone: standalone
binary distribution (or any built-artifact distribution — npm-bundled
binary, dotnet tool package, etc.) is blocked until at least a Personal or
Academic license is obtained, regardless of which packaging method is
chosen. Source-only distribution remains unaffected.

### 9.4 New investigative lead: possible NRT info outside standard reflection (unconfirmed)

In the same reply, responding to being told that Echoes doesn't emit
`NullableAttribute`/`NullableContextAttribute` (§8), the RemObjects
contact added: "Ah yes, that info would be in the metadata.fx slice of
the assembly, probably."

This hints that NRT information may live somewhere other than the
standard ECMA-335 custom-attribute tables checked in §8 (via
`CustomAttributeData`) — possibly an Elements-specific metadata
region/resource ("metadata.fx"). The hedge ("probably") suggests the
contact wasn't fully certain either, and the term hasn't been independently
verified. Not yet investigated.

**If confirmed, this could mean NRT info is recoverable directly**,
without the Tokenizer-based source-level scan adopted in §7/§8.3 — which
would simplify the `INullabilityProvider` design considerably. **Do not
treat §8.3's "Tokenizer is the only practically viable implementation"
conclusion as final until this is checked.** Two ways to follow up:

- Hands-on: inspect the compiled assembly's resources/custom metadata
  sections for something matching "metadata.fx" and check whether it's
  readable via a documented Elements API (not just standard
  `System.Reflection`).
- Ask RemObjects directly what "metadata.fx" refers to, and whether/how
  it's readable from outside the compiler itself.

---

## 10. Task 2 results: verifying `MetadataLoadContext` usability from Oxygene/Echoes (Windows hands-on, 2026-08-02)

**Conclusion (§4 item 2 resolved): `System.Reflection.MetadataLoadContext`
is usable from Oxygene/Echoes code**, confirming that metadata-only
assembly loading (the premise behind the whole design — "read only
metadata from the target assembly without executing it") is technically
viable as the implementation strategy for Stage 1 (Loader). A real,
separate packaging gap was found along the way (see §10.2) that needs to
be tracked before relying on NuGet runtime dependencies in Echoes/.NETCore
executables generally, not just for this one package.

### 10.1 Verification method

1. Built a minimal Oxygene class library (`TargetLib`, `.NETStandard` /
   `Mode=Echoes`) with one class exposing two properties and a method, to
   act as the "target assembly" to be loaded as metadata only.
2. Built a separate Oxygene console app (`Probe`, `TargetFramework=.NETCore`
   / `Mode=Echoes`, `OutputType=Exe`) referencing the
   `System.Reflection.MetadataLoadContext` NuGet package via a
   `<NuGetReference Include="System.Reflection.MetadataLoadContext:8.0.0" />`
   item (syntax confirmed from the official ASP.NET Core/React Water
   project template, which is the only bundled sample using
   `NuGetReference`).
3. `Probe`'s `Main` builds a `PathAssemblyResolver` from the runtime
   directory's DLLs (`RuntimeEnvironment.GetRuntimeDirectory()`) plus the
   target assembly's path, opens a `MetadataLoadContext` in a `using`
   block, calls `LoadFromAssemblyPath` on `TargetLib.dll`, and enumerates
   `GetTypes()` / `GetMembers()` to confirm the metadata is readable.
4. Both projects were built with `EBuild.exe /Configuration:Release` and
   the resulting `Probe.exe` was run directly.

### 10.2 Result and a packaging gap found along the way

- The code **compiled without issue** — Oxygene has no trouble calling
  into this .NET BCL-adjacent API surface (constructing
  `PathAssemblyResolver`/`MetadataLoadContext`, generic `List<String>`,
  `using` blocks, etc. all worked as expected).
- **First run failed** with
  `System.IO.FileNotFoundException: Could not load file or assembly
  'System.Reflection.MetadataLoadContext, ...'`, even though the DLL was
  physically present in the output directory after being copied there
  manually. Root cause: EBuild's `NuGetReference` resolution silently
  upgraded the requested package version (`8.0.0`) to `10.0.10` (matching
  the installed .NET 10 SDK/runtime — the machine's installed shared
  runtime is `Microsoft.NETCore.App 10.0.9`), but the generated
  `Probe.deps.json` only recorded the package in the `dependencies` list
  for the target — it **omitted the `"runtime"` asset entry** that tells
  the .NET host which DLL file backs that dependency. Without that entry,
  the CLR's trusted-platform-assembly list built from `deps.json` doesn't
  include the file, so it isn't found even when sitting right next to the
  `.exe`.
- Confirmed as the actual root cause by manually patching
  `Probe.deps.json` to add the missing
  `"runtime": { "System.Reflection.MetadataLoadContext.dll": { ... } }`
  entry under the package's target block — after that, `Probe.exe` ran
  successfully:
  ```
  Loaded assembly: TargetLib, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null
  Type: TargetLib.Sample
    Member: Method get_Name
    Member: Method set_Name
    Member: Method get_Age
    Member: Method set_Age
    Member: Method Greet
    Member: Constructor .ctor
    Member: Property Name
    Member: Property Age
  MetadataLoadContext probe succeeded.
  ```
- **New open item (not yet investigated further): EBuild's `NuGetReference`
  packaging for `Mode=Echoes` / `TargetFramework=.NETCore` executables
  appears not to reliably populate `deps.json`'s runtime-asset entries for
  NuGet-sourced dependencies.** This is a build-tooling risk distinct from
  the original MetadataLoadContext question: it would affect *any* NuGet
  package this tool ends up depending on at runtime (not just this one),
  and needs a real fix (or at least a documented workaround — e.g. a
  post-build `deps.json` patch step, or pinning to a package version that
  doesn't trigger the auto-upgrade path) before Phase 2's CLI skeleton
  leans on NuGet dependencies for anything executed at runtime. Whether
  this reproduces with other packages, other target framework monikers, or
  only with packages EBuild "upgrades" to a newer version than requested,
  is unconfirmed — worth a quick recheck early in Phase 2 if/when the CLI
  skeleton takes on its first real NuGet dependency.

### 10.3 Artifacts

The `TargetLib`/`Probe` test projects were built under this session's
temp scratchpad directory, not under this repository — they were a
disposable hands-on probe, not a repo fixture, and will not persist across
sessions. If a reproducible regression check for this finding is wanted
later, recreate it as a small fixture under `tests/fixtures/` per §4 item
4 rather than assuming these files still exist.

### 10.4 Impact on the design

- `docs/DESIGN.md` §11 item 2 (the open question this task answered) can
  be marked resolved: metadata-only loading via `MetadataLoadContext` is
  the confirmed implementation path for Stage 1 (Loader), no ECMA-335
  from-scratch parser or alternative library is needed for this part of
  the design.
- The NuGet/`deps.json` packaging gap in §10.2 is a new risk that
  `docs/DESIGN.md` did not previously anticipate (the design assumed
  standard .NET tooling behavior for dependency deployment). It doesn't
  block starting §4 item 3 (CLI skeleton), but should be kept in mind once
  the skeleton takes on any runtime NuGet dependency — verify the built
  output actually runs, don't assume a successful `EBuild` compile implies
  a correctly deployable output.

---

## 11. Phase 2 kickoff: MVP scope decisions (2026-08-02)

Before writing `src/` code for §4 item 3, the following scope calls were
made (user-confirmed where flagged as a real fork; the rest are
implementation-detail defaults, documented here rather than silently
decided). A full write-up of what was actually built follows in §12.

- **NRT in the MVP uses the Tokenizer-based source scan from day one**,
  not the reflection-stub-only path `docs/DESIGN.md` §10.1 originally
  described. User-confirmed: this properly follows through on §8.3's
  conclusion instead of shipping an MVP where nullability is always
  `Unknown` for every Oxygene-authored type. Consequence: the CLI needs a
  new `--source <dir>` input beyond the `--assembly`/`--out` shape
  `docs/DESIGN.md` §10.1 originally sketched.
- **NRT scanner scope: properties and fields only for MVP.** Method
  parameter/return-value nullability (also covered by the §8 hands-on
  verification) is deferred — it doesn't affect the Inertia Page Props
  shape (§6), which is what actually gets serialized.
- **Output mode: single-file `.d.ts` only for MVP** (one file with nested
  `declare namespace` blocks matching .NET namespaces). The split-file /
  ES-module layout `docs/DESIGN.md` §7.3 also describes is deferred.
- **Type mapping: a hard-coded primitive/enum mapping function stands in
  for Stage 3 in the MVP**, not the full pluggable `ITypeMappingRule`
  chain — matches `docs/DESIGN.md` §10.2 already placing the plugin
  mechanism near the end of the post-MVP list.
- **Enum strategy: both numeric and string-literal-union are implemented**
  behind a `--enum-style` flag (cheap to do since it's a small branch in
  the emitter, so no reason to cut it down to just one from §10.1's
  "selectable via configuration" wording).
- These decisions keep §4 item 3 (this task) scoped to: Stage 1 Loader
  (reflection via `MetadataLoadContext`, per §10) + a
  properties/fields-only Tokenizer NRT scan + a lightweight Stage 2 IR +
  Stage 4 single-file `DtsEmitter`. Cycle detection, generics, split-file
  output, the plugin chain, and method-level NRT all remain post-MVP per
  `docs/DESIGN.md` §10.2.

---

## 12. Task 3 results: MVP implementation (`src/Tsgen`), Windows hands-on, 2026-08-02

**§4 item 3 is done.** `src/Tsgen` is a working CLI
(`tsgen generate --assembly <dll> --source <dir> --out <dir>`) that loads
an Oxygene-built assembly via `MetadataLoadContext` (§10), scans its
source for `nullable`/`not nullable` via a real Oxygene tokenizer, builds
a lightweight IR, and emits a single-file `.d.ts`. Verified end-to-end
against `tests/fixtures/SampleModel` (see §12.5).

### 12.1 Project layout

```
src/Tsgen/Tsgen.elements       -- Exe, Mode=Echoes, TargetFramework=.NETCore
src/Tsgen/Loading/              -- Stage 1: RawModel.pas, AssemblyLoader.pas
src/Tsgen/Nrt/                  -- NullabilityScanner.pas (Tokenizer-based scan)
src/Tsgen/Ir/                   -- Stage 2: IrModel.pas, TypeMapper.pas, IrBuilder.pas
src/Tsgen/Emit/                 -- Stage 4: DtsEmitter.pas
src/Tsgen/Cli/Program.pas       -- argument parsing + pipeline wiring
tools/dev-build.ps1             -- build + deps.json workaround, see §12.3
tests/fixtures/SampleModel/     -- hands-on verification fixture, see §12.5
```

Single project for the MVP rather than splitting a library out from the
CLI — not enough separate consumers yet to justify it; revisit if/when a
second entry point (e.g. an MSBuild task or a watch-mode host) shows up.

### 12.2 Finding a usable tokenizer entry point

`HANDOFF.md` §7 identified `RemObjects.Elements.Code.Oxygene.Tokenizer`
(constructor takes a `TokenStream`) as the official lexer, but its public
surface turned out to be a raw incremental state machine (`Next()`,
`CurrTokenID`, `Row`/`Col`, etc.) with no simple "tokenize this whole
string" entry point — matching §7.2's warning that "a lightweight parser
still needs to be layered on top." Reverse-engineering it via reflection
(`ReflectionOnlyLoadFrom` + manually preloading its dependency chain --
`RemObjects.Elements.dll`, `RemObjects.Elements.Code.dll` -- to work
around `ReflectionOnlyAssemblyResolve` not being usable from a script)
surfaced a friendlier alternative instead:

- **`RemObjects.Elements.Oxygene.SimpleTokenizer`** — a public static
  class with `Parse(text: String): Void` and `Items: List<TokenValue>`
  (`TokenValue` = `{ Token: Int32, StartPos: Int32, Length: Int32 }`).
  **Quirk found by hands-on probing (not documented anywhere found):**
  `Parse` only ever returns the *first* token of whatever string it's
  given -- calling it repeatedly on the same string does not advance.
  The scanner therefore calls `Parse` on a shrinking substring in a loop,
  re-deriving the absolute offset each time. This works, but a lone
  trailing `.` with nothing after it (e.g. the final `end.` of a unit
  with no trailing newline) makes some internal loop inside `Parse` spin
  and the process dies with "Out of memory." -- `NullabilityScanner`
  guards against this by checking `remaining.Trim() = '.'` (and
  `Length = 0`) *before* calling `Parse`, not after. Any future rework of
  this scanner should keep that guard or something equivalent.
- **Token ID constants** live as public static `Int32` fields on
  `RemObjects.Elements.Code.Oxygene.Token` (an abstract static-only
  class, not an enum), e.g. `TI_class=208`, `TI_nullable=250`,
  `TI_not=249`, `TI_property=259`, `TI_begin=205`, `TI_end=219`,
  `T_Identifier=100`, `TINT_WhiteSpace=69`, `T_Colon=104`,
  `T_SemiColon=110`, `T_OpenRound=105`, `T_CloseRound=106`, `T_Dot=103`.
  Confirmed correct by cross-checking against `SimpleTokenizer`'s output
  for a real snippet (see the sample dump in §12.5). The full field list
  (277 entries) was not transcribed here — re-derive with
  `ReflectionOnlyLoadFrom` + `GetFields(Public, Static)` on
  `RemObjects.Elements.Oxygene.dll`'s `Token` class if more are needed
  later (e.g. for method-level NRT, which will need `TI_method`,
  parameter-list tokens, etc. -- already partly scoped out in §11).

### 12.3 The `deps.json` gap recurs for local `Reference` items too, not just NuGet

§10.2 found this for a `NuGetReference`; it also reproduces identically
for a plain `<Reference Include="..."><HintPath>...</HintPath></Reference>`
item (used here for `RemObjects.Elements(.Code/.Oxygene).dll`, per the
license posture in `CLAUDE.md` -- `Private=False`, i.e. explicitly not
copied into our own output). So this is a general EBuild gap for
`Mode=Echoes` / `TargetFramework=.NETCore` **executables** with any
reference beyond the base framework, not something specific to NuGet.

**Workaround, formalized as `tools/dev-build.ps1`:** runs `EBuild.exe`,
copies the four extra DLLs (`System.Reflection.MetadataLoadContext.dll`
from EBuild's NuGet package cache, plus the three `RemObjects.Elements*`
DLLs from the Elements install) into `Bin/Release`, then patches
`tsgen.deps.json` (via `ConvertFrom-Json`/`ConvertTo-Json`) to add the
missing `"runtime"` asset entries. Re-run this script after every build;
a plain `EBuild.exe` build alone will compile fine and then fail at
launch with `FileNotFoundException`, same as §10.2. The script hardcodes
the current Elements version (`13.0.0.3101`) and assumes the `.NET 10`
SDK is what's installed locally -- update
`$RemObjectsElementsVersion` in the script if the local install changes.
This is a dev-loop convenience script, not a fix for the underlying
EBuild bug (still unreported to RemObjects, still unconfirmed whether it
reproduces on other machines/SDKs).

### 12.4 Other gotchas hit while writing the Oxygene source

- **`nullable`, `property`, and `namespace` are reserved words** and
  cannot be used as your own identifiers (enum members, field names) even
  though they're exactly the words `NullabilityScanner` needs to detect
  in *other* code. Renamed: `RawMemberKind.Property` →
  `.PropertyMember`; `NullabilityKind.Nullable`/`.NotNullable` →
  `.IsNullable`/`.IsNotNullable`; `RawType.Namespace`/`IrTypeLite.Namespace`
  → `.NamespaceName`. Reading an *external* member already named
  `Namespace` (e.g. `System.Type.Namespace` from reflection) compiles
  fine -- the restriction is only on declaring your own identifier with
  the bare reserved word, not on member access.
- **Oxygene's `case` statement does not appear to support string
  subjects** in the way C#'s `switch` does (only tried this for CLI flag
  parsing and enum-string mapping; did not verify against official docs).
  Used `if`/`else if` chains for anything switching on a `String` instead
  of risking it; `case` on `Int32` token IDs (an ordinal type) works
  fine and is used throughout the scanner.
- **`not nullable` fields/properties must be initialized inline**,
  confirmed again here (already known from §8.1): `property Id: not
  nullable String read write := '';` -- the `:= <default>` goes *after*
  `read write`, not before (`tests/fixtures/SampleModel/SampleModel.pas`).

### 12.5 End-to-end verification

Fixture: `tests/fixtures/SampleModel/SampleModel.pas` -- an enum
(`Status`) and a class (`User`) with one `not nullable` property, one
`nullable` property, and two properties with no NRT annotation at all
(to exercise `--nrt-unknown-policy`).

Command (after `tools/dev-build.ps1`):
```
tsgen generate --assembly tests/fixtures/SampleModel/Bin/Release/SampleModel.dll \
               --source tests/fixtures/SampleModel \
               --out tests/fixtures/SampleModel/dist
```

Output (`tests/fixtures/SampleModel/dist/index.d.ts`, default
`--enum-style numeric --nrt-unknown-policy nullable`):
```typescript
declare namespace SampleModel {
  export enum Status {
    Active = 0,
    Inactive = 1,
    Pending = 2,
  }
  export interface User {
    Id: string;
    DisplayName: string | null;
    Age: number | null;
    IsAdmin: boolean | null;
  }
}
```
`Id` (explicit `not nullable`) has no `| null`; `DisplayName` (explicit
`nullable`) does; `Age`/`IsAdmin` (no annotation -> `Unknown`) fall back
to the `--nrt-unknown-policy` default (`nullable`). Re-running with
`--enum-style union --nrt-unknown-policy non-null` correctly flipped the
enum to a string-literal union and dropped `| null` from `Age`/`IsAdmin`
only (not from `DisplayName`) -- confirms the policy only applies to
genuinely `Unknown` members, not to explicitly-annotated ones.

### 12.6 Known limitations / not done

- **NRT scanner is a heuristic, not a real parser.** It tracks
  `class`/`record`/`interface`/`begin`/`try`/`case` nesting with a single
  depth counter plus a paren-depth counter to exclude method parameter
  lists (§11 already scoped out method-level NRT) -- not validated
  against nested types, multiple types under one `type` section, or
  properties with indexer-style parameter lists. Harden with more
  `tests/fixtures/` cases before relying on it for a real, larger
  Oxygene/Inertia codebase.
- Single-file `.d.ts` output only, hardcoded primitive/enum type mapping
  in place of Stage 3's pluggable chain, no cycle detection, no generics
  -- all per the §11 scope decisions and `docs/DESIGN.md` §10.2's
  existing post-MVP ordering.
- `tools/dev-build.ps1`'s `deps.json` patch is a workaround, not a fix;
  if this project ever needs a real packaged/distributable build (blocked
  anyway on the Trial license per §9.3), this gap needs an actual
  resolution first.
- No automated test runner wired up yet -- `tests/fixtures/SampleModel`
  was verified by hand this session. §4 item 4 (snapshot-comparison test
  infrastructure) is still open.

---

## 13. Post-review fixes (Fable5 design review, same session, 2026-08-02)

A design-level review (run as a Fable5 agent, prompted to critique §11's
scope decisions and the §12 implementation) flagged several issues.
User decided to fix the high-severity ones immediately rather than carry
them forward. Full review text is not reproduced here; this section
records what changed as a result.

- **IR reshape (the review's main structural objection).**
  `IrMemberLite` no longer stores a pre-mapped `TsType: String` or a
  pre-resolved `IsNullable: Boolean` — it now stores raw `ClrTypeName:
  String` and the tri-state `Nullability: NullabilityKind`. `IrBuilder`
  (Stage 2) no longer calls `TypeMapper` or applies
  `--nrt-unknown-policy` — both moved into `DtsEmitter` (Stage 4). Why:
  the old shape quietly folded Stage 3 (type mapping) into Stage 2,
  re-creating the "Loader builds the TS AST directly" alternative
  `docs/DESIGN.md` §1.2 explicitly rejected, and collapsed the
  "explicitly annotated vs. Unknown+policy" distinction that
  `docs/DESIGN.md` §4.3's `mark-unknown` policy needs. `IrBuilder.Build`
  and `DtsEmitter.Emit` signatures changed accordingly (see
  `src/Tsgen/Ir/IrBuilder.pas`, `src/Tsgen/Emit/DtsEmitter.pas`).
- **`NullabilityScanner` token IDs now reference
  `RemObjects.Elements.Code.Oxygene.Token`'s public static fields
  directly** (`Token.TI_class`, `Token.TI_nullable`, etc.) instead of
  hardcoded local magic numbers, since Elements is a weekly-release
  product (§3) and these are compiler-internal ordinals.
- **Fixed a real correctness bug**: multi-identifier field declarations
  (`FirstName, LastName: nullable String;`) previously left every name
  except the one immediately before the colon as silently `Unknown`.
  `tests/fixtures/SampleModel/SampleModel.pas` now has such a
  declaration as a regression case; both names correctly come back
  `nullable` after the fix.
- **Fixed an inaccurate comment** in `NullabilityScanner.pas` that
  claimed nested types' "innermost type wins" — the code actually does
  the opposite (outer type wins, since `currentTypeName` is only
  assigned once). Comment corrected; behavior unchanged (still a known
  limitation, §12.6).
- **`TypeMapper`'s fallback changed from `'any'` to `'unknown'`**,
  matching `docs/DESIGN.md` §2.4's specified policy for unmapped types
  (the previous `'any'` fallback silently disabled type-checking exactly
  where the tool's value proposition is type safety). `DtsEmitter` now
  also prints a warning naming the unmapped CLR type and member when
  this fallback triggers.
- **Two new warnings for previously-silent failure modes**: `Program.pas`
  now warns when `--source` is omitted (all members will fall back to
  the unknown-policy default with zero NRT info), and `AssemblyLoader`
  now counts and warns about skipped non-public/nested/generic/
  unsupported-kind types instead of dropping them with no trace.
- **`.gitignore` hardened**: `bin/`/`obj/` → `[Bb]in/`/`[Oo]bj/` (Elements
  names the folder `Bin` with a capital B; the lowercase-only pattern
  only worked by accident of Windows' case-insensitive filesystem), plus
  explicit `*.deps.json`/`*.runtimeconfig*.json` patterns as extra
  insurance against ever committing build output.
- **`IsTypeOpen`'s lookback cap raised from 8 to 64 tokens** (an
  arbitrarily small cap that a long modifier chain before `class`/
  `record`/`interface` could have exceeded).
- Re-ran `tools/dev-build.ps1` and the full `tests/fixtures/SampleModel`
  end-to-end check (default flags, and `--enum-style union
  --nrt-unknown-policy non-null`) after all of the above — output
  unchanged except for the new `FirstName`/`LastName` regression case,
  confirming no regressions from the reshape.

**Deliberately NOT done this round** (review flagged these too, but
they're bigger or lower-urgency asks — left for a future session, in the
order the review suggested):
1. Checking the `metadata.fx` lead from §9.4 (could obsolete the whole
   Tokenizer-scanner approach if NRT turns out to be recoverable from
   metadata directly — cheap to check, should happen before investing
   more in scanner hardening).
2. Committing `tests/fixtures/SampleModel/dist/index.d.ts` as a locked
   snapshot-test baseline with an automated comparison script (§4 item
   4) — the review suggested doing this *before* any further IR changes.
   That didn't happen before §13's reshape; it was instead verified by
   manual output comparison, which happened to work this time. Treat
   that as "got away with it once," not as the ordering advice having
   expired — snapshot infra should be a hard precondition before the
   next structural change (item 3 below is exactly that kind of change).
3. Reworking `NullabilityScanner.Tokenize` off `SimpleTokenizer`'s
   shrinking-substring loop onto the real incremental
   `RemObjects.Elements.Code.Oxygene.Tokenizer`/`TokenStream` (§12.2) —
   would remove the OOM guard, the safety counter, and O(n²) string
   copying, but re-opens the same low-level-API investigation that was
   deliberately avoided in §12.2; sizeable enough to deserve its own
   session rather than being folded into a fix-up pass.
4. Adding the `INullabilityProvider` chain abstraction and the third
   (`mark-unknown`) `--nrt-unknown-policy` value — the IR reshape above
   makes both easier now (the tri-state `Nullability` is preserved all
   the way to the emitter), but actually wiring them up is new scope,
   not a fix to what was already built.
5. The `docs/DESIGN.md` §4 rewrite (tracked since 2026-08-01, still
   open) and syncing §10.1/§11's now-stale MVP description — documentation
   debt, not code, and the review noted it now spans three places in the
   design doc.
6. Resolving the §9.2 Trial-license 3-day-cap question — not a code
   task; needs a vendor follow-up or a license purchase decision, and the
   review flagged it as increasingly urgent given how much sustained
   EBuild use Phase 2 is now doing.
7. ~~Reporting the `deps.json` runtime-asset gap (§10.2/§12.3) to
   RemObjects.~~ **Done 2026-08-02, see §17.** This was on the original
   review's "shouldn't wait" list alongside the `.gitignore` fix, but
   fell through the cracks of this section on the first pass -- a
   follow-up verification review caught the omission. RemObjects has
   already been responsive by email once (§9), and Elements ships
   weekly, so a real upstream fix is plausibly obtainable.

---

## 14. §9.4 follow-up resolved: `metadata.fx` does not carry NRT info (Windows hands-on, 2026-08-02)

**Conclusion (§13 deferred item 1 / §9.4 resolved): the `metadata.fx`
manifest resource is real, but it does not expose nullable/not-nullable
information.** §8.3's conclusion stands unchanged: the Tokenizer-based
source scan remains the only practically viable `INullabilityProvider`
implementation. This does not change any code — it closes an open
question and removes a reason to hold off on further scanner work
(§13 deferred item 3).

### 14.1 Verification method

1. Installed the .NET 10 SDK on this machine mid-session (previously only
   the runtime was present, which blocked `dotnet new`/`dotnet build`).
2. Wrote a disposable console app (not part of `src/Tsgen`, built and run
   from the session scratchpad only, never committed) using the standard,
   documented `System.Reflection.PortableExecutable.PEReader` +
   `System.Reflection.Metadata.MetadataReader` APIs to enumerate
   `ManifestResource` entries in `tests/fixtures/SampleModel/Bin/Release/SampleModel.dll`
   and `src/Tsgen/Bin/Release/tsgen.dll`.
3. Confirmed both assemblies embed exactly one manifest resource named
   **`metadata.fx`** (`Implementation` nil, i.e. stored in the assembly's
   own COR20 resources blob) — matching the RemObjects contact's hedge in
   §9.4 almost exactly. Magic bytes `ROSF` at the start of the resource
   (likely "RemObjects Software Format").
4. Dumped the resource body and manually inspected it: a crude
   printable-string scan plus targeted hex dumps around the known property
   names of `SampleModel.User` (`Id`, `DisplayName`, `Age`, `IsAdmin`,
   `FirstName`, `LastName`).

### 14.2 What's actually in `metadata.fx`

- A large flat list of reference-assembly names (`Echoes`, `mscorlib`,
  `netstandard`, `System.Collections.Concurrent`, ... — reads like the
  full .NET reference-assembly/facade list, not specific to this project).
- A compact per-member symbol index: for each property/field, a record
  containing the bare name, a member-kind tag (properties and fields tag
  differently), and an XML-doc-ID-style signature string (`P:Id`,
  `F:FirstName`, and for methods `M:get_Id-System.String`,
  `M:set_DisplayName-System.String`, etc.). Reads like the backing index
  for the IDE's completion/"find symbol" feature that §7 speculated about
  — a name/kind/signature lookup table, not a full semantic model.
- A small, deduplicated table of canonical type-name strings
  (`System.String`, `System.Int32`, `System.Boolean` — each appears
  exactly once) referenced by the per-member records above.

### 14.3 Why this rules out NRT recovery from `metadata.fx`

Compared byte-for-byte the records for `Id` (`not nullable String`)
against `DisplayName`/`Age`/`IsAdmin` (`nullable` / unannotated String,
Int32, Boolean respectively) — same source file
(`tests/fixtures/SampleModel/SampleModel.pas`) used for the original §8
hands-on verification, so the ground truth for each member's declared
nullability is already known independently:

- Every property record has an **identical byte structure** regardless of
  declared nullability (same tag sequence, only the name string, its
  length, and small sequential index values differ — none of which track
  nullability).
- The canonical type-name table has exactly **one** entry for
  `System.String`, shared by both `Id` (not nullable) and `DisplayName`
  (nullable) — if nullability were encoded as a distinct referenced type
  (e.g. a wrapper type name), there would need to be at least two
  different `String`-related entries. There is only one.
- The two per-usage-site references into that shared `System.String`
  entry (one for `Id`'s get/set, one for `DisplayName`'s get/set) are
  **byte-for-byte identical** to each other, despite one member being
  `not nullable` and the other `nullable`.

This isn't a full reverse-engineering of the `ROSF` binary protocol (that
would be a much larger, lower-value undertaking, and was explicitly out
of scope for this "cheap first step" per §9.4) — but it's a direct,
ground-truth-anchored comparison on the exact property that matters here,
and it comes back negative on all three counts. Good enough to close the
question without further investment.

### 14.4 Impact on the design / task list

- `HANDOFF.md` §9.4's "possible NRT info outside standard reflection"
  lead is resolved: **no**, not in the default `metadata.fx` resource.
  `docs/DESIGN.md` §4 does not need revisiting again — the
  Tokenizer-based-scan conclusion it already documents (from §8.3) is
  correct as-is.
- §13 deferred item 3 (reworking `NullabilityScanner` off
  `SimpleTokenizer` onto the real incremental
  `RemObjects.Elements.Code.Oxygene.Tokenizer`/`TokenStream`) can now
  proceed without this open question hanging over it.
- Side finding, not acted on: this machine only had the .NET runtime
  installed, not the SDK, for everything up through §13 — `dotnet
  build`/`dotnet new`/`dotnet run` were unavailable, only pre-built
  apphosts (like `tsgen.exe` via `EBuild.exe`) could run. The SDK was
  installed mid-session on 2026-08-02 specifically to unblock this
  investigation. Not expected to affect `tools/dev-build.ps1` (still
  EBuild-driven), but worth knowing the SDK is now present if a future
  session wants to reach for plain `dotnet` tooling directly.

---

## 15. §4 item 4 done: snapshot-test infrastructure (Windows hands-on, 2026-08-02)

**§13 deferred item 2 is done.** `tools/run-tests.ps1` builds the CLI and
every fixture under `tests/fixtures/`, runs `tsgen` once per case declared
in that fixture's `cases.json`, and diffs the result against a committed
`expected/*.d.ts` snapshot. This was deliberately done *before* §13
deferred item 3 (reworking the NRT scanner's tokenizer loop), per the
review's original ordering advice, now that §14 has removed the reason to
hold off further.

### 15.1 Layout

```
tests/fixtures/SampleModel/
  SampleModel.pas / .elements   -- unchanged
  cases.json                     -- new: list of {name, args, expected}
  expected/
    default.d.ts                 -- CLI defaults (numeric enum, nullable-unknown)
    union-nonnull.d.ts           -- --enum-style union --nrt-unknown-policy non-null
tools/run-tests.ps1              -- new: the runner (see below)
```

`cases.json` is what makes the runner fixture-agnostic — adding a new
fixture later means adding its `.pas`/`.elements` plus a `cases.json`,
not touching `run-tests.ps1`. A fixture with no `cases.json` (or no
`.elements` file) is skipped with a warning rather than failing the run,
so partially-set-up fixtures don't block the rest of the suite.

The old, previously-committed `tests/fixtures/SampleModel/dist/index.d.ts`
(from §12.5's manual verification) was removed — it was byte-for-byte
identical to the new `expected/default.d.ts` and is now superseded by the
`expected/` convention.

### 15.2 What the runner does

1. Builds `tsgen.exe` via the existing `tools/dev-build.ps1` (so the
   `deps.json` workaround from §10.2/§12.3 stays in exactly one place).
2. For each fixture directory with both a `.elements` file and a
   `cases.json`: builds the fixture with a plain `EBuild.exe
   /Configuration:Release` call. **No `deps.json` patch needed for
   fixtures** — unlike `tsgen.exe`, fixture DLLs are never executed, only
   loaded as metadata by `tsgen` via `MetadataLoadContext` (§10), so the
   runtime-asset gap that forces the workaround for `tsgen.exe` itself
   doesn't apply here.
3. For each case, runs `tsgen generate --assembly <fixture.dll> --source
   <fixtureDir> --out tests/fixtures/<Fixture>/_actual/<case.name>` with
   that case's `args`, then compares `index.d.ts` against
   `expected/<...>` (both sides newline-normalized before comparing, so a
   future CRLF/LF discrepancy from git config or an editor doesn't cause
   a false failure).
4. `-UpdateSnapshots` switch: regenerates every `expected/*.d.ts` from
   current output instead of comparing — the normal snapshot-test
   workflow for an intentional output change (verify the diff looks
   right with plain `git diff` afterward, same as any other snapshot
   testing setup).
5. Prints a `[PASS]`/`[FAIL]` line per case (with a line-level diff via
   `Compare-Object` on failure) and a summary count; exits non-zero if
   anything failed. `_actual/` is deleted after each fixture's cases run
   (added to `.gitignore`), so a full run leaves the tree clean whether
   it passed or not.

### 15.3 Verification

- Fresh run: both cases (`default`, `union-nonnull`) pass.
- Deliberately corrupted `expected/default.d.ts` (`Active = 0` →
  `Active = 99`) to confirm the failure path: the runner reported
  `[FAIL]` with a correct line-level diff (`expected: Active = 99,` /
  `actual: Active = 0,`) and exited with code 1; the other case still
  correctly reported `[PASS]`. Restored the snapshot and reran clean.
- `-UpdateSnapshots` run against already-matching output produced no
  content diff (confirmed via `git status`), i.e. it's idempotent when
  nothing actually changed.

### 15.4 Impact on the design / task list

- The precondition §13 set for "the next structural change" (deferred
  item 2, done here) is now satisfied. §13 deferred item 3 (reworking
  `NullabilityScanner` off `SimpleTokenizer`) — the next candidate
  structural change — can proceed with a regression safety net in place.
- Only one fixture (`SampleModel`) exists so far, covering enums,
  explicit `nullable`/`not nullable`, and the `Unknown`-policy fallback.
  It does **not** cover nested types, multiple types under one `type`
  section, or indexer-style property parameter lists — the known
  scanner limitations already called out in §12.6. Adding fixtures that
  exercise those cases would make good companion work for §13 deferred
  item 3, since a scanner rework is exactly where those limitations are
  either fixed or newly regression-locked.

---

## 16. §13 deferred item 3 done: NRT scanner moved onto the real tokenizer (Windows hands-on, 2026-08-02)

**`NullabilityScanner.Tokenize` no longer uses `SimpleTokenizer`.** It now
drives the real Oxygene tokenizer through
`RemObjects.Elements.Code.TokenStream`, which removes all three problems
§12.2/§13 flagged: the OOM guard, the safety counter, and the O(n²)
shrinking-substring copying. Verified against the existing snapshot suite
(§15) with no output change, plus a new fixture that locks in the
tokenizer-sensitive behaviour.

Done on Opus 5 rather than Sonnet 5, per `CLAUDE.md`'s model-selection
guidance naming this specific scanner as an Opus-worthy core.

### 16.1 The API, which is better than §12.2 expected

§12.2 assumed this rework meant driving `Tokenizer`'s raw incremental
state machine (`Next()`, `CurrTokenID`, `Row`/`Col`) by hand, and priced
the task accordingly. That turned out not to be necessary:
**`RemObjects.Elements.Code.TokenStream` (in `RemObjects.Elements.dll`,
not `RemObjects.Elements.Code.dll`) extends `ViewableList<Fragment>` and
tokenizes a whole file in one call**, exposing the result as a plain
array. The usable shape is:

```
Languages.Register(new OxygeneLanguage);          // once per process
var stream := new TokenStream(FragmentType.Oxygene, false);
stream.SetText(text);                              // tokenizes; no Load() needed
for i := 0 to stream.Count - 1 do
  ... stream.Items[i] ...                          // Fragment
```

- `RemObjects.Elements.Code.Fragment` has public `Token: Int32`,
  `StartPos: Int32`, `Length: Int32` fields plus `GetString()` and an
  `IsWhitespace` property — i.e. the same information `SimpleTokenizer`'s
  `TokenValue` carried, but produced by the real lexer over the entire
  input at once instead of one token at a time.
- **`FragmentType.Oxygene = 1`** is the enum value for the constructor.
- **The registration step is the non-obvious part.** `TokenStream`'s
  constructor resolves a provider out of the process-global
  `RemObjects.Elements.Languages` registry, and simply referencing
  `RemObjects.Elements.Oxygene.dll` does not populate it — without
  `Languages.Register(new OxygeneLanguage)` first, construction throws
  `System.Exception: Unsupported Language: Oxygene`. `NullabilityScanner`
  guards this behind a `class var` flag since it's a one-time global
  side effect.

Because everything below `Tokenize` still works off the local `ScanToken`
list, this was a change to one method plus a `uses` clause — `ScanFile`,
`IsTypeOpen`, `FindTypeNameBefore` and `ScanMemberDecl` are untouched.
That seam is worth keeping if the tokenizer is ever swapped again.

### 16.2 Behaviours confirmed hands-on before writing any Oxygene

Probed by executing the API from a throwaway console app in the session
scratchpad (same disposable, never-committed approach as §14.1) rather
than guessing and iterating through EBuild round-trips:

- `SetText()` alone populates `Items`/`Count`; `Load()` is not needed.
- **Every stream ends with a zero-length `T_EOF` fragment**, which the
  scanner must skip.
- `Items` is a capacity-sized array, so `Count` — not `Items.Length` —
  bounds the loop.
- Whitespace fragments are not emitted at all by default, but **comment
  fragments are**, carrying `IsWhitespace = true`. The scanner filters on
  `IsWhitespace` and additionally on the explicit
  whitespace/comment/xmldoc token IDs, preserving the previous filter
  exactly.
- **The `"end."`-with-no-trailing-newline input that made
  `SimpleTokenizer.Parse` spin and die with "Out of memory" (§12.2)
  tokenizes cleanly here** (3 fragments: `TI_end`, `T_Dot`, `T_EOF`), so
  the `remaining.Trim() = '.'` guard is gone rather than merely relocated.
- For an `&`-escaped identifier (`&class` used as a member name) the
  tokenizer reports `T_Identifier` with the `&` already stripped, and
  `GetString()`, `GetOriginalString()` and a raw `StartPos`/`Length`
  slice all agree. The scanner uses `GetString()`, which is what the
  reflection side sees as the member name — a small correctness gain the
  old raw-slicing path would not have had.

### 16.3 New fixture: `tests/fixtures/TokenizerEdgeCases`

Added per §15.4's suggestion, and because the existing `SampleModel`
fixture exercises none of what this rework actually changes. It declares
one class whose members are each named for the thing they prove, and the
file **deliberately ends with `end.` and no trailing newline** — the
exact input that used to crash the old scanner.

Two cases are locked in (`cases.json`): CLI defaults, and
`--nrt-unknown-policy non-null`. **The `non-null` case is the one with
discriminating power** — under the default policy an `Unknown` member and
a member that wrongly picked up a leaked `nullable` both render as
`| null`, so a leak would pass unnoticed. Under `non-null`, `Unknown`
renders bare and only genuine annotations keep `| null`, so the snapshot
actually distinguishes the two. Worth remembering when adding future
NRT fixtures: a default-policy-only snapshot can hide exactly the bug
class these fixtures exist to catch.

Confirmed correct by inspection before being committed as a baseline
(not just accepted because it ran): `nullable`/`not nullable` appearing
inside a line comment, a block comment, an XML doc comment, and a string
literal default value all correctly fail to annotate the following
member, while genuine annotations and the multi-identifier declaration
still resolve. The scanner reports exactly 5 annotated members for the
file, matching the 5 genuine annotations.

### 16.4 What this does not fix

The limitations in §12.6 are unchanged — this replaced *how tokens are
produced*, not the heuristic that walks them. Nested types, multiple
types under one `type` section, and indexer-style property parameter
lists are still unhandled, and `ScanFile` is still a depth-counter
heuristic rather than a parser. Those now have a snapshot net under them,
so they're a safer thing to attack next than they were before §15.

---

## 17. Two vendor follow-ups sent to RemObjects (2026-08-02)

Both non-code items §13 flagged as overdue were sent this session, as
separate, independent inquiries rather than bundled into one email —
the `deps.json` bug is an engineering/EBuild issue, while the trial-length
question is a licensing/sales issue, and the two are unlikely to be
triaged by the same person on RemObjects' side. Bundling them under a
"following up on our earlier exchange" framing would also have meant
whoever picked up the generic support inbox had no visibility into that
earlier thread's context, for no benefit.

1. **`deps.json` runtime-asset gap (§10.2/§12.3/§16.1), §13 item 7.**
   Sent as a fresh, standalone bug report to `support@remobjects.com`
   (not a reply to the §9 thread). Covers: repro steps (`NuGetReference`
   silently upgraded to a newer installed version, resulting
   `deps.json` missing the `"runtime"` asset entry under the target
   block), root-cause confirmation (manually patching in the missing
   entry fixes it), the finding that it reproduces identically for a
   plain local `Reference`/`HintPath` too (so it's not NuGet-specific),
   environment details (Elements 13.0.0.3101, .NET 10 SDK/runtime), and
   a note that a `talk.remobjects.com` search turned up related-looking
   but non-matching older threads (18830, 18544, 19464, 27688) so
   RemObjects can judge duplicate-vs-new themselves. Offered to share
   `tools/dev-build.ps1`'s workaround as a regression-test seed if
   useful. No reply yet as of this writing.

2. **§9.2 trial-length question.** The user separately emailed Marc
   directly (continuing the §9.1 thread) asking whether the "3 days"
   figure from the original reply was a typo for "30 days" — the user
   had expected a 30-day trial going in. See §9.2's updated note for the
   current status; not yet confirmed either way. If it turns out to be
   30 days, issue-tracker item #19 (`reports/2026-08-02-issue-tracker.csv`)
   and this file's own repeated "confirm before relying on extended
   Trial use" warnings (§4 task list, §9.3) lose most of their urgency
   — worth revisiting once Marc replies, rather than continuing to
   carry this as a high-severity open item by default.
   **Resolved 2026-08-07: confirmed typo, actual window is 30 days —
   see §9.2's update for the full reply text.** Issue-tracker item #19
   closed.

**Status as of this session's start (2026-08-02, later same day):** both
inboxes were checked before continuing further work — still no reply from
RemObjects on either item. Per the user, the original §9/§17 reply landed
late Friday US time (their CEO answering during overtime), so the plan is
to let the weekend pass without chasing a reply rather than escalating.
Non-code work is otherwise idle on both items; see §18 for what this
session did instead (NRT scanner hardening, code-only, no vendor
dependency).

---

## 18. NRT scanner hardening: indexer properties fixed, multi-type-section verified, nested types scoped out (Windows hands-on, 2026-08-02)

Continuation of the `HANDOFF.md` §12.6/§16.4 known-limitations list
(nested types, multiple types under one `type` section, indexer-style
property parameter lists), now that §15's snapshot-test net makes this
kind of scanner change safe to attempt (per §16.4's own recommendation).
User chose this over the other open-item candidates (vendor follow-up,
`INullabilityProvider` chain/`mark-unknown` policy, next `docs/DESIGN.md`
§10.2 post-MVP item) for this round.

### 18.1 Scope correction found before writing any fix

Before touching the scanner, checked what `AssemblyLoader.pas` and
`DtsEmitter.pas` actually do with nested types, rather than assuming the
scanner's own doc comment (which blamed itself) was the whole story.
**`AssemblyLoader.Load` filters out every `t.IsNested` type before it
ever reaches `RawAssembly`** (`AssemblyLoader.pas:27`, part of the §13
"skipped non-public/nested/generic/unsupported-kind types" warning), and
**`DtsEmitter` has no nested-`interface`-in-`interface` output path at
all** — only namespace-level nesting (`declare namespace { ... }`).
Consequence: fixing `NullabilityScanner`'s nested-type attribution alone
cannot change any generated output, because a nested type's members never
reach the IR or the emitter regardless of what key the scanner attributes
them to. Real nested-type support needs coordinated changes across all
three stages (Loader, IR key format, Emitter), not a scanner-only patch.

> **Correction (§20, 2026-08-02, later same day):** a Fable5 review found
> the paragraph above overlooked a real path to changed output —
> misattribution doesn't just orphan the nested type's own (invisible)
> data, it can silently **overwrite an OUTER, same-named member's**
> dictionary entry, corrupting output that *does* reach the `.d.ts`. Fixed
> in §20; see there before relying on this section's "cannot change any
> generated output" claim.

**User decision (2026-08-02): leave nested types out of scope for this
round.** `NullabilityScanner.pas`'s header comment was updated to record
this (why it's currently moot, not just that it's unsupported) instead of
silently carrying the stale "should be hardened" wording forward. Treat
nested-type support as a separate, future task spanning
`AssemblyLoader.pas` + `IrBuilder.pas`/`IrModel.pas` (nested-type key
format — CLR uses `Outer+Inner` for `Type.FullName`) + `DtsEmitter.pas`
(nested `interface` emission), not something to pick up piecemeal in the
scanner again.

### 18.2 Indexer-style properties: real bug, fixed

`NullabilityScanner.ScanFile`'s `TOK_PROPERTY` branch required the token
immediately after the property name to be `TOK_COLON`
(`property Name: Type ...`). An indexer declaration
(`property Item[aIndex: Int32]: not nullable String read ... write ...;`)
has `TOK_OPENBLOCK` (`[`) there instead, so the whole branch's condition
failed and indexer properties were silently never annotated — always
`Unknown`, regardless of source. `AssemblyLoader` already loads indexer
properties fine via `t.GetProperties(...)` (reflection's
`PropertyInfo.Name` is `"Item"`, ignoring index parameters), so this was
purely a scanner gap, not a Loader one.

Fix: when the token after the property name is `TOK_OPENBLOCK`, skip
forward tracking bracket depth until the matching `TOK_CLOSEBLOCK`, then
continue looking for `TOK_COLON` from there — same shape as the existing
`parenDepth` skip used to exclude method parameter lists, just for `[...]`
instead of `(...)`. `Token.T_OpenBlock`/`Token.T_CloseBlock` are the
correct constants for `[`/`]` — confirmed by tokenizing a throwaway
indexer snippet via `TokenStream` from a disposable PowerShell probe
(`Add-Type -Path` on the three `RemObjects.Elements*.dll`s, then
`Languages.Register(new OxygeneLanguage)` + `TokenStream.SetText`, same
API shape as §16.1) rather than guessing field names — the naming turned
out to be non-obvious (`T_OpenBlock`/`T_CloseBlock` for `[`/`]`, and a
separate, unrelated `T_CloseBracket` field exists for something else
entirely, so guessing "Bracket" would have picked the wrong constant).

### 18.3 Multiple types under one `type` section: verified already correct, no fix needed

Reading `ScanFile` closely: `currentTypeName`/`typeDepth` already reset
unconditionally on any type's closing `end` where `depth = typeDepth`,
regardless of how many type declarations share one `type` section — nothing
in the reset logic is scoped to "the first type only". Confirmed hands-on
with the new fixture below (§18.4) rather than trusting the code-reading
alone: two sibling classes declaring a same-named member with *opposite*
nullability right next to each other in one `type` section, which would
have collided into a single, wrong dictionary entry if any leak existed.
No code change was needed here — this item turned out to already work; it
just hadn't been exercised by a fixture before.

### 18.4 New fixture: `tests/fixtures/MultiTypeAndIndexer`

Two sibling classes (`Alpha`, `Beta`) both under one `type` section, each
declaring a property named `Name` with opposite nullability (`Alpha.Name`
nullable, `Beta.Name` not nullable) — the discriminating case for §18.3.
`Beta` also declares an indexer property (`Item[aIndex: Int32]`, not
nullable, backed by explicit `GetItem`/`SetItem` methods rather than
auto-implemented `read write`, since an indexed property has no single
backing field for the compiler to auto-generate) and an unannotated
`Count: Int32` to keep a genuine-`Unknown` member in the mix. Two cases
locked in (`cases.json`): CLI defaults and `--nrt-unknown-policy
non-null`, per `CLAUDE.md`'s standing guidance to always include a
non-null case alongside default for NRT fixtures.

Verified hands-on before committing as a baseline: ran `tsgen` directly
against the built fixture DLL and inspected the output (not just trusted
`-UpdateSnapshots`) — `Alpha.Name` and `Beta.Name` came back with the
correct, non-colliding nullability, and `Beta.Item` (the indexer) came
back `not nullable` (no `| null`) under *both* policies, which by itself
already distinguishes "detected as not-nullable" from "never detected,
fell back to Unknown" (Unknown would show `| null` under the default
policy) — the non-null case additionally distinguishes `Beta.Item` from
`Beta.Count` (genuinely `Unknown`), consistent with the leak-detection
rationale `CLAUDE.md` already documents for `TokenizerEdgeCases`.
`SampleModel` and `TokenizerEdgeCases` snapshots came back byte-identical
after the scanner change (`git diff` empty for both), confirming no
regression from the `TOK_PROPERTY` branch rewrite.

### 18.5 Verification

- `tools/dev-build.ps1` — clean build, no new warnings.
- `tools/run-tests.ps1 -UpdateSnapshots` then `tools/run-tests.ps1` (plain):
  6/6 cases pass across all three fixtures (`MultiTypeAndIndexer` x2,
  `SampleModel` x2, `TokenizerEdgeCases` x2).
- `git diff` on `SampleModel`/`TokenizerEdgeCases` expected snapshots:
  empty (no regressions).

### 18.6 What this does not fix

- Nested types remain unsupported end-to-end, now understood as a
  three-stage (Loader/IR/Emitter) gap rather than a scanner-only one —
  see §18.1. Not attempted this round per the user's explicit decision.
- `ScanFile` is still a depth-counter heuristic, not a parser; this round
  only extended what member-declaration *shapes* it recognizes
  (indexers), it didn't change the underlying nesting/type-tracking
  model.

---

## 19. Diagnostics component added: `DtsEmitter.Emit`/`AssemblyLoader.Load` are pure again (Windows hands-on, 2026-08-02)

Resolves issue-tracker item #22 (`reports/2026-08-02-issue-tracker.csv`),
flagged during §13's post-review pass and left for "when a Diagnostics
component gets implemented" rather than fixed inline at the time. User
picked this up next, and asked for the full fix (a real Diagnostics
component) rather than a minimal stderr-only patch — the CSV row's own
wording ("将来Diagnosticsコンポーネント実装時に") had left both options
open, so this was confirmed with the user before starting rather than
assumed.

### 19.1 What was actually impure, and why it mattered

`AssemblyLoader.Load` (Stage 1) and `DtsEmitter.Emit` (Stage 4) both
called `writeLn` directly for warnings (skipped-type count; unmapped CLR
type fallback), even though `docs/DESIGN.md`'s pipeline design treats
every stage as a pure data transform so they can be composed/tested in
isolation. Beyond the purity complaint itself, the unmapped-type warning
had a real noise problem: it printed once per *member*, so a single
custom POCO type used across many properties (a realistic shape for the
Inertia Page Props use case, §6) would flood the console with one
near-identical line per occurrence instead of surfacing the underlying
issue once.

### 19.2 What was added

New file `src/Tsgen/Diagnostics/Diagnostics.pas` (`Tsgen.Diagnostics`
namespace, added to `Tsgen.elements`'s `Compile` list first, since
`AssemblyLoader`/`DtsEmitter`/`Program` all now depend on it): a
`DiagnosticSeverity` enum (`Warning` only for now), a `Diagnostic` class
(`Severity` + `Message`), and a `DiagnosticList` collector class with a
single `AddWarning(aMessage)` method and an `Items` property.

- `AssemblyLoader.Load` now takes an `aDiagnostics: DiagnosticList`
  parameter; the skipped-type-count warning goes through
  `aDiagnostics.AddWarning(...)` instead of `writeLn`.
- `DtsEmitter.Emit` now takes the same parameter. The unmapped-type
  warning was restructured to *collect* first: `EmitType` takes two new
  params, a `Dictionary<String, List<String>>` keyed by CLR type name
  (value = list of `"Type.Member"` locations using it) and a
  `List<String>` recording first-seen key order (same "don't rely on
  Dictionary iteration order" rationale the existing `byNamespace`/`order`
  pair in `Emit` already used, kept consistent rather than introduced
  fresh). After all types are emitted, `Emit` walks `unmappedOrder` once
  and adds one diagnostic per unique unmapped type, e.g. `"no type
  mapping for DiagProbe.Widget, emitting \"unknown\" (3 member(s), e.g.
  Holder.A)"`.
- `Program.pas` (the CLI entry point, the only place now allowed to touch
  the console for anything beyond its own progress lines) creates one
  `DiagnosticList`, threads it through `AssemblyLoader.Load` and
  `DtsEmitter.Emit`, and also routes the pre-existing "`--source` not
  given" warning through it (previously its own direct `writeLn`, now
  consistent with the other two). All collected diagnostics are printed
  together, once, at the very end (after the "Wrote ..." line) via
  `Console.Error.WriteLine('Warning: ' + d.Message)` — to **stderr**, not
  stdout, separating warnings from the progress narration. Needed adding
  `System` to `Program.pas`'s `uses` clause for `Console.Error`.

### 19.3 Verification

- `tools/dev-build.ps1`: clean build, no new warnings.
- `tools/run-tests.ps1`: 6/6 cases across all three fixtures still pass,
  `.d.ts` output byte-identical to before (diagnostics don't touch
  generated file content, only where/how warnings are printed).
- Hands-on dedup check with a disposable scratchpad fixture (not
  committed — same throwaway-probe convention as §14.1/§16.2/§18.2): a
  `Widget` class used as the property type of three properties
  (`Holder.A`/`B`/`C`) on an unmapped custom type. Before this change
  that would have printed three near-identical `writeLn` lines mid-run;
  confirmed the new build instead prints exactly **one** line to stderr
  (verified via `2>stderr.txt` redirection, not just visual inspection):
  `Warning: no type mapping for DiagProbe.Widget, emitting "unknown" (3
  member(s), e.g. Holder.A)`.

### 19.4 Impact on the design / task list

- Issue-tracker item #22 is resolved — `AssemblyLoader.Load` and
  `DtsEmitter.Emit` are pure functions again (data + `DiagnosticList` in
  results, no direct I/O), matching `docs/DESIGN.md`'s pipeline-stage
  design intent.
- `DiagnosticSeverity` only has `Warning` today; if a future stage needs
  `Error`/`Info`, the enum and `DiagnosticList` are already the seam to
  extend rather than reaching for `writeLn` again.
- This also nudges the codebase slightly closer to the `IEmitterExtension`
  /diagnostics-adjacent extension points `docs/DESIGN.md` §6 sketches for
  the post-MVP plugin chain, though no plugin mechanism was added here —
  purely an internal refactor of how the existing two stages report
  problems.

---

## 20. Fable5 review of §18/§19 (commits `b9627df`/`ce1be2d`), and the response (Windows hands-on, 2026-08-02)

User asked for an independent Fable5 review of the two commits behind
§18/§19, on two explicit axes: internal consistency of what was done, and
whether the work introduced any *new* inconsistency elsewhere. Review ran
as a background `general-purpose` agent with `model: fable`, in an
isolated worktree, with read-only instructions (no fixes, report only).
Full method: read `CLAUDE.md`, `HANDOFF.md`/`HANDOFF_jp.md` through §19,
the actual diffs (`git show` on both commits) and current file contents,
`docs/DESIGN.md`, and the issue-tracker CSV; traced several claims by
hand rather than only trusting the written record. Did not build/run the
suite (Trial-license usage-cap caution, `CLAUDE.md` "License
constraints") — every finding below was verified by static trace, and,
for finding 1, additionally confirmed hands-on this session (§20.3).

### 20.1 Review outcome

**Question 1 (internal consistency): essentially clean.** EN/JP HANDOFF
prose, `CLAUDE.md`, the CSV, and the actual code all agreed on every
substantive point checked (token constants, the `GetItem`/`SetItem`
rationale, case counts, the dedup message format, `IsTypeOpen` claims,
etc.) — full detail not reproduced here since nothing needed fixing
beyond two wording nits (§20.4).

**Question 2 (new inconsistencies): 3 findings**, most severe first:

1. **The §18.1 "scanner-only fix cannot change output" rationale had a
   real hole.** True that a nested type's *own* data never reaches the
   emitter (Loader filters `IsNested`, Emitter has no nested-`interface`
   output) — but misattribution doesn't just orphan that invisible data.
   `NullabilityScanner`'s `TOK_PROPERTY` branch was missing the `(depth =
   typeDepth)` guard the field branches already had, so a nested type's
   annotated property was still attributed to the *outer* type
   (`currentTypeName` stays the outer type's name inside a nested body),
   and `ScanMemberDecl`'s unconditional `aResult[key] := kind` write means
   whichever declaration the scanner walks **last** — outer or nested —
   wins the shared dictionary key. A nested type's annotation can
   therefore silently overwrite an outer, same-named member's nullability
   in output that *does* reach the `.d.ts`. Present in five places making
   the same overstated claim: `HANDOFF.md`/`HANDOFF_jp.md` §18.1, the
   `NullabilityScanner.pas` header comment, `CLAUDE.md`, and CSV row 31.
   The *decision* to leave full nested-type support out of scope was
   still fine — the *justification* given for why the scanner-only gap
   was harmless was not. Fixed, see §20.3.
2. **`docs/DESIGN.md` §4 (and `DESIGN_jp.md`) still listed indexer-style
   properties as a current scanner limitation**, after §18.2 fixed them,
   and cited superseded sections (§12.6/§13 instead of §18) plus a stale
   `SimpleTokenizer` mention (actually superseded back at §16, not
   introduced by these two commits, but caught by the same read). `b9627df`
   updated `CLAUDE.md`/`HANDOFF.md` but missed the canonical design doc.
   Fixed, see §20.2.
3. **The issue-tracker CSV's phase-numbering column silently changed
   meaning.** Rows 1–30 use a sequential same-session event counter that
   does *not* equal HANDOFF section numbers (e.g. phase 8 = §14, phase 10
   = §16). Rows 31–33 (`b9627df`) and row 22's updated resolution phase
   (`ce1be2d`) switched to raw HANDOFF section numbers (18, 19) instead,
   jumping straight from phase 10 to phase 18 with nothing in between.
   Fixed, see §20.2.

Also flagged as trivial (Q2): §18.1's `AssemblyLoader.pas:26` citation
for the `IsNested` filter was accurate when §18 was written, but
`ce1be2d` added a `Tsgen.Diagnostics` line to the `uses` clause, shifting
the filter to line 27 — off by one since. Fixed in both `HANDOFF.md` and
`HANDOFF_jp.md` (the only two places citing it) as part of this section's
own edits, addressed in a follow-up pass after the rest of §20 landed
(user caught it hadn't actually been done despite being listed as a
"trivial" finding).

Two minor Q1 wording nits (not inconsistencies between sources, just
imprecise phrasing) are noted in §20.4.

### 20.2 Fixed: findings 2 and 3 (docs + CSV)

- `docs/DESIGN.md` §4 / `docs/DESIGN_jp.md` §4: rewrote the
  `OxygeneSourceScanProvider` paragraph to state indexer properties and
  multi-type sections are supported (§18.2/§18.3), describe the current
  `TokenStream`-based implementation instead of the superseded
  `SimpleTokenizer`, restate the nested-types limitation as a
  Loader+Emitter gap rather than just "a known limitation," and repoint
  citations at §12.6/§18.
- `reports/2026-08-02-issue-tracker.csv`: renumbered rows 31–33 from
  phase 18 to phase **11** (continuing the pre-existing sequential
  counter — nothing had used 11–17 yet), and row 22's resolution phase
  from 19 to **12**, matching the same counter (11 = §18's NRT hardening,
  12 = §19's Diagnostics component). This review's own findings and fixes
  are logged as phase 13 (discovery, "Fable5レビュー3回目") and phase 14
  (fixes, "修正対応2") — rows 34–38.

### 20.3 Fixed: finding 1 (the real scanner bug)

Added the missing `(depth = typeDepth)` guard to
`NullabilityScanner.ScanFile`'s `TOK_PROPERTY` branch
(`src/Tsgen/Nrt/NullabilityScanner.pas`), matching the guard the field
branches already had. A `property` token found while `depth` has moved
past `typeDepth` (inside a nested type's body, or in principle any other
nested block) is now correctly **ignored** instead of being attributed to
`currentTypeName` (the outer type).

**New regression fixture: `tests/fixtures/NestedTypeCollision`.** `Outer`
declares `property Name: nullable String` directly, then a nested `type
Inner = public class ... property Name: not nullable String ... end;`
inside its own body — same member name, opposite nullability, with
`Outer`'s own declaration placed *before* the nested type in the source
(order matters: `ScanMemberDecl` overwrites unconditionally, so whichever
declaration is scanned last determines the final dictionary value; this
ordering is what makes the corruption actually observable rather than
accidentally masked).

Verified both directions hands-on, not just "tests pass" — confirmed the
fixture actually discriminates buggy from fixed behavior before trusting
it as a snapshot baseline:
- `git stash` (temporarily reverting the guard), rebuilt, ran `tsgen`
  directly: `Outer.Name` came back as bare `string` — **wrongly** losing
  `| null`, corrupted by `Inner`'s `not nullable` annotation. Confirmed
  the fixture reproduces the bug.
- `git stash pop` (restoring the guard), rebuilt, ran `tsgen` again:
  `Outer.Name` correctly came back as `string | null` under *both*
  `--nrt-unknown-policy` settings (proving it's the explicit annotation
  surviving, not an Unknown-policy fallback coincidence). Locked in as
  the `expected/*.d.ts` snapshot via `tools/run-tests.ps1
  -UpdateSnapshots` only after this manual confirmation.

Full suite: `tools/run-tests.ps1` — **8/8 cases pass** across all four
fixtures (`MultiTypeAndIndexer`, `NestedTypeCollision`, `SampleModel`,
`TokenizerEdgeCases`); `git diff` on the three pre-existing fixtures'
snapshots is empty (no regressions from the guard addition).

**Rationale corrected in all five places** the overstated claim appeared:
`NullabilityScanner.pas`'s header comment now explains the guard and
narrows the claim to "nested-type members are ignored without corrupting
anything" rather than "nested-type members never affect output" (the
latter was only ever true for the Loader/Emitter path, not the scanner's
own dictionary). `HANDOFF.md`/`HANDOFF_jp.md` §18.1 got an inline
correction blockquote pointing here rather than being silently rewritten
(preserves what was actually believed at the time; §14/§9.4's "resolved"
pattern is the precedent for this). `CLAUDE.md`'s nested-types paragraph
and CSV row 31 (via the new row 34, §20.2) were updated directly since
they're living status, not a dated log entry.

### 20.4 Two minor Q1 wording nits, also fixed

- `CLAUDE.md`'s Diagnostics paragraph read as if `Program.pas` performs
  the unmapped-type dedup; it's actually `DtsEmitter.Emit` that groups by
  CLR type name, and `Program.pas` only prints the already-deduplicated
  result. Reworded.
- CSV row 32's Japanese description said "ブレース深度" (brace depth,
  `{}`) where the code actually tracks bracket depth (`[]`) — should have
  been "ブラケット". Also tightened "property直後がColon" to specify
  "プロパティ名直後" (immediately after the property *name*, not the
  `property` keyword itself), matching what both HANDOFF language
  versions already said correctly. Fixed directly in row 32 (not a new
  row — a wording-only correction to already-accurate content, unlike
  §20.2/§20.3's rows which needed a distinct "what was wrong, what fixed
  it" record).

### 20.5 What this does not change

- Nested types are still out of scope for *real* support (a nested
  type's own members getting their own output). §20.3 only fixes the
  scanner's dictionary-corruption side effect on OUTER members — it does
  not make `AssemblyLoader` stop filtering `IsNested` types or give
  `DtsEmitter` a nested-`interface` output path. That remains the
  three-stage task described in §18.1.
- No change to `DiagnosticList`, the Diagnostics component's own design,
  or anything in §19 beyond the `CLAUDE.md` wording nit in §20.4 — the
  review found §19's substance sound.

---

## 21. `INullabilityProvider` chain + `mark-unknown` policy implemented (Windows hands-on, 2026-08-02)

Resolves issue-tracker items #9 and #10 — the two remaining Fable5
review-1 deferrals (`HANDOFF.md` §13 deferral item 4): the provider-chain
abstraction had no seam at all (a direct dictionary lookup in
`IrBuilder.Build`), and `--nrt-unknown-policy`'s third value was blocked
on it. User picked this up next, from the residual-open-items list.

### 21.1 Scope decided before writing code

Two design forks confirmed with the user up front rather than assumed:

1. **Whether to include Provider 3 (`ValueTypeDefaultProvider`, value
   types non-nullable by default) alongside Provider 1**, given it
   measurably changes existing snapshot output for unannotated
   value-typed members (they stop being `Unknown` at all, so
   `--nrt-unknown-policy` no longer touches them). **Confirmed: yes,
   include it** — it's explicitly part of the same `docs/DESIGN.md` §4.2
   provider-chain design, not scope creep, and the behavior change is a
   correctness improvement (matches C#/.NET's actual default: value
   types are non-nullable unless explicitly `Nullable<T>`/`T?`).
2. **How to render `mark-unknown` in TypeScript**, since the type system
   has no way to express "nullability undetermined" as distinct from
   "confirmed non-nullable." **Confirmed: same bare type as `non-null`,
   plus a trailing `// nrt: unknown` line comment** — visually/grep-ably
   distinct without inventing a fake type or JSDoc tag that might collide
   with the not-yet-implemented XML-doc-to-JSDoc feature
   (`docs/DESIGN.md` §10.2 item 3).

Provider 2 (`RoslynStyleAttributeProvider`, reflection-attribute-based)
was deliberately **not** implemented — it remains genuinely unimplemented
per `docs/DESIGN.md` §4.2, and the chain only contains the two providers
that are real rather than a stub for a third.

### 21.2 What was added

**New file `src/Tsgen/Nrt/NullabilityProviders.pas`** (added to
`Tsgen.elements`'s `Compile` list right after `NullabilityScanner.pas`,
since it needs `NullabilityKind` and precedes `IrBuilder.pas` which uses
it): `INullabilityProvider` (one method,
`TryGetNullability(aTypeFullName, aMemberName, aClrTypeName): NullabilityKind`),
`OxygeneSourceScanProvider` (wraps the existing scan-result dictionary —
Provider 1), `ValueTypeDefaultProvider` (Provider 3 — a known-value-type
CLR-name list, deliberately kept as a separate list from
`Tsgen.Ir.TypeMapper`'s rather than a shared call, since `Tsgen.Ir`
already depends on `Tsgen.Nrt` one-way and calling back would create a
circular unit reference — the two lists are documented as needing to stay
in sync), and `NullabilityProviderChain.Resolve` (tries each provider in
list order, stops at the first non-`Unknown` answer — same "first match
wins" philosophy as the type-mapping chain in `docs/DESIGN.md` §2.2/§2.3).

Adapted from `docs/DESIGN.md` §4.2's `IrMemberRef`/`AnalysisContext`
pseudocode to the concrete strings this tool actually has (type full
name, member name, raw CLR type name) — the abstract sketch was
illustrative of the *pattern*, not a literal API to replicate given
`IrMemberRef`/`AnalysisContext` don't otherwise exist in the codebase.

**`IrBuilder.pas`**: `Build` now constructs
`[OxygeneSourceScanProvider(aNullability), ValueTypeDefaultProvider]` once
and resolves every member's `Nullability` through
`NullabilityProviderChain.Resolve` instead of the direct dictionary
lookup. `IrBuilder.Build`'s own signature is unchanged (still takes the
raw scan dictionary) — the chain's existence is an internal
implementation detail, invisible to `Program.pas`. `NrtUnknownPolicy`
gained a third value, `MarkUnknown`.

**`DtsEmitter.pas`**: `ResolveNullable` split into two methods —
`ResolveNullableSuffix` (unchanged logic, renamed) decides whether to
append `| null`; new `ShouldMarkUnknown` decides whether to append the
`// nrt: unknown` comment (true only when the member is genuinely
`Unknown` *and* the policy is `MarkUnknown` — explicitly-annotated
members never get the comment, matching the existing rule that policy
only ever touches genuinely-`Unknown` members).

**`Program.pas`**: `--nrt-unknown-policy mark-unknown` recognized
alongside the existing `nullable`/`non-null` values; usage string
updated.

### 21.3 Fixture/snapshot changes from adding Provider 3

Hand-verified before trusting `-UpdateSnapshots`, same discipline as
§18/§20: ran `tsgen` directly against `SampleModel` first. Confirmed
`Age`/`IsAdmin` (`Int32`/`Boolean`, unannotated) flipped from `number |
null`/`boolean | null` (default policy) to bare `number`/`boolean` —
correctly resolved as definitively not-nullable by Provider 3, no longer
`Unknown` at all, so the policy no longer has anything to act on for
them.

**Side effect this surfaced**: `SampleModel`'s `union-nonnull` case
existed specifically to exercise `--nrt-unknown-policy non-null`, but its
only two `Unknown` members (`Age`, `IsAdmin`) were both value types —
after Provider 3, `SampleModel` had **zero** genuinely-`Unknown` members
left, silently making that case stop testing anything policy-related.
Added `property Notes: String read write;` (deliberately unannotated,
deliberately a reference type so Provider 3 can't resolve it) to restore
a genuinely-`Unknown` member the policy can still discriminate on. Added
matching `mark-unknown` cases to both `SampleModel` and
`TokenizerEdgeCases` (`TokenizerEdgeCases` already had several genuinely-
`Unknown` `String` members from its comment/string-literal-leak tests, no
source changes needed there).

Full diff review (not just "tests pass"): `MultiTypeAndIndexer`'s
`Beta.Count: Int32` (unannotated) flipped from `number | null` to
`number` in the `default` case (identical reasoning to `SampleModel`);
its `non-null` case was already `number` so no diff there.
`NestedTypeCollision` and `TokenizerEdgeCases`'s `default`/`non-null`
cases showed **no diff** — `NestedTypeCollision`'s only member is
explicitly `nullable` (unaffected by Provider 3), and
`TokenizerEdgeCases` has no value-typed members at all.

### 21.4 Verification

- `tools/dev-build.ps1`: clean build.
- Hand-verified `mark-unknown` output on both `SampleModel` (`Notes:
  string; // nrt: unknown`, with `Age`/`IsAdmin`/explicitly-annotated
  members all unaffected) and `TokenizerEdgeCases` (four genuinely-
  `Unknown` members correctly commented, `WithKeywordDefault`/
  `ExplicitlyNotNullable`/etc. correctly not) before running
  `-UpdateSnapshots`.
- `tools/run-tests.ps1 -UpdateSnapshots` then plain `tools/run-tests.ps1`:
  **10/10 cases pass** across all four fixtures (2 new `mark-unknown`
  cases added, for 10 total vs. the previous 8).
- Every snapshot diff reviewed by hand (§21.3) and matched what the
  hand-verification predicted — no surprises between manual `tsgen`
  invocations and the snapshot suite.

### 21.5 What this does not change

- Provider 2 (reflection-attribute-based NRT for C#/VB dependency
  assemblies) remains unimplemented — still correctly post-MVP per
  `docs/DESIGN.md` §4.2.
- The `MetadataFxProvider` open slot (`docs/DESIGN.md` §4.1) is still
  just a slot — §14 already closed that lead as a dead end for NRT
  specifically, so there's nothing to implement there for this tool.
- No changes to `AssemblyLoader.pas`, `NullabilityScanner.pas`, or the
  Diagnostics component — this was entirely a Stage 2/4 (IR builder /
  emitter) change plus one new Stage-2-adjacent unit.

---

## 22. §3.5 technical spike: is entry-point-driven `Inertia.Render` detection viable? (Windows hands-on + web research, 2026-08-02)

Resolves the "top-priority technical validation item" `docs/DESIGN.md`
§11 item 8 flagged for whichever session picks up the Inertia.js pivot
(§6). User chose to start §6 with exactly this spike, per the ordering
discussed earlier this session (resolve the entry-point-detection unknown
before investing in generics/cycle-detection, since the unknown
determines what shape that investment needs to take). Method: real web
research into InertiaNetCore's actual API (not the assumed/generic
shape), then hands-on Oxygene probes in the session scratchpad (same
disposable-probe convention as §14.1/§16.2/§18.2/§21) to test what
DESIGN.md's original write-up left untested. **Conclusion: yes, viable —
via source-level token scanning, not IL analysis and not a Roslyn-style
full AST (neither of DESIGN.md §3.5's original two options) — but a
significant, previously-unknown Oxygene-specific language gotcha changes
what the scanner needs to handle.**

### 22.1 InertiaNetCore's actual `Render` API (web research)

`docs/DESIGN.md` §3.5's framing ("resolve the static type of the `data`
argument") assumed a shape like C#'s generic `Inertia.Render(name, new {
...})`. The actual API (`mergehez/InertiaNetCore`, the adapter
`HANDOFF.md` §6.4 already committed to) is narrower:

```csharp
public static Response Render(string component);
public static Response Render(string component, InertiaProps? props);
public static Response Render(string component, Dictionary<string, object?>? props);
// InertiaProps : Dictionary<string, object?>
```

**There is no overload accepting an arbitrary POCO or anonymous object
directly.** Every real usage example in the project's own README
constructs `InertiaProps`/`Dictionary` via C# object-initializer syntax:
`new InertiaProps { ["Name"] = "InertiaNetCore", ["Version"] = ... }`,
including `Inertia.Defer(async () => ...)`/`Inertia.Merge(async () =>
...)`-wrapped values for lazy-loaded props.

**Consequence: the `data` argument's *static* type is always
`InertiaProps`/`Dictionary<string, object?>` — never informative on its
own.** The real problem §3.5 needs to solve isn't "resolve one
expression's type," it's "for each string key added to the props
dictionary, determine the type of the value expression assigned to it."
This is a narrower, differently-shaped problem than the design doc
originally posed, and it's the one the rest of this spike actually
investigates.

### 22.2 Oxygene anonymous classes: confirmed to exist, confirmed reflectable, confirmed *not* usable inline here

Oxygene has anonymous class/record/interface literals: `new
class(Name := 'Peter', Age := 35)`. Verified hands-on (disposable probe):
compiles, and — unlike the concern `docs/DESIGN.md` §3.5 raised about C#
anonymous types being IL-opaque — reflection sees a real, fully
reflectable synthesized generic type:
`<>f__AnonymousType0\`2[System.String,System.Int32]`, with working
property access (`a1.Name` correctly returned `'Peter'`). Same
synthesized-name-instability as C#'s `<>f__AnonymousType0`, but the
*shape* (property names + types) is genuinely recoverable via reflection
if you can get your hands on a specific instance's `Type` — the practical
blocker is correlating "the anonymous literal at *this* source location"
to "*that* reflected type," not the reflectability of anonymous types in
general. Given §22.1's finding that `InertiaProps` values are added one
key at a time, an inline `new class(...)` could still appear as a single
prop's *value* (e.g. `props['Meta'] := new class(Total := 10, Page :=
1);`) — handled the same way as any other value expression (§22.4), via
source-level parsing, not reflection.

### 22.3 New finding: Oxygene has no object/collection-initializer syntax, and the closest-looking syntax silently no-ops

Not something either DESIGN.md or HANDOFF.md previously flagged.
Verified hands-on with three candidate syntaxes for populating a
`Dictionary<String, Object>`, mirroring InertiaNetCore's own C# README
examples:

1. `new Dictionary<String, Object> { ['Name'] := 'Foo', ['Age'] := 30 }`
   — **compiles cleanly, but silently does nothing.** `{ }` is Oxygene's
   block-comment delimiter (already known from NRT scanner work,
   `HANDOFF.md` §16.3's comment-leak test cases) — the entire
   `{ ['Name'] := 'Foo', ['Age'] := 30 }` block tokenizes as a single
   comment fragment and is discarded, leaving `new Dictionary<String,
   Object>` — an empty dictionary — as the actual expression. **Confirmed
   at runtime, not just by inspecting tokens**: `d1.Count` printed `0`
   after this exact line. This is a genuine, silent-failure language trap
   for anyone porting InertiaNetCore's own official C#-style examples
   into Oxygene verbatim — no compiler warning, no error, just silently
   empty Page Props in production.
2. `new Dictionary<String, Object>(['Name'] := 'Foo', ['Age'] := 30)`
   (parens instead of braces) — hard compile error: `comma (,) or close
   parenthesis expected, got assignment (:=)`.
3. `new Dictionary<String, Object>(('Name', 'Foo'), ('Age', 30))`
   (tuple-pair Add-style) — hard compile error: no matching constructor
   overload (tuple literals aren't coerced to a `capacity`/`comparer`
   pair).

**Conclusion: the only way to populate an `InertiaProps`/`Dictionary` in
Oxygene is sequential indexer-assignment statements after construction**
(`var props := new InertiaProps; props['User'] := aUser; props['IsAdmin']
:= true;`) — confirmed as the only pattern that actually works, and (per
§22.1) the only pattern real Oxygene Inertia code can use at all, since
no inline-literal alternative compiles to anything meaningful.

**Worth reporting to RemObjects independently of this project** (not done
yet — flagging for the user to decide, same as the `deps.json` bug in
`HANDOFF.md` §17): a curly-brace block that looks exactly like a
plausible object-initializer silently compiling to a no-op comment,
rather than either working or erroring, is a sharp footgun matching the
kind of issue RemObjects has been responsive to before.

### 22.4 Detection feasibility, confirmed hands-on via `TokenStream`

Because §22.3 established that real code is *always* the
sequential-statement pattern, tokenized the realistic probe method below
through `RemObjects.Elements.Code.TokenStream` (same tool, same technique
as `NullabilityScanner`, §16) and inspected the raw token list:

```pascal
method Profile(aUser: UserDto): InertiaResponse;
begin
  var props := new InertiaProps;
  props['User'] := aUser;
  props['IsAdmin'] := true;
  result := Inertia.Render('pages/Profile', props);
end;
```

The token stream is unambiguous and cleanly structured — `method Profile
( aUser : UserDto )` gives the parameter's declared type; `var props :=
new InertiaProps` gives the local variable's type; each `props [
'<key>' ] := <value> ;` is a flat, easily-delimited statement; the call
site itself is `Inertia . Render ( '<component>' , props ) ;`. This is
mechanically the same class of problem `NullabilityScanner` already
solves (paren/bracket-depth-tracked token walking, §18.2's indexer-skip
logic is structurally the same shape as what indexer-assignment detection
here needs) — **no IL analysis and no Roslyn-style full AST required**,
resolving the "neither approach has been prototyped" gap `docs/DESIGN.md`
§3.5 flagged. A third option — source-level token scanning, extending the
already-proven `NullabilityScanner` infrastructure — is the answer,
matching the project's own established bias (§2.9, §8.3) toward
source-level analysis over IL/reflection for anything Oxygene's compiler
doesn't expose through standard metadata.

### 22.5 Reflection's role: none for the props shape itself, full reuse once a named type is resolved

Metadata-only reflection (`MetadataLoadContext`, this tool's whole Loader
design) cannot see method *bodies* at all — the props-key-to-type mapping
is 100% invisible to it, confirming this is purely a source-level
problem, not a reflection one (a sharper version of the same conclusion
already reached for NRT, `HANDOFF.md` §8.3). But once source scanning
resolves a value expression to a reference to a *named* type (a
parameter/local variable's declared type, or a `new NamedType(...)`
expression), the **existing** `AssemblyLoader`/`IrBuilder` reflection
pipeline handles that type's own member shape with zero new code needed —
clean division of labor matching `docs/DESIGN.md` §3.5's own diagram
(step ③, "walk that type's members transitively, reusing the
edge-collection logic of §3.2"). Inline `new class(...)` anonymous-literal
values (§22.2) are the one case that stays fully source-level even after
this handoff — their shape must come from parsing the literal's own
`Name := expr` pairs, not from reflecting the resulting
`<>f__AnonymousTypeN`.

### 22.6 Honest scope assessment: this is a bigger scanner than NRT's

Confirmed feasible, not confirmed cheap. What a v1 entry-point scanner
needs, beyond what `NullabilityScanner` already does:

- Per-method local-variable type tracking (parameter declared types +
  `var x := new T` local declarations) — `NullabilityScanner` has no
  notion of "method body local state" today, only type/member-level
  declarations.
- Correlating `identifier['key'] := expr;` statements back to a tracked
  variable.
- Expression-type inference for a deliberately small set of shapes:
  literals, a plain identifier (look up its tracked declared type), `new
  NamedType(...)`, and `new class(...)` (recurse into its own pairs).

**Deliberately out of scope for v1** (fall back to `unknown` + a
`Tsgen.Diagnostics` warning per unresolved key, or to `docs/DESIGN.md`
§3.5's explicit-annotation escape hatch for the whole page if too much is
unresolvable, rather than a hand-rolled expression evaluator): conditional
/branch-dependent key-setting, keys set via a helper-method call, values
wrapped in `Inertia.Defer(...)`/`Inertia.Merge(...)` (the real type is an
async lambda's return type — a second, smaller spike of its own if
pursued), dynamically-computed string keys, and a props object built in a
different method/class than where `Render` is actually called.

### 22.7 Recommendation

**Entry-point-driven auto-discovery is technically viable and should be
the primary mechanism**, not the `docs/DESIGN.md` §3.5 fallback
(explicit per-type annotation) — scoped to the sequential
indexer-assignment-in-the-same-method pattern established as the only
pattern real Oxygene code can produce anyway (§22.3). Falling back to
`unknown`/a diagnostic warning for the explicitly-out-of-scope cases
above (rather than requiring full manual annotation the moment *anything*
in a controller is unrecognized) keeps the "automatic, no manual
annotation" value proposition for the common case while degrading
gracefully, not catastrophically, for the uncommon one.

Not yet done, left for whichever session implements this: writing the
actual scanner (`Tsgen.Nrt`-adjacent or a new `Tsgen.Inertia`-ish unit),
building fixtures covering the confirmed-working sequential pattern plus
the explicitly-out-of-scope cases (to lock in that they degrade to
`unknown`+warning rather than crash or silently mis-detect), and — per
§6.2's still-open item — deciding how the `Inertia.Defer`/`Inertia.Merge`
wrapper case should eventually be handled.

### 22.8 Impact on `docs/DESIGN.md`

§3.5 needs a revision pass to: replace the "(a) IL analysis / (b)
Roslyn-syntax-tree analysis, neither prototyped" framing with this
spike's answer (source-level `TokenStream` scanning, extending
`NullabilityScanner`'s proven approach); note the `InertiaProps`/
`Dictionary`-only API shape from §22.1 (no arbitrary-POCO overload);
and record the Oxygene object-initializer gotcha from §22.3 as a
load-bearing fact the detection design depends on. Not rewritten in full
here — flagged for the next pass, same as `docs/DESIGN.md` §4's revision
was tracked before it was actually done (`HANDOFF.md` §8.3 → §13).

---

## 23. Generics support implemented (Windows hands-on, 2026-08-02)

`docs/DESIGN.md` §10.2 item 1 ("Generalizing generics (`List<T>`,
`Dictionary<K,V>`), inheritance/interfaces"), picked up ahead of the
entry-point scanner itself (§22) per the ordering discussed this
session: real Page Props DTOs will almost certainly use collections, so
building the scanner before generics support existed would have produced
output that couldn't render them.

### 23.1 Scope decided before writing code

User confirmed two forks up front:

1. **Cycle detection (Tarjan SCC) deferred, generics done alone this
   round.** `docs/DESIGN.md` §3.3 states cycles can generally be ignored
   for `DtsEmitter` specifically (TS `interface`/`type` declarations
   tolerate circular references natively) — its main value is the
   zod `SchemaEmitter` (not built) and single-file output ordering
   (cosmetic). Building full Tarjan SCC now, before either of those
   exist, would be exactly the kind of premature infrastructure
   `CLAUDE.md` says to avoid. Revisit when the zod emitter is actually
   built.
2. **Inheritance already works, verified hands-on, no code needed.** A
   probe class hierarchy confirmed `t.GetProperties(Public|Instance)`
   (no `DeclaredOnly`) already returns inherited base-class properties
   alongside a derived type's own — this was already true before this
   session's changes; `docs/DESIGN.md` grouping it with generics as one
   post-MVP item didn't mean it needed separate implementation.

### 23.2 What was added

**`RawTypeRef`** (new type in `src/Tsgen/Loading/RawModel.pas`):
structural CLR type reference — `FullName`, `IsArray`/`ElementType`,
`TypeArguments: List<RawTypeRef>` — built recursively from `System.Type`
via a new `AssemblyLoader.BuildTypeRef` using `GetElementType()`/
`GetGenericArguments()` directly, never `Type.FullName`'s mangled,
assembly-qualified generic-argument string (confirmed hands-on this
matters: `List<Foo>.FullName` looks like
`"System.Collections.Generic.List\`1[[Foo, MyAsm, Version=...]]"` — not
something worth string-parsing when the real API gives clean pieces
directly). `RawMember.ClrTypeName: String` → `RawMember.TypeRef:
RawTypeRef` throughout — `IrMemberLite` reuses `RawTypeRef` directly
(same "reuse, don't duplicate" pattern already used for
`NullabilityKind`).

**`TypeMapper.MapClrTypeName(String)` → `TypeMapper.MapTypeRef(RawTypeRef,
HashSet<String>)`**: recursive over the new structural type. Handles, in
order: arrays (element-type recursion + `[]`), `Nullable<T>`/`Task<T>`/
`ValueTask<T>` (docs/DESIGN.md §2.2's named "special cases" — unwrap to
the single type argument's mapping; `Nullable<T>`'s nullability itself
stays a `Tsgen.Nrt` concern, not doubled up here), `List<T>`/`IList<T>`/
`IEnumerable<T>`/`ICollection<T>`/`IReadOnlyList<T>`/
`IReadOnlyCollection<T>`/`HashSet<T>`/`ISet<T>` → `T[]`,
`Dictionary<K,V>`/`IDictionary<K,V>`/`IReadOnlyDictionary<K,V>` →
`Record<K, V>` when `K` maps to `string`/`number` (else `unknown` — no
clean JSON-shaped TS equivalent for non-primitive keys), then the
existing known-BCL-primitive leaf mapping, unchanged.

**`INullabilityProvider.TryGetNullability`'s `aClrTypeName: String` →
`aTypeRef: RawTypeRef`** (`Tsgen.Nrt.NullabilityProviders`, `Tsgen.Nrt`
gained a one-way dependency on `Tsgen.Loading` — no cycle, `Tsgen.Loading`
depends on neither). `ValueTypeDefaultProvider` now also recognizes
`Nullable<T>` (CLR `FullName = "System.Nullable\`1"`) as always
`IsNullable`, regardless of `T` — confirmed hands-on that Oxygene's
`nullable Int32` on a value type really does compile to
`System.Nullable\`1[[System.Int32]]`, not some Oxygene-specific
encoding. This is a real capability gain, not just plumbing: previously
*every* member was `Unknown` without `--source`; now a `Nullable<T>`-typed
member resolves correctly via reflection *alone*, no source access
needed — confirmed by running the new fixture with `--source` omitted
(§23.3).

### 23.3 Bug found mid-implementation: user-defined types had no
resolution path at all

Building the `Generics` fixture (a self-referential `Node` type with a
`List<Node>` member) surfaced a real gap that predates this session's
generics work but was invisible until generics support made it
observable: `TypeMapper` had **never** had a branch for "this leaf CLR
type isn't a BCL primitive, but it IS one of our own emitted types" —
any property of a custom type (even a plain, non-generic one) silently
fell to `'unknown'`. `List<Node>` exposed this immediately as
`unknown[]` instead of `Node[]`.

Fixed by adding `DtsEmitter.Emit`-built `aKnownTypes: HashSet<String>`
(every `IrTypeLite`'s `Namespace.Name`, covering both class-like and
enum types), threaded through `MapTypeRef`: a leaf type found in this
set resolves to a reference by its own fully-qualified name
(`Namespace.Name`, e.g. `Generics.Node`) rather than falling through to
`unknown`. Always fully qualified, never the bare short name — TS's
`declare namespace A.B` blocks accept dotted-namespace references
regardless of which namespace block the reference site is in, so this
is correct without tracking "am I in the same namespace as what I'm
referencing." This is `docs/DESIGN.md` §2.2 chain step "③e. User-defined
types" in miniature — the first time it's existed in any form.

Named-type references are never structurally expanded (`Node`'s own
`List<Node>` member just says `"Node[]"`, it doesn't inline `Node`'s
shape again) — confirmed by the `Generics` fixture actually building
and running without any infinite loop, which is the concrete
verification behind §23.1's decision that Tarjan SCC isn't load-bearing
for `DtsEmitter` yet.

### 23.4 New fixture: `tests/fixtures/Generics`

`Tag` (a plain named type) and self-referential `Node` (`Value: not
nullable String`; `Children: List<Node>`; `Tags: List<Tag>`; `Scores:
List<Int32>`; `Lookup: Dictionary<String, Int32>`; `MaybeCount: nullable
Int32`; `Numbers: array of Int32`). Two cases locked in via the normal
convention (`default`, `non-null`): confirms `Generics.Node[]`/
`Generics.Tag[]` (named-type + self-reference), `number[]` (`List<Int32>`
element unwrapping), `Record<string, number>` (`Dictionary` → `Record`),
`number[]` for the plain array, and `MaybeCount: number | null` staying
`| null` under *both* policies (explicit annotation, unaffected by
policy) while the unannotated reference-type-generic members correctly
flip with the policy.

**Third case verified hands-on but not locked into the snapshot suite**:
running with `--source` omitted entirely and `--nrt-unknown-policy
non-null`. Every reference-type-generic member (`Children`, `Tags`,
`Scores`, `Lookup`, `Numbers`) correctly lost `| null` (genuinely
`Unknown` without source, non-null policy applies) — but `MaybeCount`
*kept* `| null`, proving `ValueTypeDefaultProvider`'s new `Nullable<T>`
detection fires from reflection alone. Not added as a permanent
`cases.json` entry because `tools/run-tests.ps1` always passes
`--source <fixtureDir>` unconditionally for every case (no per-case way
to omit it today) — extending the shared runner for one narrow scenario
wasn't judged worth it this round; the finding is preserved here as a
verified fact instead. If `--source`-omission ever needs to be a
permanent regression test, the runner needs a case-level opt-out flag
first.

### 23.5 Verification

- `tools/dev-build.ps1`: clean build (one real syntax error hit and
  fixed along the way — see §23.6).
- `tools/run-tests.ps1 -UpdateSnapshots` then plain `tools/run-tests.ps1`:
  **12/12 cases pass** across all five fixtures (`Generics` ×2 new,
  the previous eight unchanged). `git diff` on all four pre-existing
  fixtures' snapshots: empty — no regressions from the `RawTypeRef`
  plumbing change touching every stage from Loader to Emitter.

### 23.6 Oxygene gotcha hit while writing doc comments (not a design
issue, noting for future sessions)

A doc comment containing a literal TypeScript code sample with curly
braces (`` `declare namespace A.B { ... }` ``) broke the build with a
cascade of confusing parser errors starting well past the actual
problem line. Root cause: Oxygene's `{ }` block comments do not nest —
the first inner `}` in the sample closed the comment early, and
everything after that up to the *real* next `}` was parsed as live
code. Fixed by rephrasing the comment to avoid literal braces. Worth
remembering: never put brace-containing code samples inside a `{ }`
comment in this codebase; use prose description or a `//` line comment
instead if a literal sample is really needed.

### 23.7 What this does not change

- Cycle detection (Tarjan SCC) remains unimplemented, deliberately
  (§23.1) — revisit when the zod `SchemaEmitter` is built, where it's
  actually load-bearing.
- Provider 2 (reflection-attribute-based NRT), the plugin mechanism,
  split-file output, and the Inertia-specific entry-point scanner (§22)
  are all still separately unimplemented — this section only covers
  `docs/DESIGN.md` §10.2 item 1.
- `Task<T>`/`ValueTask<T>` unwrapping was added to `TypeMapper` (§23.2)
  since it was cheap and explicitly named in `docs/DESIGN.md` §2.2, but
  nothing yet *produces* an async-wrapped member to exercise it against
  — no fixture coverage for this specific branch yet.

---

## 24. Inertia.Render entry-point scanner implemented (`--mode inertia`) (Windows hands-on, 2026-08-02)

Implements the mechanism the §22 spike confirmed viable — this is
`docs/DESIGN.md` §3.5 (entry-point-driven type discovery) for real,
resolving the "top-priority technical validation item" `docs/DESIGN.md`
§11 item 8 flagged. User confirmed the v1 scope up front: literal /
identifier / non-generic `new NamedType(...)` value expressions resolve;
`new class(...)` anonymous-literal prop values fall back to `unknown` +
a diagnostic rather than being supported this round (synthesizing an
on-the-fly named IR type for them is a distinct, larger piece of work,
deferred).

### 24.1 Shared tokenizer extracted first

Before writing the new scanner, extracted `NullabilityScanner`'s
`ScanToken`/`Tokenize`/`EnsureLanguageRegistered` into a new
`src/Tsgen/Nrt/OxygeneTokenizer.pas` (`Tsgen.Nrt.OxygeneTokenizer`,
`Tsgen.Nrt.ScanToken`) — real, current duplication (both scanners need
the exact same `TokenStream`-over-a-whole-file setup) rather than
speculative reuse, so factoring it out first was the right call, not
premature abstraction. `NullabilityScanner.Scan` now calls
`OxygeneTokenizer.Tokenize` instead of a private copy; behavior
unchanged, confirmed by the full suite still passing before writing any
new code.

### 24.2 `InertiaScanner` (`src/Tsgen/Inertia/InertiaScanner.pas`)

Per §22.3's finding that Oxygene has no working object/collection-
initializer syntax, the *only* pattern real code can produce is
sequential indexer assignment:

```pascal
var props := new InertiaProps;
props['User'] := aUser;
props['IsAdmin'] := true;
result := Inertia.Render('pages/Profile', props);
```

So the scanner's job, within each `method ... begin ... end;` body
(constructors and bodyless/interface method declarations are not
tracked — v1 scope), is to:

1. Track parameter declared types (from the `method Name(...)` header)
   and local variable declared types (from `var x := new T;` / `var x:
   T := ...;`), resolved via a small BCL-alias table (`String` →
   `System.String`, etc.) plus a short-name lookup into the target
   assembly's own types (built once from `RawAssembly.Types`).
2. Recognize a local variable as a "props candidate" when its resolved
   written type name is literally `InertiaProps` or `Dictionary`
   (string match on the type name as written — good enough since these
   are the only two type shapes InertiaNetCore's `Render` accepts,
   §22.1).
3. For every `propsCandidate['key'] := valueExpr;` statement, resolve
   `valueExpr`'s type — literal (string/integer/real/`true`/`false`),
   a plain identifier (looked up in the tracked parameter/local symbol
   table), or `new NamedType` / `new NamedType(...)` (non-generic only)
   — appending one field to that variable's accumulated list, or (if
   unresolvable) adding a `Tsgen.Diagnostics` warning naming the key and
   falling back to a placeholder "(unresolved)" type that maps to
   `unknown`.
4. On `Inertia.Render('component', propsVar)`, emit an
   `InertiaPageProps` using `propsVar`'s accumulated fields (or, for
   `Inertia.Render('component')` with no second argument, a legitimate
   zero-field page); an unresolvable second argument (a method call, an
   inline expression, a variable never seen as a props candidate) warns
   and skips that call site rather than emitting a wrong/incomplete page
   silently.

**Found and fixed while building the fixture, not while designing**:
the "new NamedType(...)" matcher initially required parentheses, but
Oxygene allows a no-arg constructor call with no parens at all (`new
MetaDto;` — confirmed already working elsewhere in this codebase, e.g.
`result := new InertiaResponse;` in the §22 spike probe). Without
handling the 2-token `new Identifier` shape explicitly, this is a
realistically common pattern that would have silently resolved to
`unknown` instead of the real type. Fixed before it shipped, caught by
building a fixture that actually used the no-parens form rather than
only the with-parens one.

Token IDs needed beyond what `NullabilityScanner` already used
(`TI_method=243`, `TI_new=247`, `T_Assignment=132`, `T_String=170`,
`T_Integer=160`, `T_Real=161`, `TI_true=273`, `TI_false=224`) were
confirmed by reflecting on `RemObjects.Elements.Code.Oxygene.Token`'s
public static fields and by tokenizing throwaway snippets, same
verify-don't-guess discipline as every prior token-ID confirmation this
project has done (§7.2, §12.2, §16.1, §18.2). String literals are
single-quoted, Pascal-style (`''` escapes a literal quote); neither
`GetString()` nor `GetOriginalString()` unquotes them — confirmed
hands-on — so `UnquoteStringLiteral` strips the outer quotes and
un-escapes `''` to `'` manually.

### 24.3 `InertiaIrBuilder` (`src/Tsgen/Inertia/InertiaIrBuilder.pas`) — reachability BFS

`Tsgen.Ir.IrBuilder` was split into three pieces first
(`BuildProviders`, `BuildType`, `Build` — the last now just calls the
first two in a loop) so `InertiaIrBuilder` could reuse the identical
per-type NRT-resolution logic instead of duplicating it — the only new
piece needed was *which* types to convert, not *how*.

Given the scanner's output (a list of pages, each a list of `(key,
RawTypeRef)` fields), building the final `IrAssemblyLite` is: (1) index
`RawAssembly.Types` by `FullName`; (2) seed a BFS queue/`HashSet<String>`
from every field's `RawTypeRef` (recursing through arrays/generic
arguments to find leaf named-type references, reusing the exact
unwrapping shape `TypeMapper.MapTypeRef` already needs); (3) drain the
queue, and for each reachable type's own members, repeat step 2 —
this is `docs/DESIGN.md` §3.2 step ①'s edge-collection, minus the SCC
decomposition (still deliberately deferred, §23.1) and scoped to start
from an ad-hoc root set instead of "every type," rather than a new
algorithm; (4) `IrBuilder.BuildType` each reachable `RawType`, in
`aRaw.Types`'s own order (not the `HashSet`'s iteration order — not a
contract to rely on, same rationale used elsewhere in this codebase);
(5) synthesize one `IrTypeLite` interface per page, resolving each
field's `Nullability` through the *same* provider chain via
`NullabilityProviderChain.Resolve` with an empty type-name key (a
synthesized Props type has no real reflected member for
`OxygeneSourceScanProvider`'s dictionary to match against — it correctly
returns `Unknown`, and `ValueTypeDefaultProvider` still resolves
value-typed/`Nullable<T>` fields correctly from the `RawTypeRef` alone,
regardless of the key).

**Found and fixed while inspecting actual output, not while designing**:
the first working version gave synthesized Props types
`NamespaceName := ''`, which `DtsEmitter` — correctly, per its existing
logic — renders as a **bare top-level `export interface`**, not wrapped
in `declare namespace`. A `.d.ts` file mixing a bare top-level `export`
with `declare namespace` blocks stops being a pure global-ambient
declarations file the moment that `export` appears — TypeScript treats
the presence of any top-level `import`/`export` as making the *whole
file* a module, silently changing how every other namespace in the same
file is consumed by downstream code. Fixed by giving all synthesized
Props types a shared `'Props'` namespace instead of no namespace at
all — a placeholder grouping choice, not a settled convention (see
§24.5). This was caught by reading the actual generated `.d.ts` output
by eye before locking in the fixture, not by any automated check — worth
remembering as a category of bug (structurally-valid-per-type-but-
wrong-when-combined output) unit-level review doesn't catch.

### 24.4 CLI wiring

`Program.pas` gained `--mode assembly|inertia` (default `assembly`,
preserving all existing behavior byte-for-byte — confirmed via the full
suite passing unchanged before this section's fixture was even added).
`--mode inertia` requires `--source` (hard error otherwise: entry-point
discovery has nothing to scan without it) and branches to
`InertiaScanner.Scan` + `InertiaIrBuilder.Build` in place of
`AssemblyLoader`'s implicit whole-assembly `IrBuilder.Build` path;
`NullabilityScanner.Scan` still runs identically either way (both modes
need the same NRT dictionary).

### 24.5 New fixture: `tests/fixtures/InertiaMode`

One controller method with one `Inertia.Render` call, covering every
resolved/unresolved shape in one pass: `User: UserDto` (identifier
referencing a parameter — and `UserDto.Role: RoleDto` makes `RoleDto`
reachable *only* transitively, proving the BFS actually walks member
references, not just direct page-field references), `IsAdmin: true`
(literal → value type → auto-non-nullable via `ValueTypeDefaultProvider`,
no `--nrt-unknown-policy` involvement at all), `Bio: 'hello'` (string
literal), `Meta: new MetaDto` (the no-parens constructor form from
§24.2), and `Note: SomeHelper()` (a method call — deliberately
unresolvable, proving the diagnostic-and-`unknown` fallback rather than
a crash or a wrong guess). `UnusedDto` is declared but referenced by
nothing reachable, proving the BFS filter actually filters instead of
just falling back to whole-assembly behavior. Two cases (`default`,
`non-null`) confirm the synthesized `Props.ProfileProps` interface's
*unannotated* member (`Note`, and `Role`'s reference-typed field) tracks
`--nrt-unknown-policy`, while `IsAdmin` stays non-nullable under both.

**Correction (2026-08-07, §29): the claim in the previous version of this
paragraph — that `RoleDto`/`UserDto`/`MetaDto`'s properties "correctly
track `--nrt-unknown-policy`" — was wrong, and wrong in a way that
rationalized a real bug instead of catching it.** `RoleDto.Name`,
`UserDto.Email`, and `MetaDto.Title` are all explicitly annotated `not
nullable` in this fixture's source — per §21/README's central NRT
promise ("an explicit annotation always wins regardless of policy"),
they should never have varied with `--nrt-unknown-policy` at all. That
they visibly did was the symptom of the scanner bug §29 fixes, not
confirmation of correct behavior. Caught by an external (Fable5)
consistency review, not by this fixture doing its job — see §29 for the
bug, why the `non-null` case specifically couldn't have caught it, and
the fix.

Verified hands-on before locking in snapshots (same discipline as every
fixture this session): ran `tsgen --mode inertia` directly, read the
output by eye — this is what caught the namespace bug in §24.3 — then
`tools/run-tests.ps1 -UpdateSnapshots` followed by plain
`tools/run-tests.ps1`. **14/14 cases pass** across all six fixtures;
`git diff` on the five pre-existing fixtures' snapshots is empty — the
`--mode` addition, `IrBuilder` refactor, and `OxygeneTokenizer`
extraction changed nothing about the existing whole-assembly path's
output.

`ProfileProps`'s name comes from `SanitizePropsTypeName`: take the
component name's last `/`-separated segment (`"pages/Profile"` →
`"Profile"`), strip non-alphanumeric characters, append `"Props"`. This
is one reasonable v1 answer to `docs/DESIGN.md` §7.4's still-open "exact
naming/output-file convention is TBD" — not a settled decision; revisit
if it doesn't hold up against real component-naming conventions.

### 24.6 Known v1 limitations (by design, not oversights)

Matches what §22.6 scoped in advance, now confirmed against real code
rather than just planned:

- **`new class(...)` anonymous-literal prop values are not supported** —
  fall back to `unknown` + a diagnostic naming the key, per this
  section's opening scope decision. Supporting them means synthesizing
  an on-the-fly named IR type per literal, a distinct and larger piece
  of work than anything else here.
- **No cross-method/cross-class props construction** — the props
  variable must be declared and populated in the *same* method as the
  `Inertia.Render` call. A props dictionary built by a helper method and
  passed in, or populated across multiple methods, isn't tracked.
- **No conditional/branch-dependent key-setting awareness** — the
  scanner doesn't know or care whether a `props['X'] := ...;` statement
  is inside an `if`/`else`; it just accumulates every assignment to a
  tracked variable it sees, in whichever order the tokens appear.
- **No `Inertia.Defer(...)`/`Inertia.Merge(...)` unwrapping** — a value
  wrapped in either resolves to whatever `ResolveValueExprType` makes of
  the *whole* wrapped expression, which (being a method call, not a
  literal/identifier/`new`) will be `unknown` today. The real type is
  the async lambda's return type — its own smaller follow-up spike if
  pursued (§22.6 already flagged this).
- **No dynamic/computed keys** — only a literal string token directly
  inside `[...]` is recognized as a key.
- **Short-name type resolution can collide** — `ResolveTypeName`/the
  scanner's known-types lookup is keyed by a type's bare `Name`, not its
  full `Namespace.Name`; two same-named types in different namespaces
  within the target assembly would resolve to whichever was registered
  last. Not exercised by the fixture (single-namespace); worth a
  dedicated regression fixture before relying on this in a
  multi-namespace real project.

**Update (2026-08-13)**: the original v1 scope also excluded
generic-typed locals ("generic-typed parameters/locals" in the
scanner's own doc comment) — colon-annotated generic LOCALS
(`var x: List<Foo> := ...;`, the List/Dictionary/... families) are now
resolved, see §39. Generic method PARAMETERS and everything listed
above still stand as scoped out.

---

## 25. Self-review fix: CLI arg parsing had no bounds checking (Windows hands-on, 2026-08-02)

Found via a deliberate self-review prompted by the user asking whether
this session's code showed typical AI-generated-code failure patterns
(inconsistent rigor, over-defensive coding, dependency optimism, security
gaps, outdated idioms) — not found by any test, since no fixture
exercises malformed CLI invocations, only malformed/edge-case Oxygene
source.

**The bug**: `Program.pas`'s argument-parsing loop did `inc(i); x :=
args[i];` for every flag taking a value (`--assembly`, `--source`,
`--out`, `--enum-style`, `--nrt-unknown-policy`, `--mode`), with no
`(i < args.Length)` guard. `tsgen generate --assembly` with nothing
following crashed with an unhandled `IndexOutOfRangeException` and a raw
.NET stack trace instead of a clean CLI error message.

**Worth naming as a real inconsistency, not just a bug**: the same
session's `InertiaScanner.pas` (§24) guards nearly every token-list
access with `(i < aTokens.Count)` — meticulous bounds-checking in the
token-scanning code, none at all in the CLI's own argument parsing. Same
codebase, same session, two very different levels of rigor depending on
which kind of "user input" (Oxygene source vs. command-line flags) was
being handled — a concrete instance of the "consistency varies across a
session" pattern the user asked about.

**Fix**: track a `missingValueFor: String` sentinel; each flag branch
sets it instead of indexing out of bounds when its value is missing, and
the loop exits with `Error: --flag requires a value.` (exit code 1)
instead of continuing. Verified hands-on, not just by re-running the
existing suite: `tsgen generate --assembly` (and separately
`--nrt-unknown-policy`/`--mode` with no value) now print the clean error
and exit 1; the full snapshot suite still passes 14/14 unchanged,
confirming no regression to normal, well-formed invocations. No new
automated fixture added for the error path itself — `tools/run-tests.ps1`
is built around "build an assembly, run `tsgen` against it," not
malformed-invocation testing, and adding that infrastructure for one
narrow fix wasn't judged worth it this round (manual verification is
straightforward and was actually done, unlike some past instances in
this project where "should work" was asserted without checking).

**Separately noted during the same review, not yet fixed**: an
`InertiaScanner.UnquoteStringLiteral` correctness claim in §24.2 turned
out to be one degree short of what was actually verified —
`GetString()`/`GetOriginalString()` not un-quoting was confirmed
hands-on, but the `Replace('''''', '''')` un-escaping logic itself was
never exercised by any fixture (`tests/fixtures/InertiaMode`'s string
literals contain no embedded escaped quotes). Verified during this same
review, via a disposable scratchpad probe tokenizing `'it''s'`: correctly
unescapes to `it's` (4 chars). No code change needed — this was a
documentation-precision gap (claiming more verification than had
actually happened), not an actual bug. Worth remembering as its own
lesson: "confirmed hands-on" claims in this file should name exactly
what was tested, not the general area.

### 25.1. Remaining categories from the same self-review

The user's prompt named five typical AI-generated-code failure patterns.
Two are covered above (inconsistent rigor → the bug fix; dependency
optimism → the `UnquoteStringLiteral` note). The other three were also
checked, with no code change resulting, but the conclusions are worth
keeping on record so a future session doesn't have to re-derive them:

- **Over-defensive coding**: no notable instances found. If anything the
  session leaned the opposite way (see the bug above) — each feature was
  scoped to what was actually asked for, without piling on unrequested
  edge-case handling, so this category didn't manifest as excess either.
- **Security gaps**: low relevance for this project's actual threat
  model — `tsgen` is a local CLI with no secrets, no IAM, no SQL. The one
  candidate, `--assembly`/`--source` taking unvalidated file paths, was
  judged not worth guarding: the tool only ever points at the invoking
  user's own machine/assembly/source, so there's no privilege boundary
  being crossed by not validating the path.
- **Outdated idioms**: not literally "deprecated API usage" (nothing in
  this codebase is old enough for that), but a close relative of it
  surfaced twice — silently assuming a C#-familiar syntax would carry
  over to Oxygene. Both instances are already documented elsewhere and
  are cross-referenced here rather than repeated: the object-initializer
  syntax that silently no-ops (§22.3) and the non-nesting `{ }` comment
  bug hit twice (§23.6, §24.3; also called out as a standing gotcha in
  `CLAUDE.md`). Same root cause both times — training-data familiarity
  with C# leaking into assumptions about Oxygene syntax — so treat any
  new "this should just work like in C#" assumption as a place to verify
  hands-on first, not a third instance to add here.

## 26. Form/`useForm()` error type implemented (docs/DESIGN.md §2.6 item 3 / §5.4, 2026-08-07)

Of the three Inertia-specific type-generation targets scoped in §2.6
(Page Props, Shared Data, Form/`useForm()` errors), only Page Props had
been implemented (§24). This closes the second of the two remaining
items — Form/`useForm()` errors — leaving only Shared Data types open.

**Scope decision (asked of the user before implementing, since §5.4
explicitly left this open)**: field names for the error-shape type are
sourced from the *same* field list already resolved for the
corresponding page's Props type, not from a separate scan of a POST
action's request-DTO `[Required]`/etc. attributes. The latter is closer
to how `useForm()` is actually used in real Inertia apps, but would
require a whole new entry-point-discovery mechanism (finding the POST
action that handles a given page's form submission and correlating it
back to the page) — a materially bigger feature. Reusing the Props
field list needs zero new scanning: `InertiaIrBuilder.Build` already has
the exact `page.Fields` list in hand right after building the Props
type. This is the same kind of "one reasonable v1 choice, not a settled
decision" call already made for Props type naming (§22.6/§24, §7.4 still
open) — revisit if/when Shared Data or a real request-DTO scan is built
and a natural correlation mechanism exists.

**Output shape**: `export type ProfileFormErrors = Partial<Record<'User'
| 'IsAdmin' | ..., string>>;` — a plain TypeScript type alias, not an
`interface`. This needed a third `IrTypeLite.Kind` value,
`FormErrorsLike` (`src/Tsgen/Ir/IrModel.pas`), alongside the existing
`ClassLike`/`EnumLike`, since neither existing emission path fits: it's
not an object shape (interface) and not a fixed enum. `Members` is
reused for the field-name list only — `TypeRef`/`Nullability` are set on
`ClassLike` members but simply never populated for `FormErrorsLike` ones
(`DtsEmitter.EmitType` never reads them for this kind).

**The empty-fields edge case is real, not speculative**: `InertiaScanner.pas`'s
own `ParseRenderCall` comment already documented that a page can
legitimately have zero fields (props variable declared, never assigned
before `Inertia.Render`). A union of zero string literals isn't valid
TypeScript syntax, so `DtsEmitter.EmitType` special-cases `Members.Count
= 0` to emit `Partial<Record<never, string>>` instead — `Record<never,
V>` is valid TS for "no keys." Added a second page (`Empty`, no field
assignments) to `tests/fixtures/InertiaMode/InertiaMode.pas` specifically
to exercise this path in the snapshot suite rather than leaving it
manually-verified-only.

**Naming/placement**: `SanitizePropsTypeName`'s prefix logic was
factored out into `SanitizeComponentBaseName` and reused by a new
`SanitizeFormErrorsTypeName` (suffix `FormErrors` instead of `Props`),
so `pages/Profile` yields both `ProfileProps` and `ProfileFormErrors` —
visibly paired names. Kept in the same `'Props'` namespace as the Props
types (not a separate namespace) since the two are always emitted
together per page; same "placeholder, not settled" caveat as the
namespace choice itself (§24, §7.4).

**Verification**: rebuilt via `tools/dev-build.ps1`, regenerated
`InertiaMode` fixture snapshots via `tools/run-tests.ps1
-UpdateSnapshots`, and read the actual diff by eye before trusting it
(`git diff -- tests/fixtures/InertiaMode/expected/`) — confirmed only
`InertiaMode`'s two snapshots changed (all other fixtures byte-identical
after the blanket regeneration) and that both the multi-field
(`ProfileFormErrors`) and zero-field (`EmptyFormErrors`) cases render
correctly. Full suite re-run afterward: 14/14 pass.

## 27. Shared Data type implemented (docs/DESIGN.md §2.6 item 2 / §7.1 / §8.2, 2026-08-07)

This is the last of §2.6's three Inertia-specific type-generation targets
(Page Props §24, Form/`useForm()` errors §26, now Shared Data) —
`--mode inertia` no longer has any target left unimplemented from that
list.

**A spike came first, deliberately, run on a different model.** §8.2
already named the open problem: Shared Data must be discovered from "the
ASP.NET Core Inertia middleware's `share()`-equivalent registration," but
*how* to reliably locate it "is itself unresolved and depends on which
adapter is chosen." Since the adapter (InertiaNetCore) was already fixed
(§11 item 6) but its actual Share API had never been looked up, this
carried real "dependency optimism" risk (the self-audit category from
§25.1) if implementation started from assumption. A background Opus 5
agent was launched (Sonnet 5 stayed the primary model for this
conversation, per `CLAUDE.md`'s model-selection guidance recommending
Opus for algorithmically/API-research-hard cores) with instructions to
research InertiaNetCore's real Share API via WebSearch/WebFetch against
its actual GitHub source and NuGet package, build a hands-on Oxygene
probe verifying detectability via `TokenStream` (the same standard §22.4
held itself to), and report back — not to implement anything. Its full
report is reproduced in this session's history; only the load-bearing
conclusions are repeated here.

**What the spike found, verified against InertiaNetCore's own source
(not assumed from Laravel/Rails Inertia conventions)**:
- The real API is `Inertia.Share(key, value)`, `Inertia.Share(props)`,
  and `AddInertiaSharedData(Func<HttpContext, InertiaProps>)` /
  `AddInertiaSharedData(Func<HttpContext, Task<InertiaProps>>)` — no
  interface, attribute, or DI-registered type exists for reflection to
  find; source-level scanning is the only path, same conclusion as Page
  Props (§22.5).
- `AddInertiaSharedData` is startup-time pipeline middleware
  registration (`app.Use(...)` under the hood) — a fixed, scannable call
  shape. A bare `Inertia.Share(key, value)` call, though, is used by
  InertiaNetCore for BOTH app-global shared data AND a single page's own
  extra prop — the call shape alone cannot distinguish the two. This is
  a materially harder classification problem than anything Page Props
  faced, where `Inertia.Render` is unambiguous by construction.
- Three keys (`flash`, `timestamp`, `errors`) are injected into every
  page's payload by InertiaNetCore's own `Response.GetFinalProps`
  regardless of whether the app registers any shared data at all.
- The probe confirmed all of this is token-detectable with **zero new
  token IDs** beyond what `InertiaScanner.pas` already declares — the
  lambda passed to `AddInertiaSharedData` is just another nested
  `begin...end` block one level deeper inside a method body, which the
  existing `depth`/`methodBodyDepth` bookkeeping already handles
  correctly.
- The `{ }`-initializer trap (§22.3) recurs here in a worse form: writing
  InertiaNetCore's own README-style `AddInertiaSharedData(ctx ->
  new InertiaProps { ['key'] := value })` compiles and silently empties
  the shared payload for the ENTIRE app, not just one page's props.

**Scope decisions made from the spike's open-questions list, asked of
the user before implementing (not decided silently — matching this
project's standing practice)**:
- **Classification policy**: conservative v1 — only
  `AddInertiaSharedData(...)` registrations count as shared data. A bare
  `Inertia.Share(...)` call is detected but excluded, with a diagnostic
  naming it, rather than guessed at via a "no `Inertia.Render` in the
  same method" heuristic (the spike's alternative option), which would
  catch more real patterns but risks misclassifying a page's own prop as
  global. The user asked to keep this switchable later via a CLI flag —
  noted here as a real, deliberately-deferred follow-up, not implemented
  this round (no flag exists yet; `ParseShareCallExcluded` is the single
  place that would need to branch on one).
- **Framework floor keys**: always emit `flash`/`timestamp`/`errors` in
  `SharedData`, regardless of whether any registration was found —
  matches actual runtime behavior. Same "make it a flag later" follow-up
  noted, not built yet.
- **Merge representation**: `interface XxxProps extends Props.SharedData`
  (an inheritance clause), not the literal `type XxxProps = SharedData &
  T` intersection §2.6/§8.2/§7.1 originally described. Chosen because it
  needed no new `IrTypeKindLite` value or emitter branch (`IrTypeLite`
  just grew a `BaseTypeNames: List<String>`, and `DtsEmitter.EmitType`
  appends `' extends ' + ...` to the existing interface-header line), and
  because on a field-name collision `extends` is a TypeScript **compile
  error** rather than the intersection form's silent collapse to `never`
  — arguably more honest given shared data actually **overwrites**
  same-named page props at runtime in InertiaNetCore
  (`InertiaProps.Merge`, confirmed in the spike). `docs/DESIGN.md`
  §2.6/§7.1/§8.2 need a follow-up edit to describe this instead of the
  original intersection-type sketch.
  **Done, same session, right after this section was written** — the
  `extends`-based rewrite of §2.6/§7.1/§8.2 landed (English and
  `DESIGN_jp.md` mirror both), but this flag itself was never updated to
  say so, leaving it reading as outstanding debt after the edit had
  already happened. Caught by the §29 Fable5 review, not by re-reading
  this section — a small instance of the same "update the doc, forget to
  update the note that pointed at the doc" class of drift the rest of
  §29 is about.
- **camelCase key/property-naming gap**: the spike also surfaced,
  incidentally, that InertiaNetCore's default `JsonSerializerOptions`
  camelCases both dictionary keys and POCO property names, so this
  tool's existing output (`User`, `IsAdmin`, etc., verbatim from Oxygene
  source casing) doesn't match what a default-configured app actually
  sends. This is a **pre-existing bug in the already-shipped Page Props
  feature** (§24), not something Shared Data introduces, and out of
  scope for this section's diff. The user asked for it to be tracked as
  a separate issue rather than fixed here — see the issue-tracker CSV
  row for this session's phase.

**Implementation** (`src/Tsgen/Inertia/InertiaScanner.pas`,
`InertiaIrBuilder.pas`, `src/Tsgen/Ir/IrModel.pas`,
`src/Tsgen/Emit/DtsEmitter.pas`, `src/Tsgen/Cli/Program.pas`):
- New `InertiaSharedData` class (`Fields: List<InertiaPropsField>`),
  deliberately mirroring `InertiaPageProps`'s shape so
  `InertiaIrBuilder` can convert both kinds of field list through the
  exact same per-field IR-conversion code.
- `ScanFile` gains three pieces of state — `sharedRegionActive`,
  `sharedRegionEntryParenDepth`, `sharedRegionKnownVars` — to track an
  active `AddInertiaSharedData(...)` call's argument span. On detecting
  `IDENT . AddInertiaSharedData (` (the `.`-prefix guard avoids matching
  a bare declaration, cheap insurance found worth adding during the
  spike's own probe), it snapshots which props vars already exist; on
  the matching `)` (parenDepth returning to the value it had right
  before the call's own `(`), it diffs `propsFields.Keys` and adds every
  *newly*-declared props var's fields to `aSharedData.Fields`. This
  deliberately does NOT parse the lambda's `exit ...;` statement to find
  which var is returned — every registration shape the spike's probe
  confirmed compiles declares its own props var inline and returns it
  directly, so "new var declared inside the region" and "the var actually
  returned" coincide for every case tested. A var declared *outside* the
  call and merely referenced inside it would be missed by this heuristic
  — an accepted v1 gap, same style as the existing "props built across
  multiple methods" gap for Page Props (§24.6).
- A parallel `Inertia . Share (` detection (`ParseShareCallExcluded`)
  warns and skips to the matching `)` without attempting to resolve
  anything — the conservative-policy decision above needs no key/value
  parsing at all for the excluded path.
- **Known interaction not defended against**: `ParseShareCallExcluded`
  and `ParseRenderCall`'s own skip-loops consume tokens (including their
  own parens) without updating `ScanFile`'s outer `parenDepth` counter —
  harmless before this feature (nothing read `parenDepth` outside its own
  increment/decrement), but now that shared-region-close detection
  compares against a saved `parenDepth` value, an `Inertia.Share(...)` or
  `Inertia.Render(...)` call occurring *inside* an
  `AddInertiaSharedData(...)` registration's lambda body could throw off
  the region-close match. Judged unlikely enough in real code (why would
  a shared-data registration itself render a page or share a single
  prop) not to defend against this round; flagging the reasoning here
  rather than silently ignoring it.
- `IrTypeLite` gains `BaseTypeNames: List<String>` (default empty,
  meaningful only for `ClassLike`); `DtsEmitter.EmitType` appends
  `' extends ' + ...` to the interface header when non-empty.
- `InertiaIrBuilder.Build` now takes an `aSharedData: InertiaSharedData`
  parameter, hand-constructs `RawTypeRef`s for the three floor keys
  (`System.DateTime` for `timestamp`; a hand-built
  `System.Collections.Generic.Dictionary\`2` of `String,String` for
  `flash`/`errors` — `TypeMapper.MapTypeRef` already renders that as
  `Record<string, string>`, confirmed by reading `TypeMapper.pas`, not
  assumed), builds one `SharedData` `IrTypeLite` in the `'Props'`
  namespace (same placeholder-namespace caveat as Props/FormErrors,
  §24/§7.4), and adds `'Props.SharedData'` (fully qualified, matching
  `TypeMapper`'s own "always fully qualify" convention even though
  same-namespace) to every page's `BaseTypeNames`. The reachability BFS
  that decides which of the target assembly's own types get emitted was
  seeded with `aSharedData.Fields`' types too, not just each page's own
  fields — otherwise a shared field's own type (e.g. `Auth:
  AuthUserDto`) would fall to `unknown` instead of being emitted and
  referenced.
- `Program.pas`: creates one `InertiaSharedData` before scanning,
  threads it through `InertiaScanner.Scan` (now takes it as an in/out
  accumulator parameter, same pattern as the existing `aResult:
  List<InertiaPageProps>` parameter — no `out` keyword needed since it's
  a reference type) and into `InertiaIrBuilder.Build`.

**Fixture**: extended `tests/fixtures/InertiaMode/InertiaMode.pas` rather
than adding a new fixture, since Shared Data only makes sense evaluated
together with existing pages. Added: `HttpContext`/`AppBuilder` stand-ins
(a plain method, not an `extension class(IApplicationBuilder)` — the
scanner only cares about the call shape `IDENT . AddInertiaSharedData
(`, not how the method was declared, so a plain method sidesteps needing
to get Oxygene's extension-class syntax exactly right for something the
scanner doesn't inspect anyway), a `SharedUserDto` reachable ONLY via the
shared-data registration (proving the reachability-seeding fix above), a
`Startup.Configure` method registering shared data via the exact
statement-lambda-with-`exit` shape the spike's probe confirmed compiles,
and an `Inertia.Share(...)` call added to the existing `Empty` page
method (proving the exclusion path without needing a whole new method).
Rebuilt, ran the full suite to see the actual diff before regenerating
anything, then regenerated snapshots and read the resulting `.d.ts` by
eye (both `default.d.ts` and `non-null.d.ts`) to confirm `SharedData`,
the `extends` clauses, and `SharedUserDto`'s presence in the `InertiaMode`
namespace are all syntactically valid, sensible TypeScript — not just
"the diff updated." Full suite: 14/14 pass.

## 28. Fix issue #55: camelCase naming policy, both modes (2026-08-07)

Closes issue-tracker item #55, found incidentally during the §27 Shared
Data spike: InertiaNetCore's default `JsonSerializerOptions` camelCases
both dictionary keys and POCO property names, so Page Props output
emitted verbatim Oxygene-source casing (`User`, `IsAdmin`, ...) didn't
match the real wire payload (`user`, `isAdmin`, ...). `docs/DESIGN.md`
§5.1 always described this as a general "simulate the `JsonNamingPolicy`
setting" concern — not Inertia-specific — but it had never been
implemented for either mode.

**Scope decisions (asked of the user before implementing)**: apply to
both `--mode assembly` and `--mode inertia` (one implementation point,
`DtsEmitter.EmitType`, matches §5.1's original general framing rather
than treating this as an Inertia-only patch); add it as a new
`--naming-policy camelCase|as-written` flag, **defaulting to
`camelCase`** rather than keeping the old as-written behavior as
default — the old default was the actual bug, not a stylistic choice
worth preserving by default, and `camelCase` matches what
ASP.NET Core/`System.Text.Json` themselves default to when a project
doesn't reconfigure `JsonSerializerOptions`.

**Implementation** (`src/Tsgen/Emit/DtsEmitter.pas`,
`src/Tsgen/Cli/Program.pas`): new `NamingPolicy = public enum (AsWritten,
CamelCase)`, an `ApplyNamingPolicy`/`ToCamelCase` helper, threaded
through `DtsEmitter.Emit`/`EmitType` and applied at both places a JSON
property name actually gets emitted: `ClassLike` interface members, and
`FormErrorsLike`'s `Record<'key1' | 'key2', string>` key literals (these
must stay consistent with each other — `ProfileFormErrors`'s keys
describe the *same* fields `ProfileProps`'s members do, so both needed
the same transform or they'd silently disagree). Deliberately NOT
applied to: type/interface names themselves (`ProfileProps`,
`SharedData`, etc. are TypeScript-side identifiers, not JSON payload
keys) or `EnumLike` value names (`System.Text.Json`'s enum string
conversion is controlled separately, by `JsonStringEnumConverter`'s own
naming policy parameter, not `PropertyNamingPolicy` — confirmed this is
a real, separate mechanism, not assumed). The unmapped-type diagnostic
message still names the as-written source name, not the transformed
one, since diagnostics should point back to where the user should look
in their own source.

**`ToCamelCase` is a simplified stand-in, not a port of
`JsonNamingPolicy.CamelCase.ConvertName`**: it lowercases only the first
character. Correct for every ordinary PascalCase Oxygene identifier —
which is the only shape this codebase's own fixtures/DTOs use — but does
not replicate the real algorithm's acronym-run handling (e.g. a property
literally named `ID` or `URLPath`). A deliberate, documented v1 gap
rather than porting that logic now, matching this codebase's existing
risk tolerance for heuristic limitations (e.g. `InertiaScanner`'s
short-name collision note, §24.6).

**A second, unrelated bug was found while verifying this fix, and fixed
alongside it**: `tools/run-tests.ps1`'s snapshot comparison used
PowerShell's `-eq` operator, which is **case-insensitive for strings by
default** (`"Id" -eq "id"` is `$true` in PowerShell — confirmed hands-on,
not assumed). This meant the ENTIRE snapshot suite could never have
caught a case-only regression, including this very fix: the first
`tools/run-tests.ps1` run after implementing `--naming-policy` reported
14/14 PASS even though the actual output was camelCase and every
committed snapshot was still PascalCase. Caught only because the output
still "looked green" was suspicious given the size of the change — a
manual `diff` against a preserved `_actual/` directory (a temporary
debug copy of the script with its cleanup step disabled) confirmed the
files genuinely differed while the script still reported PASS. Fixed by
changing the comparison to `-ceq` (ordinal/case-sensitive). This is the
kind of bug that specifically hides behind "the tests still pass" — worth
remembering that a green snapshot suite was never actually verifying
casing, for the whole lifetime of this test runner (`HANDOFF.md` §15),
not just for this one fix.

**Fixture**: added an `as-written` case to
`tests/fixtures/SampleModel/cases.json` (`--naming-policy as-written`)
to prove the opt-out actually restores the old PascalCase behavior, not
just that camelCase-by-default works. Regenerated all snapshots (now 6
fixtures / 15 cases, one new case) with the case-sensitive comparison
already fixed, then read every changed file's diff by eye — confirmed
type/interface names stay untouched, only member/property names and
`FormErrorsLike` key literals change, `SharedData`'s already-lowercase
floor keys (`flash`/`timestamp`/`errors`) are unaffected (case-insensitive-safe
no-op through the same code path), and enum value names
(`Active`/`Inactive`/`Pending` in `SampleModel`) are correctly untouched.
Full suite: 15/15 pass.

## 29. Fable5 consistency review (2026-08-07): a real NRT-scanner bug, plus doc drift

With a commit/push deadline approaching, asked a background Fable5 agent
to review the whole project — design phase onward, weighted toward the
most recently implemented Inertia features (§24-§28) — for internal
inconsistencies, contradictions between documentation and actual
behavior, and irrational decisions, the same kind of review this project
has used twice before early on (§9/§13-era) to catch things the
implementing model misses in its own work. It found one load-bearing
bug and several stale cross-references. This section covers the bug;
the doc fixes were applied directly to `README.md`/`docs/DESIGN.md`
without a separate writeup (small, mechanical corrections — no new
information/decision to record beyond "this was stale, now isn't").

**The bug: `NullabilityScanner.IsTypeOpen` mistook a static member's
`class` keyword for a type declaration.** Oxygene's static-member
modifiers (`class method`, `class var`, `class property`, `class
constructor`, `class operator`) reuse the `class` keyword — the same
token `ScanFile` watches for to detect `TypeName = ... class` type
declarations. `IsTypeOpen`'s backward walk (stopping only at `;`/
`begin`/`end`) had no way to tell the two apart: for a type whose
*first* member after the visibility section header is a `class
method`/etc. (no semicolon yet since the header itself doesn't end in
one), the walk sailed straight through that `class` token, back through
the type's own `class`/visibility tokens, and reached the *enclosing*
type's own `TypeName = ` equals sign — reporting a second, spurious
type-open. That extra `inc(depth)` was never matched by a corresponding
decrement (a static method's own `class` keyword doesn't open a `begin
...end` block of its own), so `depth` stayed permanently offset by one
for the rest of the file. Because `currentTypeName`/`typeDepth` are only
(re)assigned `if String.IsNullOrEmpty(currentTypeName)`, and
`currentTypeName` was already non-empty from the first (real) type, no
type declared afterward in the same file ever got its properties/fields
scanned — every one silently failed the `(depth = typeDepth)` guard
already added after the §20 nested-type bug, so they degrade to
`Unknown` rather than corrupting another type's entry. Concretely: in
`tests/fixtures/InertiaMode/InertiaMode.pas`, the `Inertia` class's
`class method Render`/`class method Share` (its very first members)
trip this, and every type declared afterward in that file
(`RoleDto`/`UserDto`/`MetaDto`/`SharedUserDto`/`Controller`/`Startup`)
loses NRT scanning for the rest of the file. Any real target codebase
with an ordinary static helper class ahead of other types in the same
file — an unremarkable, common Oxygene pattern — hits this too; it's
not specific to this fixture's shape.

**Why the snapshot suite didn't catch it, and actively hid it**:
`RoleDto.Name`/`UserDto.Email`/`MetaDto.Title`/`SharedUserDto.Email` are
all explicitly `not nullable` in the fixture. With their annotations
lost to the bug, they fell back to genuinely `Unknown`, which
`--nrt-unknown-policy`'s default (`nullable`) renders as `T | null` —
wrong, but the `default` case's own committed snapshot had simply
baked in the wrong (post-bug) output as "expected," so it passed. The
fixture's `non-null` case — the one CLAUDE.md's own standing rule says
every NRT fixture needs specifically to distinguish "genuinely Unknown"
from "a leaked/lost annotation" —*also* couldn't catch it here, for a
sharper reason than the usual "both render `| null`" case CLAUDE.md
already documents: under `non-null` policy, `Unknown` renders as bare
`T`, which is *identical* to what a correctly-recognized `not nullable`
member renders as. The two cases that exist were exactly the pair that
happens to agree on this bug's output. `HANDOFF.md` §24.5 additionally
rationalized the wrong behavior as a passing test's success criterion
("confirm the reachable types … correctly track
`--nrt-unknown-policy`") — corrected in §24.5 above, not rewritten
silently.

**Fix** (`src/Tsgen/Nrt/NullabilityScanner.pas`, `IsTypeOpen`): added a
forward lookahead — if the token immediately after a candidate `class`
is `method`/`var`/`property`/`constructor`/`operator`, it's a
static-member modifier, not a type declaration, and `IsTypeOpen` returns
`false` without doing the backward walk at all. `TOK_METHOD`/`TOK_VAR`
reuse the exact same `Token.TI_method`/`Token.TI_var` constants already
confirmed working in `InertiaScanner.pas`; `TOK_PROPERTY` was already
declared in this file; `TOK_CONSTRUCTOR`/`TOK_OPERATOR`
(`Token.TI_constructor`/`Token.TI_operator`) were new and confirmed by
successful compilation, not assumed. Deliberately did NOT change the
backward-walk's stop-token set itself (adding `public`/`private` as stop
tokens was considered and rejected — those keywords appear both as a
type's own visibility modifier, directly before `class`, and as a
standalone member-visibility section header, and are not
distinguishable by token ID alone without the exact context this
lookahead already handles more precisely).

**Verification**: rebuilt (confirming the two new token constants
compile), ran the full suite *before* touching any snapshot — 14/15
passed, with `InertiaMode/default` the only failure, isolating the
fix's effect to exactly the fixture that exercises the pattern.
`InertiaMode/non-null` already passed unchanged (consistent with the
mechanism above — that case couldn't distinguish the bug from correct
behavior either way). Regenerated snapshots, then read
`InertiaMode/expected/default.d.ts` by eye: `name`/`email`/`title` now
correctly render without `| null` regardless of policy, while
`role: InertiaMode.RoleDto | null` (genuinely unannotated) still
correctly tracks the policy. Full suite: 15/15 pass.

No new fixture added — `InertiaMode`'s existing `Inertia` class already
exercises the exact trigger pattern (`class method` as a type's first
member) and now genuinely regression-tests it, since `default`'s
snapshot would fail again if this regressed.

## 30. Fable5 review, Findings 6-9 (2026-08-07, same day, before the commit deadline)

With time still available before the day's commit/push window, addressed
the remaining four (lower-severity) findings from the §29 review rather
than leaving them recorded-but-deferred.

**Finding 6 (bookkeeping)**: §27's own text said the `docs/DESIGN.md`
§2.6/§7.1/§8.2 `extends`-rewrite was "not done in this pass" — but it
*was* done, later in that same session, and the flag was just never
updated to say so. Fixed by editing the flag in place (§27 above) rather
than treating it as new work.

**Finding 7a (real bug, fixed): a discovered Shared Data field can
collide with `SharedData`'s own hardcoded floor keys after the
naming-policy transform.** E.g. a target app registering
`shared['Flash'] := ...` via `AddInertiaSharedData(...)` would, under
the default `camelCase` policy, produce a second `flash` member
alongside `SharedData`'s own framework-injected `flash: Record<string,
string>` — a TypeScript "duplicate identifier" compile error in the
generated `.d.ts`, since interface members must be unique within one
declaration (unlike the `extends`-collision case between a page's Props
and `SharedData`, which is a *different*, deliberately-kept compile
error per §27). Fixed in `DtsEmitter.EmitType`'s `ClassLike` branch: a
`HashSet<String>` tracks names already emitted for the *current*
interface (post-naming-policy-transform); a later member whose
transformed name repeats an earlier one is skipped and reported via
`aDiagnostics.AddWarning(...)` instead of emitted, keeping the output
always-valid TypeScript. Deliberately scoped to one `EmitType` call (one
interface's own `Members` list) — not extended across the `extends`
boundary, which stays a compile error on purpose. Since floor keys are
added to `SharedData.Members` before any discovered field
(`InertiaIrBuilder.Build`), "skip the later duplicate" also happens to
match InertiaNetCore's real runtime precedence for this exact case: the
spike (§27) found `Response.GetFinalProps` applies `AddFlash(...)`/
`AddTimeStamp()` *after* merging in registered shared data, so the
framework-injected value overwrites a same-named registered field at
runtime too — not a coincidence chosen for convenience, verified against
the same spike finding §27 already relied on.

Added a real regression case for this rather than trusting the reasoning
alone: `tests/fixtures/InertiaMode/InertiaMode.pas`'s `Startup.Configure`
now also registers `shared['Flash'] := 'collides-with-floor-key'`.
Rebuilt and ran the suite *before* touching snapshots — confirmed the
diagnostic fires (`duplicate member "flash" on SharedData after
naming-policy transform (source name "Flash")`) and that
`InertiaMode/default`/`non-null` still **passed unchanged**, proving the
collision is silently and safely dropped from output rather than
corrupting it (diagnostics aren't part of the compared `.d.ts`, so a
correctly-handled collision changes nothing in the snapshot — the
absence of a snapshot diff here is itself the confirmation the fix
works, not a sign nothing happened).

**Finding 7b (investigated, no code change needed — the existing
behavior turned out already correct)**: the review asked whether
`SharedData`'s three floor keys (`flash`/`timestamp`/`errors`, always
lowercase) staying lowercase under `--naming-policy as-written` was
actually a hidden inconsistency, given `as-written` reverts every other
member back to Oxygene source casing. Worked through why it isn't: (1)
`as-written` has no Oxygene source declaration to preserve the casing
*of* for these three — they're synthetic, never scanned from real
source, so "as written" is meaningless for them; the tool's own
consistent behavior is "always their real wire name." (2) Even setting
that aside, `DtsEmitter`'s `camelCase` transform only lowercases a
member's *first character* — a no-op on an already-all-lowercase single
word like `flash`/`timestamp`/`errors` — so this is unaffected by
*either* naming-policy value regardless, for any realistic
`JsonSerializerOptions.DictionaryKeyPolicy` an app might configure
(`None` or `CamelCase` both leave these three exact strings unchanged;
only a policy that *uppercases* an already-lowercase key — which no
built-in `JsonNamingPolicy` does — would disagree). Documented this
reasoning directly in `InertiaIrBuilder.pas` next to the floor-key
construction rather than leaving it as an unstated assumption, since the
review was right that it hadn't been stated anywhere before.
`tests/fixtures/InertiaMode/expected/as-written.d.ts` (new, see Finding
9 below) now shows this directly: `flash`/`timestamp`/`errors` stay
lowercase while `Auth`/`AppName`/`Flash` revert to their as-written
Oxygene casing in the same interface.

**Finding 7 (the `errors`-key type-representation tension): documented,
not fixed.** `SharedData.errors: Record<string, string>` and each page's
`XxxFormErrors = Partial<Record<'field1' | 'field2', string>>` (§26)
both describe the same runtime payload key, in two incompatible shapes.
Not resolved this round — `SharedData` is one interface shared by every
page while `XxxFormErrors` is page-specific, and `Record<string,
string>`'s implicit index signature isn't cleanly narrowable to a
fixed-key `Partial<Record<...>>` as a TypeScript interface-member
override, so reconciling this is a real design question (which
representation should win, or whether they should stay separate with a
documented relationship) rather than something to decide unilaterally
under a same-day commit deadline. Flagged in code
(`InertiaIrBuilder.pas`, next to `errorsMember`) and here so it isn't
lost.

**Finding 8 (real gap, fixed): enum-valued CLI flags accepted any
unrecognized value and silently fell through to a default**, instead of
erroring — an inconsistency with the missing-*value* case §25 already
fixed, and a sharper problem given §28 made `--naming-policy`'s default
the behavior-changing one: a typo like `--naming-policy aswritten`
previously silently produced `camelCase` output, the exact opposite of
what the flag was being used to opt out of. Fixed in `Program.pas`: each
of `--enum-style`, `--nrt-unknown-policy`, `--mode`, `--naming-policy`
now explicitly matches its known literal values and sets a new
`invalidFlag`/`invalidValue`/`invalidAllowedValues` sentinel (parallel
to the existing `missingValueFor` one) on anything else, checked right
after the parse loop: `Error: --flag does not accept "value" -- valid
values are: a, b, c` (exit code 1). Verified hands-on, not just by
inspection: `tsgen generate --assembly ... --out ... --naming-policy
bogus` and `--mode bogus` both now print the clean error and exit 1
(previously both would have silently run with a default).

**Finding 9 (test-coverage gap, fixed)**: §28's stated invariant —
`ClassLike` member names and `FormErrorsLike` key literals must transform
consistently under the same naming policy — was only snapshot-tested via
`SampleModel`'s `as-written` case, which has no `FormErrorsLike` type at
all (assembly mode). Added `tests/fixtures/InertiaMode/cases.json`'s own
`as-written` case (`--mode inertia --naming-policy as-written`), giving
the invariant real two-sided coverage. Read the resulting
`expected/as-written.d.ts` by eye: `ProfileFormErrors` correctly reads
`Partial<Record<'User' | 'IsAdmin' | 'Bio' | 'Meta' | 'Note', string>>`
(PascalCase, matching `ProfileProps`'s own reverted member casing) rather
than staying camelCase.

**Verification for the whole section**: rebuilt after each change
(catching two new token-adjacent details immediately via compilation —
nothing guessed), ran the full suite before touching any snapshot to
confirm each change's actual effect first, then regenerated and
read every changed `.d.ts` by eye. Final state: 6 fixtures, **16/16
cases pass**.

## 31. `AssemblyLoader.Load` dependency resolution + crash resilience (2026-08-13)

**Trigger**: `TeaTimeTracker/reports/M3-dts-validation.md` §3.1 — running
`tsgen generate --mode inertia` against the real `TeaTimeTracker.dll`
(the first time tsgen was ever pointed at a multi-assembly real app,
rather than a self-contained fixture) crashed with an unhandled
`System.IO.FileNotFoundException` while resolving
`Microsoft.AspNetCore.Mvc.ViewFeatures` inside `t.IsClass` — no `.d.ts`
was written at all. Two separate root causes, both in
`src/Tsgen/Loading/AssemblyLoader.pas`:

1. `Load`'s `PathAssemblyResolver` search paths were only ever "the .NET
   runtime directory tsgen.exe itself is hosted on" + "the single target
   DLL path" — never the target's own folder (so a sibling dependency DLL
   like `InertiaNetCore.dll`, sitting right next to `TeaTimeTracker.dll`,
   was unreachable) and never any ASP.NET Core shared framework (so
   `Microsoft.AspNetCore.Mvc.Controller`, the base class every MVC
   controller in the app inherits from, was unreachable either).
2. The `for each t in asm.GetTypes() do` loop had no per-type
   `try`/`except` at all, so one type's unresolvable base type crashed the
   entire process instead of just that type being skipped — a direct
   violation of this project's own "pipeline stages report problems via
   `Tsgen.Diagnostics`, not direct console I/O / unhandled exceptions"
   rule (`CLAUDE.md`).

**Fix, both in `AssemblyLoader.pas`**:

- `Load` now builds its resolver path list from four sources, added in
  priority order via a `Dictionary<String, String>` keyed by lowercase
  file name (`AddResolverFile`/`AddResolverDir` — first-registered wins,
  so a higher-priority source is never silently shadowed by a
  lower-priority one shipping a same-named DLL): (1) the target assembly
  itself, (2) every other `*.dll` in the target's own folder, (3) each
  shared framework the target declares via its own
  `<assembly>.runtimeconfig.json` (`runtimeOptions.framework` singular
  and/or `.frameworks` array, both handled — `ParseRuntimeConfigFrameworks`,
  parsed with `System.Text.Json.JsonDocument`; returns an empty list, not
  an error, when the file doesn't exist at all, since library-only
  assemblies — every existing fixture — never get one, only executables
  do), resolved to `C:\Program Files\dotnet\shared\<name>\<version>\` with
  a same-major-version fallback to the highest installed version when the
  exact one isn't present (`PickBestFrameworkVersionDir`, via
  `System.Version` comparison) rather than failing outright, and (4) the
  original runtime-directory addition, kept as the lowest-priority
  fallback for base BCL types (unchanged behavior for that part).
  **Known follow-up (Fable5 review, 2026-08-13):** `DotnetSharedRoot` is
  hardcoded to `C:\Program Files\dotnet\shared` — Windows-default-install
  only. If this tool ever runs on Linux again (it started there, §pre-1)
  or against a non-default dotnet root, derive it from `DOTNET_ROOT` or
  from `RuntimeEnvironment.GetRuntimeDirectory()` (two levels up is
  `shared\Microsoft.NETCore.App\<ver>` → `dotnet\shared`) instead. Small,
  contained; not done now because every current consumer is this machine.
- The type-enumeration loop now wraps each iteration's body in its own
  `try`/`except`: a type whose base-type/property/field resolution still
  throws (e.g. a genuinely unresolvable third-party dependency this tool
  has no way to locate) is skipped individually, with
  `aDiagnostics.AddWarning('skipped type "..." ... ' + E.GetType().Name +
  ': ' + E.Message + ...)` naming the type and the underlying exception,
  plus a trailing aggregate count warning
  (`'failed to resolve N type(s) due to unresolvable dependencies...'`) —
  matching the existing `skippedCount` aggregate-warning pattern already
  used for the filter-based skip case (non-public/nested/generic/
  non-class-non-enum), now sitting alongside it as a second, distinct
  counter (`failedCount`) so the two skip reasons are never conflated in
  diagnostics. `typeLabel` (used in the warning) is captured as the very
  first statement inside the `try`, defended by its own default value
  (`'(name unavailable)'`) in case even `t.FullName` itself is what
  throws.

**Design choice not obviously forced, recorded for future reference**:
resolver-path priority is target-assembly-folder-first, shared-framework
second, hosting-runtime-directory last. This matters if a same-named DLL
ever exists in more than one of these locations (e.g. a self-contained
deployment carrying its own `System.*.dll` copies) — the app's own build
output should win over the ambient framework, which should win over
whatever runtime happens to be hosting tsgen.exe itself. Not currently
exercised by any fixture (TeaTimeTracker is framework-dependent, not
self-contained, so no collision exists to test against); worth a fixture
if this ever becomes a real problem.

**Regression fixture** (`tests/fixtures/ExternalDependency/`): covers
root cause 1's "same-folder dependency DLL" half only — a
`VendorLib.elements` library (`Vendor/` subfolder) defines `VendorBase`
with one property; the fixture's own `ExternalDependency.pas` defines
`Widget = public class(VendorBase)`, so resolving `Widget`'s base type
requires `VendorLib.dll` to be found next to `ExternalDependency.dll`,
which is exactly what root cause 1 made impossible before this fix.
`EBuild`'s `ProjectReference` item did not resolve when tried standalone
outside a `.sln` context, so `ExternalDependency.elements` instead
references `Vendor\Bin\Release\VendorLib.dll` by prebuilt-DLL `HintPath`
with `Private=True` (copies it into `ExternalDependency`'s own
`Bin\Release`, replicating the same-folder shape); `tools/run-tests.ps1`
was extended with a small pre-build step (build any `Vendor\*.elements`
found under a fixture directory before that fixture's own top-level
project) so `VendorLib.dll` is always rebuilt fresh from source, never a
committed (license-prohibited) binary. Confirmed the fixture's `Widget`
interface includes the inherited `vendorId` member
(`vendorId: string | null` — falls back to the `--nrt-unknown-policy`
default since `VendorLib.pas` isn't part of `--source`'s scan, so
`OxygeneSourceScanProvider` has no opinion on it and `String` isn't a
`ValueTypeDefaultProvider` type either; this is the technically-correct
behavior for a real third-party dependency's own unannotated member, not
a bug). Root cause 1's *shared-framework* half and root cause 2 (the
per-type `try`/`except`) have no fixture — library-only test assemblies
never get a `.runtimeconfig.json` to point at a shared framework in the
first place, and root cause 2 only fires for exactly the kind of
resolution failure root cause 1's fix is meant to eliminate — so both were
instead verified by hand against the real `TeaTimeTracker.dll` (below).

**Real-app acceptance run** (the actual M3 blocker this task exists to
fix):

```
tsgen generate --assembly ...\TeaTimeTracker\Bin\Release\TeaTimeTracker.dll --source ...\TeaTimeTracker\src\TeaTimeTracker --out <scratchpad> --mode inertia
```

No longer crashes (exit code 0); full stderr:

```
Loading assembly: ...\TeaTimeTracker\Bin\Release\TeaTimeTracker.dll
Loaded 12 type(s).
Scanning source for NRT info: ...\TeaTimeTracker\src\TeaTimeTracker
Found nullability info for 7 member(s).
Scanning source for Inertia.Render call sites: ...\TeaTimeTracker\src\TeaTimeTracker
Found 5 Inertia.Render call site(s) and 1 shared-data field(s).
Wrote <scratchpad>\index.d.ts
Warning: skipped 5 non-public/nested/generic/unsupported-kind type(s); their members will not appear in the output.
Warning: could not resolve type of Inertia props key "Records" on props -- emitting "unknown" for this field
Warning: could not resolve type of Inertia props key "Count" on props -- emitting "unknown" for this field
Warning: no type mapping for TeaTimeTracker.Models.Rating, emitting "unknown" (1 member(s), e.g. TastingRecordDetail.Rating)
Warning: no type mapping for System.DateOnly, emitting "unknown" (1 member(s), e.g. TastingRecordDetail.BrewedAt)
Warning: no type mapping for (unresolved), emitting "unknown" (2 member(s), e.g. IndexProps.Records)
```

Zero "failed to resolve" warnings — every type in `TeaTimeTracker.dll`,
including its `Controller`-derived MVC controllers, now resolves cleanly
via the new same-folder (`InertiaNetCore.dll`) + shared-framework
(`Microsoft.AspNetCore.App` 10.0.10, read from
`TeaTimeTracker.runtimeconfig.json`) resolver paths. The `Records`/`Count`
(`Integer` alias)/`Rating`/`DateOnly` unknowns and the
`BeverageType`/`ThemeMode` `| null` nullability are exactly the
already-known gaps `docs/DESIGN.md` §7 tasks 1-4 exist to close — this
task's job was only to make the real DLL loadable at all, which it now
is. Note the `.d.ts` was written to a scratchpad directory, not
`TeaTimeTracker/frontend/src/types/generated/`, per this session's
instructions (TeaTimeTracker repo writes out of scope) and separately
observed: `Controller.Profile`-shaped methods that appear twice in
`TeaTimeTracker`'s source (once for `GET`, once for `POST` to the same
Inertia page) currently produce two separate, identical
`EditProps`/`ThemeProps`/`EditFormErrors`/`ThemeFormErrors` declarations
in the output. **Originally logged here as "harmless (TypeScript allows
re-declaring an identical interface) but redundant"** — that was wrong
for half of it: `interface` re-declaration is harmless, but `XxxFormErrors`
is a `type` alias, and TypeScript does NOT allow redeclaring a `type`
alias (a "Duplicate identifier" compile error), so the generated `.d.ts`
actually failed to compile whenever the same component was rendered from
more than one action — a real-world-common pattern (re-rendering a form
on validation failure). **Fixed 2026-08-13, see §37** (Fable5 review
finding on this exact real-DLL run, addressed as an additional task
before this session's other work was considered done).

**Verification**: `tools/run-tests.ps1` (no `-UpdateSnapshots` first, to
confirm the change didn't alter any existing fixture's output — it
didn't, `git diff` on every pre-existing `expected/*.d.ts` was empty)
followed by a `-UpdateSnapshots` run to capture the new
`ExternalDependency` fixture, then a final clean run: **17/17 cases
pass** (was 16/16 before this task's new fixture).

## 32. Oxygene standard type-alias support in `InertiaScanner.ResolveTypeName` (2026-08-13)

**Trigger**: `TeaTimeTracker/reports/M3-dts-validation.md` bug #1 —
`InertiaScanner.ResolveTypeName` (`src/Tsgen/Inertia/InertiaScanner.pas`)
only recognized a value type's exact CLR name (`Int32`, `Int16`, ...), not
Oxygene's own "more Pascal-ish" standard-library aliases for those same
types. `Integer` (the alias for `Int32`) is what real Oxygene code
overwhelmingly writes — confirmed by the report finding it in
`TeaTimeTracker`'s own `RecordsController.Index` (`var count: Integer :=
records.Count;`), the exact `var IDENT: TypeName := ...;` shape §24.6
already documents as v1's only resolvable local-variable pattern — so
`var count: Integer` silently failed to register in `aLocalTypes`, and
the props value read from it fell back to `unknown` + a diagnostic naming
the field, even though the underlying type (`Int32`) is fully supported
everywhere else in the pipeline.

**Fix**: added an alias branch to `ResolveTypeName`, checked against
https://docs.elementscompiler.com/API/StandardTypes/Integers/ (fetched
directly, not from memory or a general web summary — an initial broader
web search claimed "Real" is also a recognized Oxygene alias for
`Double`, which turned out to be unconfirmed by the actual Elements docs
page, see below) rather than guessed:

| Written alias | Resolves to |
|---|---|
| `Integer` | `System.Int32` |
| `SmallInt` | `System.Int16` |
| `ShortInt` | `System.SByte` |
| `Word` | `System.UInt16` |
| `Cardinal`, `LongWord` | `System.UInt32` |
| `IntMax` | `System.Int64` |
| `UIntMax` | `System.UInt64` |

**Deliberately NOT added, and why**:
- **`Real` for `Double`** — a common historical Pascal/Delphi name, and a
  general web search initially suggested it's supported in Oxygene too.
  Fetching https://docs.elementscompiler.com/API/StandardTypes/Floats/
  directly (the actual current Elements docs page, table format matching
  the Integers page above) shows only `Single` (aliases `float`,
  `Float32`) and `Double` (alias `Float64`) — no `Real` anywhere on that
  page. Not adding an alias the authoritative source doesn't confirm,
  per this session's explicit "don't guess" instruction — if `Real` is
  genuinely valid Oxygene and just undocumented on that specific page,
  add it later with a better citation, not now.
- **`NativeInt`/`NativeUInt`** (aliased to `IntPtr`/`UIntPtr` on the same
  Integers page) — real, but `Tsgen.Ir.TypeMapper.MapLeaf` has no case for
  `System.IntPtr`/`System.UIntPtr` either (would still render `unknown`
  downstream even if resolved here), and platform pointer-sized integers
  aren't a realistic Inertia props type. Skipped as out-of-scope rather
  than half-wired.

Only `InertiaScanner.ResolveTypeName` needed changing —
`ParseMethodParams`/`ParseVarDecl` both already call it as their single
choke point for written-type-name resolution, so parameter types spelled
with an alias now resolve too, not just local-variable declarations.
`Tsgen.Nrt.NullabilityScanner` (the separate NRT source scanner) needed
no change: it works off the `nullable`/`not nullable` keywords directly,
never a type-name string, so it was never affected by this gap.

**Fixture**: `tests/fixtures/InertiaMode/InertiaMode.pas`'s
`Controller.Profile` now also declares `var age: Integer := 30;` and
`props['Age'] := age;` — chosen over a new dedicated fixture since
`InertiaMode` is exactly where the real bug manifested (props-value
resolution, not assembly-reflection member typing, which already worked
via `Int32` regardless of spelling). Confirmed `expected/default.d.ts`'s
`ProfileProps.age: number;` (no `| null`, correctly non-nullable via
`ValueTypeDefaultProvider` same as every other value-typed member) and
`ProfileFormErrors` picking up the new `'age'` key — the *only* diff
across all three `InertiaMode` snapshots (`default`/`non-null`/
`as-written`), confirmed via `git diff` before committing.

**Verification**: `tools/run-tests.ps1` — **17/17 cases pass**.

## 33. Enum non-null default value in `ValueTypeDefaultProvider` (2026-08-13)

**Trigger**: `TeaTimeTracker/reports/M3-dts-validation.md` bug #2 — an
unannotated property/field whose type is one of the target assembly's own
enums (e.g. `property BeverageType: BeverageType read write;`) rendered
`| null` under the default `--nrt-unknown-policy`, even though enums are
CLR value types and every *other* unannotated value type
(`Int32`/`Boolean`/...) already resolves to non-null via
`ValueTypeDefaultProvider` (§21). Root cause:
`ValueTypeDefaultProvider.IsKnownValueType` is a hardcoded string-name
list of BCL primitives — it can enumerate `System.Int32` up front because
that name is fixed and known at compile time, but it has no way to
enumerate every possible target-assembly enum name the same way, so a
user-defined enum always fell through to `Unknown` from every provider
(`OxygeneSourceScanProvider` too, since Oxygene convention doesn't require
writing `not nullable` on a value type either) and picked up
`--nrt-unknown-policy`'s default.

**Design, following the report's own §5.1 suggestion**: propagate
`RawType.Kind = Enum` (already tracked per-type in
`src/Tsgen/Loading/RawModel.pas`) through to the MEMBER's own type
reference, rather than trying to make `ValueTypeDefaultProvider` look
anything up by name:

- `RawTypeRef` (`RawModel.pas`) gains an `IsEnum: Boolean` field — true
  only for a leaf reference (never for the array/generic-instantiation
  wrapper itself; only a wrapper's element/argument type could be an
  enum, and that nested `RawTypeRef` carries its own `IsEnum`).
- **Two separate call sites build a `RawTypeRef` and both needed the
  fix** — this is the one design point worth flagging for whoever reads
  this next, since it's easy to fix only the more obvious one and think
  the bug is closed:
  - `AssemblyLoader.BuildTypeRef` (reflection path, used for every
    ordinary class member): sets `result.IsEnum := aType.IsEnum` in the
    leaf (`else`) branch, straight from `System.Type.IsEnum`. Fixes the
    `beverageType`-style case (a real class property).
  - `InertiaScanner.Scan`'s `knownTypes` dictionary construction (source-
    scan path, used to resolve Inertia props/shared-data field types by
    written name): now sets `IsEnum := (rt.Kind = RawTypeKind.Enum)` per
    entry, reading `RawType.Kind` directly (there's no live
    `System.Type` here — `aRaw` is the already-loaded `RawAssembly`).
    Fixes the `mode`-style case (`var mode: ThemeMode := ...;
    shared['Mode'] := mode;`, resolved via `ResolveTypeName`'s
    `aKnownTypes` lookup, an entirely different code path from class-
    member reflection). The M3 report's harness reproduction hit this
    exact path (`SharedData.mode: ThemeMode | null`) — fixing only
    `AssemblyLoader.BuildTypeRef` would have silently left this half of
    the bug in place.
- `ValueTypeDefaultProvider.TryGetNullability`: `IsKnownValueType(...) or
  aTypeRef.IsEnum` now both lead to `IsNotNullable`. The existing
  `Nullable<T>` check stays first and still wins for `nullable SomeEnum`
  (a `Nullable<T>`-wrapped member's outer `RawTypeRef` has
  `FullName = 'System.Nullable\`1'` and `IsEnum = false` — only the inner
  `TypeArguments[0]` entry, never examined by this provider, would carry
  `IsEnum = true` — so an explicitly-nullable enum is unaffected by this
  change, exactly like an explicitly-nullable `Int32` already was).

**Fixture**: `tests/fixtures/SampleModel/SampleModel.pas`'s `Status` enum
existed already but no member referenced it — added
`property CurrentStatus: Status read write;` (deliberately unannotated)
to `User`, reusing the existing enum rather than adding a new one.
Confirmed via `git diff` that only the `SampleModel` fixture's four
snapshots changed (`InertiaMode`'s, which has no enum type at all, did
not — ruling out an accidental behavior change elsewhere) and that
`currentStatus: SampleModel.Status;` renders with no `| null` and no
`// nrt: unknown` comment in any of `default`/`union-nonnull`/
`mark-unknown`/`as-written` — genuinely resolved non-null, not merely
defaulted, matching `CLAUDE.md`'s existing NRT-fixture guidance (a
default-only snapshot can't distinguish "correctly resolved" from
"happened to default the same way" — `SampleModel`'s pre-existing `Notes`
member already exercises the genuinely-`Unknown` side of that
distinction, so no separate non-null-policy fixture case was needed just
for this addition).

**Verification**: `tools/run-tests.ps1` — **17/17 cases pass**.

## 34. `System.DateOnly`/`System.TimeOnly` support (2026-08-13)

**Trigger**: `docs/DESIGN.md` §7 task 1 / `TeaTimeTracker/reports/M3-dts-validation.md`
§7 gap #2 — `TastingRecordDetail.BrewedAt: DateOnly` fell to `unknown` +
a diagnostic, one of the three deliberately-expected gaps the report
confirmed reproduced as documented (not a new bug, unlike tasks 3/4).
`TimeOnly` handled identically in the same pass, per this session's
instructions ("do both, TS side is `string` either way").

**Fix, three locations, matching `docs/DESIGN.md` §7's own task
breakdown exactly**:

- `Tsgen.Ir.TypeMapper.MapLeaf` (`TypeMapper.pas`): `System.DateOnly`/
  `System.TimeOnly` → `'string'`, same bucket as `DateTime`/
  `DateTimeOffset` and for the same reason — `System.Text.Json`'s default
  converters serialize both to a plain ISO string (`DateOnly` as
  `"yyyy-MM-dd"`, `TimeOnly` as `"HH:mm:ss[.fffffff]"`), and JSON has no
  native date/time type for TypeScript to model more precisely anyway.
- `Tsgen.Nrt.NullabilityProviders.ValueTypeDefaultProvider.IsKnownValueType`:
  added both CLR names to the known-value-type list (both are genuine CLR
  `struct`s, same category as `DateTime`), so an unannotated
  `DateOnly`/`TimeOnly` member resolves to non-null via the same
  mechanism as tasks 3/4's additions, not left to `--nrt-unknown-policy`.
- `Tsgen.Inertia.InertiaScanner.ResolveTypeName`: added both written
  names to the same branch style as `DateTime`/`DateTimeOffset`/`Guid`,
  so an Inertia props/shared-data field typed via an explicit
  `var x: DateOnly := ...;` local (the only pattern v1 resolves, §24.6)
  also works, not just reflection-based class members.

**Fixture, and an unplanned but necessary side effect**: added
`property RegisteredOn: DateOnly read write;` (unannotated, mirroring
task 4's `CurrentStatus` addition) to `SampleModel.pas`, and a
`var joined: DateOnly := new DateOnly(2024, 1, 1); props['Joined'] :=
joined;` pair to `InertiaMode.pas`'s `Controller.Profile` (covering
`ResolveTypeName`'s branch specifically, which `SampleModel`'s
reflection-only path can't reach). Both fixtures failed to build at
first with `E: Unknown type "DateOnly"` — `System.DateOnly` was
introduced in .NET 6 and was never backported into the `netstandard2.0`/
`netstandard2.1` reference assemblies every existing fixture targets
(`<TargetFramework>.NETStandard</TargetFramework>`), so it's simply not
visible from a `.NETStandard`-targeted Oxygene source file regardless of
what's installed locally. Fixed by changing ONLY these two fixtures'
`<TargetFramework>` from `.NETStandard` to `.NETCore` (each fixture is
its own independent EBuild project — this cannot affect the other five,
confirmed via `git diff` showing zero changes to any of their expected
snapshots after the switch); `Reference Include="Echoes"` needed no
change, EBuild re-resolved it to the `NETCore5.0` variant automatically.
Arguably more representative than `.NETStandard` anyway, since
`DateOnly` is a real .NET 6+-only BCL type — a target app using it (like
`TeaTimeTracker`, `Mode=Echoes`/`TargetFramework=.NETCore`) will always
be a `.NETCore` assembly by construction, never `.NETStandard`.

Confirmed via `git diff` that only `SampleModel`'s and `InertiaMode`'s
own expected snapshots changed (`registeredOn: string;` /
`joined: string;`, both non-null, both correctly added to
`ProfileFormErrors`'s key union for the `InertiaMode` case) — no other
fixture's output moved.

**Verification**: `tools/run-tests.ps1` — **17/17 cases pass**.

## 35. struct (Oxygene `record`) support (2026-08-13)

**Trigger**: `docs/DESIGN.md` §7 task 2 / `M3-dts-validation.md` §7 gap
#1 — `TastingRecordDetail.Rating: Rating` (an Oxygene `record`, i.e. a
CLR `struct`) fell to `unknown` + a diagnostic, the last of the three
gaps the report confirmed reproduced exactly as `docs/DESIGN.md` §7
already expected (not a new bug).

**Fix, one location** (`AssemblyLoader.Load`'s type-filter condition):
previously `not (t.IsClass or t.IsEnum)` skipped every value type that
wasn't an enum, including ordinary structs. Added `isStruct := t.IsValueType
and (not t.IsEnum) and (not t.IsPrimitive)` and included it in the
admitted set (`t.IsClass or t.IsEnum or isStruct`) — everything else about
the loop is unchanged: a struct that passes the filter falls into the
exact same `else` branch (`rt.Kind := RawTypeKind.ClassLike`, then the
same `GetProperties`/`GetFields` reflection) a class already used, since
reading a struct's public instance properties/fields works identically
to reading a class's. `t.IsPrimitive` is .NET's own small fixed set of
built-in value types (`Int32`, `Boolean`, ...); confirmed this exclusion
is actually unreachable in practice, not just belt-and-suspenders — kept
anyway for explicitness/defensiveness, in case `asm.GetTypes()`'s
target-assembly-only contract is ever weakened later — since
`asm.GetTypes()` only ever returns types the TARGET assembly itself
declares, and no assembly can declare its own `System.Int32`, this branch
was already effectively unreachable even before adding the explicit
check; the real thing keeping BCL structs like `System.DateTime` out is
that they simply never appear in the loop at all, being defined in a
different assembly entirely. No IR (`Tsgen.Ir`) or Emitter
(`Tsgen.Emit.DtsEmitter`) change was needed — both already treat
`RawTypeKind.ClassLike`/`IrTypeKindLite.ClassLike` generically, with no
assumption anywhere that a `ClassLike` IR type must have originated from
a CLR `class` — so this stayed a single-file, single-location fix, not
the Loader+IR+Emitter "nested type"-style compound change `CLAUDE.md`
warns struct support might turn into. It didn't.

**Follow-up finding, deliberately NOT implemented this round**: an
unannotated struct-typed member (e.g. `TastingRecordDetail.Rating`
itself) still renders `| null` under the default policy —
`ValueTypeDefaultProvider` has no path from "this `RawTypeRef` names one
of our own struct types" to `IsNotNullable`, unlike task 4's enum fix
(§33). This is real and mirrors §33's bug shape closely enough that it
would be a small, contained addition (a second flag alongside
`RawTypeRef.IsEnum`, or generalizing it to something like
`IsAssemblyValueType`, set from `AssemblyLoader.BuildTypeRef`'s
`aType.IsEnum` OR struct-check and checked the same way in
`ValueTypeDefaultProvider`) — but `docs/DESIGN.md` §7 task 2's own text
scoped this task to "admit structs into the IR, confirm the Emitter
handles them, add a fixture proving the reference resolves" only, with
no mention of the referencing member's own nullability. Not adding it
unrequested, per this session's explicit scope discipline instruction (a
task turning out to need something adjacent-but-distinct is exactly what
tasks 3/4 already were split out for) — flagging it here instead so
it's a deliberate, visible decision, not a missed case. **(Since
resolved — implemented as sketched here, see §38, 2026-08-13.)** The `SampleModel`
fixture below makes this visible on purpose: `currentRating` responds to
`--nrt-unknown-policy` exactly like the deliberately-`Unknown`-reference-type
`notes` field does (`| null` under default, bare + `// nrt: unknown`
under `mark-unknown`, bare under `union-nonnull`) — not like the
already-non-null `currentStatus`/`registeredOn` fields task 4/1 fixed.

**Fixture**: `tests/fixtures/SampleModel/SampleModel.pas` gained a
`Rating = public record public property Aroma/Taste/Overall: Integer
read write; end;` — deliberately mirroring `TeaTimeTracker`'s own
`Rating` record exactly (three `Integer` properties, same field names),
since that's the real shape this task exists to support — plus
`property CurrentRating: Rating read write;` (unannotated) on `User`.
Confirmed via `git diff` that only `SampleModel`'s four snapshots
changed, and read each by eye: `Rating` emits as an ordinary `export
interface` (`aroma`/`taste`/`overall: number;`, `Integer`→`Int32`→
`number` working unchanged since a struct's members go through the exact
same `BuildTypeRef`/`TypeMapper` path as a class's), and
`currentRating: SampleModel.Rating | null;` on `User` — a real,
fully-qualified named-type reference, not `unknown` — which is this
task's actual acceptance bar.

**Verification**: `tools/run-tests.ps1` — **17/17 cases pass**.

## 36. Session summary: `docs/DESIGN.md` §7 tasks 0/3/4/1/2, in that priority order (2026-08-13)

All five tasks `docs/DESIGN.md` §7 lists (added by `TeaTimeTracker`'s M3
validation pass, `M3-dts-validation.md`) are now done, in the priority
order the session was given (0 → 3 → 4 → 1 → 2, task 0 first since
nothing else was re-verifiable against a real app until it was fixed).
See §31 (task 0: `AssemblyLoader` dependency resolution + crash
resilience), §32 (task 3: Oxygene type-alias support), §33 (task 4: enum
non-null default), §34 (task 1: `System.DateOnly`/`TimeOnly`), §35 (task
2: struct/`record` support) for the full per-task detail; `CLAUDE.md` was
updated in the same session to reflect all five (fixture count/list,
`ValueTypeDefaultProvider`'s enum/DateOnly coverage, the type-alias list,
the new `AssemblyLoader` dependency-resolution paragraph, and a note
distinguishing struct support from the still-out-of-scope nested-type
case).

**Final acceptance run**, after all five fixes, against the same real
`TeaTimeTracker.dll` that originally blocked M3 (§31's own acceptance run
only had task 0 applied; this one has all five):

```
tsgen generate --assembly ...\TeaTimeTracker\Bin\Release\TeaTimeTracker.dll --source ...\TeaTimeTracker\src\TeaTimeTracker --out <scratchpad> --mode inertia
```

```typescript
declare namespace TeaTimeTracker.Models {
  export enum BeverageType { GreenTea = 0, BlackTea = 1, Oolong = 2, Herbal = 3, Coffee = 4 }
  export enum ThemeMode { Light = 0, Dark = 1, System = 2 }
  export interface Rating {
    aroma: number;
    taste: number;
    overall: number;
  }
  export interface TastingRecordDetail {
    id: number;
    name: string;
    beverageType: TeaTimeTracker.Models.BeverageType;
    rating: TeaTimeTracker.Models.Rating | null;
    notes: string | null;
    brewedAt: string;
  }
}
declare namespace Props {
  export interface SharedData {
    flash: Record<string, string>;
    timestamp: string;
    errors: Record<string, string>;
    mode: TeaTimeTracker.Models.ThemeMode;
  }
  export interface IndexProps extends Props.SharedData {
    records: unknown | null;
    count: number;
  }
  // ...EditProps/ThemeProps and their FormErrors types, unchanged from §31's run
}
```

Comparing this to §31's task-0-only run and the original M3 report:
- `beverageType`/`mode`: `| null` → non-null (task 4).
- `brewedAt`: `unknown` → `string` (task 1).
- `count`: `unknown` → `number` (task 3 — the `Integer` alias).
- `rating`: `unknown` → `TeaTimeTracker.Models.Rating | null`, a real
  interface with `aroma`/`taste`/`overall: number;` (task 2) — still
  `| null` since struct-typed-member non-null defaulting was this task's
  documented, deliberate follow-up finding (§35), not fixed this round.
- `records`: still `unknown` — `List<TastingRecordSummary>` generic
  props resolution was never one of the five tasks (`docs/DESIGN.md` §7
  never listed it; `InertiaScanner` v1's generic-typed-local limitation
  is `HANDOFF.md` §24.6's own documented scope boundary) and remains
  exactly as expected, not a regression.
- `notes`: unchanged (`string | null`, explicitly annotated
  `nullable String` in `TeaTimeTracker`'s own source — never affected by
  any of these five tasks).

Diagnostics dropped from six warning lines (§31's run) to three: the
`Rating`/`DateOnly` "no type mapping" warnings and the `Count`
"could not resolve" warning are gone (their underlying gaps are fixed);
only the pre-existing `Records` generics gap, its matching aggregate
`(unresolved)` warning, and the "skipped N type(s)" aggregate (now 4, was
5 — one fewer non-public/nested/generic/unsupported-kind type, unrelated
churn from ordinary reflection, not investigated further since it's
below the diagnostic's own aggregation threshold for detail) remain.
`TeaTimeTracker` frontend integration itself (copying this `.d.ts` into
`frontend/src/types/generated/` and running `tsc --noEmit` against it)
was explicitly out of scope for this session (TeaTimeTracker repo writes
prohibited) — that's M3's own re-run, a `TeaTimeTracker`-side task for a
future session, not part of `docs/DESIGN.md` §7.

**All local commits, in order** (task order 0 → 3 → 4 → 1 → 2, plus this
documentation pass):

1. task 0 — `AssemblyLoader` dependency resolution + crash resilience
2. task 3 — Oxygene type-alias support
3. task 4 — enum non-null default value
4. task 1 — `System.DateOnly`/`TimeOnly`
5. task 2 — struct (Oxygene `record`) support
6. this `HANDOFF.md` §36 + `CLAUDE.md` documentation pass
7. task 5 (added by Fable5 review after §36, see §37) — merge duplicate
   Inertia page declarations

No push performed, per instructions.

## 37. Merge duplicate Inertia page declarations across Render call sites (task 5, 2026-08-13)

**Trigger**: Fable5 review of tasks 0-2's real-DLL output (§31's
`TeaTimeTracker.dll` acceptance run) — approved tasks 0-2, but flagged
the "two separate, identical `EditProps`/`ThemeProps`/
`EditFormErrors`/`ThemeFormErrors` declarations" §31 had logged as merely
"redundant" as actually a real bug: `EditFormErrors`/`ThemeFormErrors`
are TypeScript `type` aliases (`DtsEmitter.EmitType`'s `FormErrorsLike`
branch), and TypeScript does not allow redeclaring a `type` alias — a
"Duplicate identifier" compile error, not a harmless duplicate like the
`interface` re-declaration half of it. Any real app where the same
Inertia component is rendered from more than one action (the common
"GET shows a form, POST re-renders it with validation errors" pattern —
exactly what `TeaTimeTracker`'s `RecordsController.Edit`/`Save` and
`SettingsController.Theme`/`SaveTheme` do) would produce a `.d.ts` that
fails `tsc`. Added as an explicit additional task (numbered 5, done
after the original 0/3/4/1/2 order) rather than folded into task 0,
since it's a distinct root cause (`InertiaScanner`/`InertiaIrBuilder`'s
"one Render call site = one page" assumption, unrelated to `AssemblyLoader`).

**Design** (Fable5's own call, implemented as specified): dedup pages by
`ComponentName`, field list = union of every call site's fields.
- A field name resolving to the SAME type at every call site merges
  silently.
- A field name resolving to DIFFERENT types across call sites keeps the
  FIRST-resolved one and warns via `aDiagnostics`, naming the component,
  the field, and both conflicting type display names — no attempt to
  synthesize a TS union type for the field itself (out of v1's scope, and
  arguably the wrong fix anyway — a genuine type conflict on the same
  prop name across actions usually indicates the two actions aren't
  really building "the same shape" and deserves a look, which is exactly
  what surfacing it as a diagnostic rather than silently unioning
  achieves).
- A field present at only one call site is still included (union, not
  intersection) — v1 has no way to distinguish "genuinely conditional
  prop" from "just happens to be set from a different action", and the
  pre-existing scope decision (`docs/DESIGN.md` §5.4 / `HANDOFF.md` §24.6)
  is "no optional-field support," which this doesn't change, just applies
  consistently to the merged field set.

**Where the fix lives, and why**: `InertiaScanner.pas`, a new private
`MergePages` class method, called once at the end of `Scan` (after the
existing per-file `ScanFile` loop, which now accumulates into a local
`rawPages` list instead of writing straight into `result`) — `result :=
MergePages(rawPages, aDiagnostics);`. Considered `InertiaIrBuilder.Build`
as the alternative site (it's the thing that actually creates one Props/
FormErrors pair per `aPages` entry) but chose the Scanner instead:
`InertiaIrBuilder.Build`'s "one entry in `aPages` = one page" assumption
is correct and simple, and should stay that way — teaching it about
"actually, entries might describe the same page and need merging" would
push a collection-normalization concern into the IR-building stage,
which is supposed to only convert an already-resolved page list, not
resolve it further. The Scanner is also where the exact same shaped
problem is already solved once, for `aSharedData.Fields` (cross-file
accumulation via `ScanFile`'s in/out accumulator pattern) — `MergePages`
is a second instance of "the Scanner's job is to normalize what call-site
parsing found," not a new responsibility for it.

**Fixture**: `tests/fixtures/InertiaMode/InertiaMode.pas`'s `Controller`
gained a `SaveProfile` method — a second `Inertia.Render('pages/Profile',
...)` call site (the same component `Profile` already renders), with
`props['Bio'] := 'saved-bio';` (same key AND same resolved type,
`String`, as `Profile`'s own `Bio` — merges silently), `props['IsAdmin']
:= 'yes';` (same key, but `String` here vs `Boolean` in `Profile` — a
genuine, deliberate type conflict, since `Profile` sets `IsAdmin` from a
`Boolean` literal), and `props['SavedAt'] := 'now';` (a key only this
call site sets — proves the union, not intersection). Confirmed by
running `tsgen` directly against the rebuilt fixture DLL before touching
any snapshot: "Found 2 Inertia.Render call site(s)" (was 3 raw call
sites — `Profile`, `SaveProfile`, `Empty` — merged down to 2 pages,
`pages/Profile` and `pages/Empty`), a single `ProfileProps`/
`ProfileFormErrors` pair (not two), `isAdmin: boolean;` (first-resolved
type kept), a new `savedAt: string | null;` member, and the exact
expected diagnostic: `Inertia page "pages/Profile" renders prop
"IsAdmin" with conflicting types across multiple Render call sites
(System.Boolean from an earlier call site vs System.String here) --
keeping the first-resolved type for the merged page.` Then ran
`-UpdateSnapshots` and confirmed via `git diff` that ONLY `InertiaMode`'s
three snapshots changed (adding `savedAt` to `ProfileProps`/
`ProfileFormErrors`, no other fixture affected — none of the other six
render the same component twice).

**Real-DLL re-verification** against the same `TeaTimeTracker.dll` as
§31/§36 (no source changes to `TeaTimeTracker`, `--mode inertia`, `--out`
a scratchpad directory):

```
Loading assembly: ...\TeaTimeTracker.dll
Loaded 13 type(s).
Found nullability info for 7 member(s).
Found 3 Inertia.Render call site(s) and 1 shared-data field(s).
Wrote <scratchpad>\index.d.ts
Warning: skipped 4 non-public/nested/generic/unsupported-kind type(s); their members will not appear in the output.
Warning: could not resolve type of Inertia props key "Records" on props -- emitting "unknown" for this field
Warning: no type mapping for (unresolved), emitting "unknown" (1 member(s), e.g. IndexProps.Records)
```

"Found 3 Inertia.Render call site(s)" (was 5 in §36's run — `Index`,
`Edit`×2, `Theme`×2 raw call sites merged down to the 3 distinct pages:
`Index`/`Edit`/`Theme`). The emitted `.d.ts` now has exactly ONE
`EditProps`/`EditFormErrors`/`ThemeProps`/`ThemeFormErrors` each (see the
full listing in §36 for the unchanged parts — `Rating`, `beverageType`,
`brewedAt`, etc. are all identical to that run, only the duplicate-page
issue is different here). No type-conflict warning fired for
`TeaTimeTracker` itself — its GET/POST pairs happen to set the same
fields to consistent types, so the conflict path only shows up in the
fixture's deliberately-constructed case, not this real app; that's a
property of `TeaTimeTracker`'s own code, not evidence the conflict path
is unreachable in general.

## 38. Unannotated struct-typed members default to non-null (§35's follow-up, 2026-08-13)

**Trigger**: `TeaTimeTracker`'s HANDOFF item 2 — the two remaining
prerequisites for replacing its hand-written `models.ts` with generated
types. This is prerequisite (b): `rating: TeaTimeTracker.Models.Rating |
null` where the hand-written type correctly says non-null. Exactly the
change §35's "Follow-up finding, deliberately NOT implemented this
round" paragraph already sketched — designed this round by Fable5
(main session), implemented by a Sonnet 5 agent per the model-selection
policy (a fully-specified mirror of an existing pattern), commit
`88f6842`.

**Fix — a precise mirror of §33's enum fix, four locations**:

- `RawTypeRef` gained `IsStruct: Boolean` (alongside `IsEnum`), and
  `RawType` gained `IsStruct: Boolean` — deliberately a flag on the
  existing `ClassLike` kind, NOT a third `RawTypeKind` value, so no
  `Kind = RawTypeKind.ClassLike` comparison anywhere (IrBuilder,
  InertiaIrBuilder, DtsEmitter) changes behavior.
- `AssemblyLoader.BuildTypeRef`'s leaf branch sets `result.IsStruct :=
  aType.IsValueType and (not aType.IsEnum) and (not aType.IsPrimitive)`
  — the same expression as `Load`'s own §35 `isStruct` filter. This is
  the "broad" definition (BCL structs like `DateTime`/`Decimal` also get
  the flag), following `IsEnum`'s own precedent (true for BCL enums
  too): for structs already in `IsKnownValueType` nothing changes, and
  for ones that aren't (`TimeSpan`, ...) non-null is semantically MORE
  correct — a non-`Nullable<T>` value type can never serialize to JSON
  `null`.
- `AssemblyLoader.Load` sets `rt.IsStruct := isStruct` on the `RawType`.
- `InertiaScanner.Scan`'s `aKnownTypes` construction propagates
  `typeRef.IsStruct := rt.IsStruct` — the second call site §33 taught us
  about (a props/shared-data field's type is resolved by written name
  from source, not reflection, so `BuildTypeRef` alone doesn't cover it).
- `ValueTypeDefaultProvider.TryGetNullability` adds `or
  aTypeRef.IsStruct` to the existing `IsKnownValueType(...) or
  aTypeRef.IsEnum` check.

**Fixtures**: `SampleModel` needed no source change (`User.CurrentRating:
Rating`, unannotated, was §35's own fixture) — its `default`/
`mark-unknown`/`as-written` snapshots dropped the `| null`/`// nrt:
unknown` on `currentRating` exactly as predicted; `union-nonnull` was
already bare. `InertiaMode` gained a `BadgeDto = public record` and an
unannotated `var badge: BadgeDto; props['Badge'] := badge;` in
`Profile` — this pins the SOURCE-SCAN propagation path in a snapshot
(`badge: InertiaMode.BadgeDto;`, non-null), which §33's enum version
never had (it was only ever exercised against the real DLL). 17/17
cases pass; no other fixture's snapshot changed.

**Real-DLL acceptance** (same `TeaTimeTracker.dll`/`--source` as §36):
`rating: TeaTimeTracker.Models.Rating;` — `| null` gone, everything
else byte-identical to §36+§37's baseline, diagnostics unchanged.

## 39. InertiaScanner resolves generic type annotations on locals (2026-08-13)

**Trigger**: `TeaTimeTracker`'s HANDOFF item 2, prerequisite (a) — the
sole reason `IndexProps.records` stayed `unknown`: `var records:
List<TastingRecordSummary> := fRepository.GetAll();` (its
`RecordsController.Index`, the repo-documented "annotated local"
pattern) never resolved, because `ParseVarDecl` read only a single
identifier after the `:`. Designed this round by Fable5 (main session);
implemented by an Opus 5 agent per the model-selection policy (the
tokenizer-scanner/generics-interaction territory `CLAUDE.md` explicitly
reserves for it), commit `7174424`.

**Key design fact**: everything downstream already handled generic
`RawTypeRef`s (§23's `TypeMapper.MapTypeRef` recursion;
`InertiaIrBuilder.CollectReferencedTypes` already walks
`TypeArguments`, so the element type gets BFS-emitted for free). The
entire change is `InertiaScanner.pas` producing a proper generic
`RawTypeRef` — no IR/Mapper/Emitter change.

**Scope (deliberate, unchanged elsewhere)**: only the colon-annotation
form `var IDENT: GenericType<...> [:= ...];`. Recognized outer names
mirror `TypeMapper.IsCollectionGenericDef`/`IsDictionaryGenericDef`
exactly (List/IList/IEnumerable/ICollection/IReadOnlyList/
IReadOnlyCollection/HashSet/ISet at arity 1, Dictionary/IDictionary/
IReadOnlyDictionary at arity 2) plus `Nullable` → `System.Nullable``1`;
the new `ResolveGenericDefName` helper is the one place to keep in sync
with `TypeMapper`'s sets. Type arguments resolve recursively (nested
generics work; Oxygene spells shift as `shr`, so there is no `>>`
token-splitting problem — `Token.T_Less`/`T_Greater` exist and were
confirmed against the Elements SDK DLL before implementation). Still
out of scope, unchanged: `:= new List<...>` inference form, generic
`new` in prop-value position, generic method parameters, `nullable T`
annotations, `array of T`, dot-qualified type names. Resolution failure
(unknown outer name / arity mismatch / unresolvable argument) returns
nil — the local stays unregistered and the existing "could not resolve
type of Inertia props key" diagnostic fires; no new diagnostic was
added.

**Implementation notes** (Opus 5's calls, worth keeping):
- `ParseTypeAnnotation` locates the balanced `>` FIRST (depth count)
  and sets the resume index unconditionally, then parses arguments
  inside that span — "failure still advances the scan correctly" is
  structural, not per-branch bookkeeping. A `;`/`:=` before the
  balanced `>` aborts at that token.
- `ParseVarDecl` keeps capturing the outer written name and its
  `propsFields` registration test (`'InertiaProps'`/`'Dictionary'`)
  verbatim, so `var props: Dictionary<String, Object>` behaves exactly
  as before (Object unresolvable → local unregistered, props var still
  registered). An explicit `annotated` flag prevents the colon branch
  from silently falling back to the old single-name path.

**Fixture**: `InertiaMode` gained `TagDto` (reachable ONLY via
`List<TagDto>` — proves BFS-through-`TypeArguments` on the source-scan
path) and two annotated locals in `Profile`: `tags: List<TagDto>` and
`lookup: Dictionary<String, RoleDto>`. Snapshots: `tags:
InertiaMode.TagDto[] | null;` / `lookup: Record<string,
InertiaMode.RoleDto> | null;` (`| null` is correct per policy — an
unannotated reference-typed local is still `Unknown`, unchanged
principle), bare under `non-null`, `'tags' | 'lookup'` joining
`ProfileFormErrors`. 17/17 pass; only `InertiaMode`'s three snapshots
changed.

**Real-DLL acceptance** (same setup as §36): `records:
TeaTimeTracker.Models.TastingRecordSummary[] | null;` plus the
`TastingRecordSummary` interface (5 members) now emitted; both
`Records` diagnostics gone, leaving only the "skipped 4 ... type(s)"
aggregate. Verified by baseline diff, not by eye: the pre-change binary
was rebuilt from a stash and its output diffed against the new one —
the diff is exactly the new interface block plus the one `records:`
line.

**Verification**: `tools/run-tests.ps1` — **17/17 cases pass** (same
total as §36 — this task changed `InertiaMode`'s snapshot content, not
its case count).

Final state: **7 fixtures, 17/17 snapshot cases pass.**
