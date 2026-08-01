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
7. **Reporting the `deps.json` runtime-asset gap (§10.2/§12.3) to
   RemObjects.** This was on the original review's "shouldn't wait"
   list alongside the `.gitignore` fix, but fell through the cracks of
   this section on the first pass -- a follow-up verification review
   caught the omission. RemObjects has already been responsive by email
   once (§9), and Elements ships weekly, so a real upstream fix is
   plausibly obtainable; every session this stays unreported extends how
   entrenched `tools/dev-build.ps1`'s workaround becomes. Send the report
   before the next implementation session, not after.

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
