# oxygene-tsgen

A CLI that reads .NET assemblies (`*.dll`) via reflection and generates
TypeScript type definitions (`.d.ts`). Written in Oxygene, the Object
Pascal-family language from [RemObjects
Elements](https://www.remobjects.com/elements/) (Echoes backend, .NET
target). Its primary use case: generating the Props types for
**Inertia.js** page components directly from ASP.NET Core + Oxygene
controller code, so the frontend types can never silently drift from what
the backend actually sends.

.NET アセンブリ (`*.dll`) をリフレクションで読み込み、TypeScript 型定義
(`.d.ts`) を生成する CLI ツールです。実装言語は [RemObjects
Elements](https://www.remobjects.com/elements/) の Oxygene (Object
Pascal 系言語、.NET ターゲットの Echoes バックエンド)。主な用途は、
ASP.NET Core + Oxygene の Controller コードから **Inertia.js** ページ
コンポーネント向けの Props 型を直接生成し、バックエンドが実際に送る
内容からフロントエンドの型が静かにドリフトしないようにすることです。

**Status:** Phase 1 (design) is complete. Phase 2 (implementation) has a
working, snapshot-tested CLI, and all three Inertia-specific generation
targets — Page Props, Shared Data, and Form/`useForm()` error types — are
implemented. See "Current Status" below for the precise implemented /
deferred breakdown.

**ステータス:** Phase 1 (設計) は完了。Phase 2 (実装) には
スナップショットテスト済みの動く CLI があり、Inertia 固有の3つの生成
ターゲット — Page Props、Shared Data、Form/`useForm()` エラー型 — は
全て実装済みです。実装済み / 先送りの正確な内訳は下記
「現在のステータス」を参照してください。

## What It Does / 何をするツールか

Given a built assembly and the matching Oxygene source directory,
`tsgen --mode inertia` locates `Inertia.Render(componentName, props)`
call sites in controller code and generates, in a single `.d.ts` file:

ビルド済みアセンブリと対応する Oxygene ソースディレクトリを与えると、
`tsgen --mode inertia` は Controller コード中の
`Inertia.Render(componentName, props)` 呼び出し箇所を検出し、単一の
`.d.ts` ファイルとして以下を生成します:

- **One Props interface per page** — the type of the data the
  corresponding frontend page component (e.g.
  `resources/js/Pages/PageName.tsx`) receives — plus only the types
  actually reachable from those props, not the whole assembly.
  **ページごとに1つの Props interface** — 対応するフロントエンド側ページ
  コンポーネント (例: `resources/js/Pages/PageName.tsx`) が受け取る
  データの型。加えて、アセンブリ全体ではなく、その props から実際に
  到達可能な型だけを出力します。
- **A `SharedData` interface that every page's Props `extends`** —
  covering data injected into every page: fields registered via
  InertiaNetCore's `AddInertiaSharedData(...)` middleware call, plus the
  three keys InertiaNetCore injects unconditionally (`flash`,
  `timestamp`, `errors`).
  **全ページの Props が `extends` する `SharedData` interface** — 全
  ページに注入されるデータをカバーします: InertiaNetCore の
  `AddInertiaSharedData(...)` ミドルウェア呼び出しで登録されたフィールド
  に加え、InertiaNetCore が無条件に注入する3つのキー (`flash`、
  `timestamp`、`errors`)。
- **A paired form-error type per page** for Inertia's client-side
  `useForm()` hook (e.g. `ProfileFormErrors` next to `ProfileProps`),
  shaped `Partial<Record<'field1' | 'field2' | ..., string>>` and reusing
  the same field names as the page's own Props type.
  **ページごとに対になるフォームエラー型** — Inertia のクライアント側
  `useForm()` フック向け (例: `ProfileProps` と並ぶ
  `ProfileFormErrors`)。形は `Partial<Record<'field1' | 'field2' | ...,
  string>>` で、そのページ自身の Props 型と同じフィールド名を再利用
  します。

The target ASP.NET Core Inertia adapter is **InertiaNetCore**, and the
target frontend framework is **React** — both explicit decisions made
2026-08-01, not incidental defaults (`docs/DESIGN.md` §11, `HANDOFF.md`
§6.4). The Inertia focus itself is the result of a deliberate scope
narrowing from an originally more generic tool (`HANDOFF.md` §6).

対象とする ASP.NET Core 向け Inertia アダプタは **InertiaNetCore**、
想定フロントエンドフレームワークは **React** です — どちらも 2026-08-01
に明示的に決定したもので、成り行きの既定値ではありません
(`docs/DESIGN.md` §11、`HANDOFF.md` §6.4)。Inertia への特化自体も、
当初のより汎用的なツール構想から意図的にスコープを絞り込んだ結果です
(`HANDOFF.md` §6)。

A generic mode also exists and remains supported: `--mode assembly`
(the default) simply emits types for every public type in the assembly,
for projects not using Inertia.js. Broader generic ambitions —
REST/OpenAPI integration, zod/io-ts schema emission, API-client
generation — are designed but secondary and unimplemented
(`docs/DESIGN.md` §8.3).

汎用モードも存在し、引き続きサポートされます: `--mode assembly` (既定)
は、Inertia.js を使わないプロジェクト向けに、アセンブリ内の全ての公開型
の型を単純に出力します。より広い汎用機能 — REST/OpenAPI 連携、zod/io-ts
スキーマ生成、API クライアント生成 — は設計済みですが副次的で、未実装
です (`docs/DESIGN.md` §8.3)。

## Why Not an Existing Tool Like TypeGen? / なぜ TypeGen 等の既存ツールではだめなのか

Mature C# → TypeScript generators already exist (e.g.
[TypeGen](https://github.com/jburzynski/TypeGen), NSwag, OpenAPI
Generator). Two independent, hands-on-verified reasons rule them out for
this codebase — its source language is Oxygene, not C# — beyond any
preference:

成熟した C# → TypeScript 生成ツールは既に存在します (例:
[TypeGen](https://github.com/jburzynski/TypeGen)、NSwag、OpenAPI
Generator)。このコードベース (ソース言語が C# ではなく Oxygene) では
それらが使えない、好みの問題ではない、実機で確認済みの2つの独立した
理由があります:

1. **TypeGen parses C# source via Roslyn — it has no path to Oxygene at
   all.** TypeGen reads C# source through the Roslyn compiler API
   (including nullable-reference-type annotations taken straight from the
   C# syntax tree, not from compiled-assembly metadata), and has no
   assembly-reflection-only fallback mode. Roslyn cannot parse Oxygene
   syntax (`nullable String`, `array of`, `class ... end` — an entirely
   different grammar), so no configuration can point TypeGen at an
   Oxygene project.
   **TypeGen は Roslyn 経由で C# ソースを解析するため、Oxygene への経路
   がそもそも存在しない。** TypeGen は C# コンパイラ API である Roslyn
   を通じて C# ソースを読み込みます (nullable 参照型の注釈も、コンパイル
   済みアセンブリのメタデータではなく C# の構文木から直接取得)。
   アセンブリのリフレクションだけで動くフォールバックモードはありません。
   Roslyn は Oxygene の構文 (`nullable String`、`array of`、`class ...
   end` — 全く異なる文法) を解析できないため、設定をどう変えても TypeGen
   を Oxygene プロジェクトに向けること自体ができません。
2. **Even a purely reflection-based tool would still miss nullability
   for Oxygene-authored types.** Confirmed hands-on (`HANDOFF.md` §8):
   Oxygene's Echoes backend does not emit
   `NullableAttribute`/`NullableContextAttribute` for Oxygene-authored
   code at all — the one piece of metadata generic .NET → TypeScript
   tools rely on for nullable/non-nullable output simply isn't there to
   reflect on. This is why this tool's source-level NRT scanner
   (`src/Tsgen/Nrt/NullabilityScanner.pas`) exists: a token scan of the
   Oxygene source is the only viable way to recover that information,
   and no existing generic tool does it because no other .NET language
   has this gap.
   **純粋にリフレクションだけに頼るツールであっても、Oxygene で書かれた
   型の nullability 情報は取得できない。** 実機で確認済み (`HANDOFF.md`
   §8): Oxygene の Echoes バックエンドは、Oxygene で書かれたコードに
   対して `NullableAttribute`/`NullableContextAttribute` を一切出力
   しません — 汎用の .NET → TypeScript ツールが nullable/non-nullable
   の出力に依拠しているまさにそのメタデータが、リフレクションで拾える
   形で存在しないのです。本ツールのソースレベル NRT スキャナ
   (`src/Tsgen/Nrt/NullabilityScanner.pas`) が存在する理由がこれです:
   Oxygene ソースのトークンスキャンがこの情報を回復する唯一の実用的な
   方法であり、他のどの .NET 言語にもこのギャップがないため、既存の
   汎用ツールはこれを一切行いません。

On top of the language barrier, the Inertia-specific generation this tool
exists for — discovering `Inertia.Render` call sites, detecting
`AddInertiaSharedData(...)` registrations, deriving `useForm()` error
types from a page's own Props fields — has no equivalent in a generic
DTO-mirroring tool: those tools mirror C# class shapes 1:1 and have no
concept of a controller call site or Inertia's runtime data-merging
behavior.

言語の壁に加えて、このツールの存在理由である Inertia 固有の生成機能 —
`Inertia.Render` 呼び出し箇所の検出、`AddInertiaSharedData(...)` 登録の
検出、ページ自身の Props フィールドからの `useForm()` エラー型の導出 —
は、汎用の DTO ミラーリングツールには相当するものがありません。それらの
ツールは C# クラスの形を 1 対 1 で写すだけで、Controller の呼び出し箇所
や Inertia のランタイムデータマージ挙動という概念自体を持たないため
です。

## Current Status / 現在のステータス

**Implemented** (`src/Tsgen`; all of it covered by the snapshot-test
suite — see "Building and Testing" below):

**実装済み** (`src/Tsgen`。全てスナップショットテストスイートの対象 —
下記「ビルドとテスト」参照):

- Metadata-only assembly loading via
  `System.Reflection.MetadataLoadContext` — target code is never
  executed. Non-public, nested, and generic-*definition* types are
  skipped with a warning naming the count.
  `System.Reflection.MetadataLoadContext` によるメタデータのみの
  アセンブリ読み込み — 対象コードは一切実行しません。非 public /
  nested / generic *定義*型はスキップし、件数を警告として表示します。
- NRT (nullable reference type) resolution via a provider chain
  (`docs/DESIGN.md` §4.2): the Tokenizer-based Oxygene source scan
  (`--source <dir>`) is the primary provider, falling back to "known CLR
  value types are non-nullable (and `Nullable<T>` nullable) by default"
  for anything the scan has no opinion on. Handles multi-type `type`
  sections and indexer-style properties; nested types are a known,
  documented gap (`HANDOFF.md` §18.1/§20).
  NRT (nullable 参照型) の解決はプロバイダチェーン経由
  (`docs/DESIGN.md` §4.2): Tokenizer ベースの Oxygene ソーススキャン
  (`--source <dir>`) を主プロバイダとし、スキャンが判定できないものは
  「既知の CLR 値型は既定で non-nullable (`Nullable<T>` は nullable)」に
  フォールバックします。1つの `type` セクション内の複数型宣言や indexer
  形式のプロパティに対応。nested types は既知の、文書化済みの未対応事項
  です (`HANDOFF.md` §18.1/§20)。
- A lightweight IR with structural generics support: arrays,
  `List<T>`-family → `T[]`, `Dictionary<K,V>`-family → `Record<K,V>`,
  `Nullable<T>`/`Task<T>`/`ValueTask<T>` unwrapping, and
  fully-qualified references between the tool's own emitted types
  (`HANDOFF.md` §23).
  構造化された generics 対応を持つ軽量 IR: 配列、`List<T>` 系 → `T[]`、
  `Dictionary<K,V>` 系 → `Record<K,V>`、`Nullable<T>`/`Task<T>`/
  `ValueTask<T>` のアンラップ、そしてツール自身が出力する型同士の完全
  修飾名での参照 (`HANDOFF.md` §23)。
- A single-file `.d.ts` emitter with a selectable enum style,
  unknown-nullability policy, and member-naming policy (see "CLI Usage"
  below for all flags and their exact semantics).
  単一ファイルの `.d.ts` エミッター。enum スタイル、nullability 未確定
  メンバーのポリシー、メンバー命名ポリシーを選択できます (全フラグと
  その正確な意味は下記「CLI の使い方」参照)。
- **`--mode inertia`** — the entry-point-driven mode described in "What
  It Does" above: all three of `docs/DESIGN.md` §2.6's Inertia-specific
  targets (Page Props, Shared Data, Form/`useForm()` errors) are
  implemented (`HANDOFF.md` §24/§26/§27). Shared Data merges into each
  page via an `extends` clause, and form-error field names come from
  each page's own Props type — see `HANDOFF.md` §27/§26 for why those
  choices differ from the original design sketch.
  **`--mode inertia`** — 上記「何をするツールか」で説明した
  エントリーポイント駆動モード: `docs/DESIGN.md` §2.6 の Inertia 固有
  ターゲット3つ (Page Props、Shared Data、Form/`useForm()` エラー) は
  全て実装済みです (`HANDOFF.md` §24/§26/§27)。Shared Data の各ページ
  へのマージは `extends` 節で行い、フォームエラーのフィールド名は各
  ページ自身の Props 型に由来します — これらが当初の設計案と異なる理由
  は `HANDOFF.md` §27/§26 を参照してください。
- A diagnostics component (`Tsgen.Diagnostics`): pipeline stages return
  diagnostics instead of writing to the console; the CLI deduplicates
  and prints them to stderr at the end.
  診断コンポーネント (`Tsgen.Diagnostics`): パイプラインの各ステージは
  コンソールに直接書き込む代わりに診断情報を返し、CLI が最後に重複排除
  して stderr へ出力します。
- Automated snapshot tests (`tools/run-tests.ps1`): 6 fixtures, 16
  cases.
  自動化されたスナップショットテスト (`tools/run-tests.ps1`):
  6 フィクスチャ・16 ケース。

**Not yet implemented / deferred:**

**未実装 / 先送り:**

- Cycle detection (deliberately deferred — TypeScript interfaces
  tolerate circular references natively, so it isn't load-bearing for
  the current `.d.ts`-only emitter; `docs/DESIGN.md` §3.3), the
  pluggable `ITypeMappingRule` chain (type mapping is a fixed rule set,
  not user-extensible yet), split-file output, and real nested-type
  support. `docs/DESIGN.md` §10.2 has the post-MVP priority order.
  循環参照検出 (あえて先送り — TypeScript の interface は循環参照を
  そのまま許容するため、現状の `.d.ts` 専用エミッターには必須ではない。
  `docs/DESIGN.md` §3.3)、プラガブルな `ITypeMappingRule` チェーン
  (型マッピングは固定のルール集合で、まだユーザー拡張はできない)、
  split-file 出力、nested types の本当のサポート。post-MVP の優先順位は
  `docs/DESIGN.md` §10.2 参照。
- `--mode inertia`'s known v1 gaps: anonymous `new class(...)` literal
  prop values, props built across multiple methods/classes, conditional
  key-setting, and `Inertia.Defer`/`Inertia.Merge` unwrapping — all fall
  back to `unknown` plus a diagnostic rather than a silent guess
  (`HANDOFF.md` §24.6 has the full, deliberate list). Shared Data
  detection is conservative: only `AddInertiaSharedData(...)` is
  scanned; a bare `Inertia.Share(...)` call is detected but excluded
  with a diagnostic, because InertiaNetCore uses that same call both for
  app-global data and for a single page's own extra prop, so the call
  shape alone can't classify it (`HANDOFF.md` §27).
  `--mode inertia` の既知の v1 のギャップ: anonymous な `new
  class(...)` リテラルの props 値、複数メソッド / クラスにまたがって
  構築される props、条件分岐依存のキー設定、`Inertia.Defer`/
  `Inertia.Merge` のアンラップ — いずれも黙って推測せず、`unknown` +
  診断警告にフォールバックします (意図的な全リストは `HANDOFF.md`
  §24.6)。Shared Data 検出は保守的です: スキャン対象は
  `AddInertiaSharedData(...)` のみで、単体の `Inertia.Share(...)`
  呼び出しは検出はするが診断付きで除外します。InertiaNetCore がアプリ
  全体のデータと単一ページ固有の追加 prop の両方に同じ呼び出しを使う
  ため、呼び出しの形だけでは分類できないからです (`HANDOFF.md` §27)。

## Building and Testing / ビルドとテスト

Requirements: RemObjects Elements (the build script assumes 13.0.0.3101
at the default install path — adjust the constants at the top of
`tools/dev-build.ps1` if yours differs), a locally installed .NET 10
SDK, and Windows/PowerShell.

必要環境: RemObjects Elements (ビルドスクリプトは既定のインストール先の
13.0.0.3101 を前提としています — 異なる場合は `tools/dev-build.ps1`
冒頭の定数を調整してください)、ローカルにインストールされた .NET 10
SDK、Windows/PowerShell。

Build with `tools/dev-build.ps1`, **not** `EBuild.exe` directly. EBuild
has a known gap where non-framework references (NuGet or local) are not
fully registered in the generated `deps.json` for Echoes/.NET Core
executables — a plain build compiles fine but the exe fails at launch
with `FileNotFoundException`. The script builds, copies the required
runtime DLLs, and patches `deps.json` (`HANDOFF.md` §10.2/§12.3).

ビルドには `EBuild.exe` を直接使わず、**必ず** `tools/dev-build.ps1` を
使ってください。EBuild には、Echoes/.NET Core 実行ファイルにおいて非
フレームワーク参照 (NuGet またはローカル) が生成される `deps.json` に
完全には登録されないという既知の問題があります — 素のビルドはコンパイル
は通るのに、実行ファイルが起動時に `FileNotFoundException` で失敗
します。スクリプトはビルドし、必要なランタイム DLL をコピーし、
`deps.json` にパッチを当てます (`HANDOFF.md` §10.2/§12.3)。

Run the snapshot tests with `tools/run-tests.ps1`: it builds the CLI and
every fixture under `tests/fixtures/`, then diffs `tsgen` output against
the committed `expected/*.d.ts` snapshots. Pass `-UpdateSnapshots` to
regenerate expectations after an intentional output change.

スナップショットテストは `tools/run-tests.ps1` で実行します: CLI と
`tests/fixtures/` 配下の全フィクスチャをビルドし、`tsgen` の出力を
コミット済みの `expected/*.d.ts` スナップショットと比較します。意図的に
出力を変更した後は `-UpdateSnapshots` を付けて期待値を再生成して
ください。

Note the Trial-license constraints in "License" below before
distributing anything you build.

ビルドしたものを配布する前に、下記「ライセンス」の Trial ライセンス上の
制約を必ず確認してください。

## CLI Usage / CLI の使い方

```
tsgen generate --assembly <path.dll> --source <dir> --out <dir> \
  [--mode assembly|inertia] \
  [--enum-style numeric|union] \
  [--nrt-unknown-policy nullable|non-null|mark-unknown] \
  [--naming-policy camelCase|as-written]
```

Every enum-valued flag rejects an unrecognized value with an error
naming the valid options, rather than silently falling back to a
default.

列挙値を取るフラグは全て、認識できない値を黙って既定値にフォールバック
させず、有効な選択肢を示すエラーで拒否します。

- `--assembly` (required) — path to the built target `.dll`, loaded as
  metadata only via `MetadataLoadContext`.
  (必須) — 対象のビルド済み `.dll` のパス。`MetadataLoadContext` で
  メタデータのみ読み込みます。
- `--source` (required for `--mode inertia`, otherwise optional but
  strongly recommended) — directory containing the target's Oxygene
  `.pas` source. Without it, the CLI warns and every member falls back
  to `--nrt-unknown-policy`'s behavior, since reflection alone cannot
  recover NRT info for Oxygene-authored code at all (see "Why Not an
  Existing Tool" above).
  (`--mode inertia` では必須、それ以外ではオプションだが強く推奨) —
  対象の Oxygene `.pas` ソースが入っているディレクトリ。省略すると CLI
  が警告を出し、全メンバーが `--nrt-unknown-policy` の挙動に
  フォールバックします。Oxygene 製コードの NRT 情報はリフレクション
  だけでは一切復元できないためです (上記「なぜ既存ツールではだめなのか」
  参照)。
- `--out` (required) — output directory; writes `index.d.ts` there.
  (必須) — 出力先ディレクトリ。そこに `index.d.ts` を書き出します。
- `--mode` — `assembly` (default) generates types for every public type
  in the assembly. `inertia` instead scans `--source` for
  `Inertia.Render` call sites and generates the per-page Props /
  `SharedData` / form-error types described in "What It Does" above
  (`docs/DESIGN.md` §3.5, `HANDOFF.md` §24). Its resolution scope is
  deliberately narrow in v1: a prop value is resolved only if it is a
  literal, a parameter/local-variable reference, or a non-generic
  `new NamedType(...)`/`new NamedType` expression, assigned via
  `props['key'] := value;` in the *same* method as the `Render` call —
  the only pattern real Oxygene code can produce, since Oxygene has no
  working object/collection-initializer syntax (`HANDOFF.md` §22.3).
  Anything else falls back to `unknown` plus a diagnostic naming the
  key (see "Current Status" for the list). A props-less page's
  form-error type falls back to `Partial<Record<never, string>>`.
  `assembly` (既定) はアセンブリ内の全ての公開型の型を生成します。
  `inertia` は代わりに `--source` を走査して `Inertia.Render` 呼び出し
  箇所を検出し、上記「何をするツールか」で説明したページごとの Props /
  `SharedData` / フォームエラー型を生成します (`docs/DESIGN.md` §3.5、
  `HANDOFF.md` §24)。v1 の解決範囲は意図的に狭くしてあります: props 値
  が解決されるのは、リテラル、パラメータ / ローカル変数への参照、
  非 generic の `new NamedType(...)`/`new NamedType` 式のいずれかで、
  かつ `Render` 呼び出しと*同じ*メソッド内で `props['key'] := value;`
  という形で代入されている場合のみです — Oxygene には動作する
  オブジェクト / コレクション初期化子構文が存在しないため、実際の
  Oxygene コードが生成しうる唯一のパターンです (`HANDOFF.md` §22.3)。
  それ以外は `unknown` とキー名を含む診断警告にフォールバックします
  (一覧は「現在のステータス」参照)。props なしページのフォームエラー型
  は `Partial<Record<never, string>>` にフォールバックします。
- `--enum-style` — `numeric` (default, `export enum Foo { A = 0, ... }`)
  or `union` (`export type Foo = "A" | "B" | ...;`).
  `numeric` (既定、`export enum Foo { A = 0, ... }`) または `union`
  (`export type Foo = "A" | "B" | ...;`)。
- `--nrt-unknown-policy` — how to render a member whose nullability is
  still genuinely `Unknown` after the provider chain runs. An explicit
  `nullable`/`not nullable` annotation always wins regardless of this
  flag, and an unannotated *value-typed* member (`Int32`, `Boolean`,
  `DateTime`, `Guid`, ...) resolves to non-nullable automatically — only
  unannotated *reference-typed* members are affected.
  プロバイダチェーンを通しても nullability が本当に `Unknown` のままの
  メンバーをどう出力するかを指定します。明示的な `nullable`/`not
  nullable` 注釈はこのフラグに関係なく常に優先され、無注釈の*値型*
  メンバー (`Int32`、`Boolean`、`DateTime`、`Guid` 等) は自動的に
  non-nullable に解決されます — 影響を受けるのは無注釈の*参照型*
  メンバーのみです。
  - `nullable` (default) — `T | null`
    (既定) — `T | null`
  - `non-null` — `T`
  - `mark-unknown` — `T; // nrt: unknown` — the same bare type as
    `non-null` plus a trailing comment, since TypeScript has no way to
    express "nullability undetermined" as distinct from "confirmed
    non-nullable"; the comment keeps it visually and grep-ably distinct.
    `non-null` と同じ素の型に末尾コメントを付けたもの — TypeScript には
    「nullability 未確定」を「non-nullable 確定」と区別して表現する手段
    がないため、コメントで目視・grep の両方から区別できるようにして
    います。
- `--naming-policy` — how member/property names are cased in the emitted
  `.d.ts`, applied uniformly regardless of `--mode` (`docs/DESIGN.md`
  §5.1, `HANDOFF.md` §28):
  出力する `.d.ts` でメンバー / プロパティ名をどう変換するかを指定
  します。`--mode` に関わらず一律に適用されます (`docs/DESIGN.md`
  §5.1、`HANDOFF.md` §28):
  - `camelCase` (default) — lowercases the first character
    (`UserId` → `userId`), matching `System.Text.Json`'s default
    `JsonNamingPolicy` — i.e. what ASP.NET Core / InertiaNetCore
    actually send on the wire unless a project reconfigures
    `JsonSerializerOptions`. It does not replicate
    `JsonNamingPolicy.CamelCase`'s acronym-run handling (a property
    literally named `ID`) — a known, accepted v1 simplification.
    (既定) — 先頭の1文字を小文字化します (`UserId` → `userId`)。
    `System.Text.Json` の既定 `JsonNamingPolicy` に一致 — つまり、
    プロジェクトが `JsonSerializerOptions` を再設定しない限り ASP.NET
    Core / InertiaNetCore が実際にワイヤー上で送る形です。
    `JsonNamingPolicy.CamelCase` の頭字語連続の扱い (`ID` という名前の
    プロパティ等) は再現しません — 既知の、受容された v1 の簡略化です。
  - `as-written` — emits names exactly as written in the Oxygene source.
    Oxygene ソースに書かれた表記のまま出力します。

## Documentation / ドキュメント

- [`docs/DESIGN.md`](docs/DESIGN.md) (English, canonical) /
  [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md) (日本語) — the full design:
  architecture, type-mapping layer, cycle detection, NRT strategy,
  plugin mechanism, output pipeline, CI design, and the MVP boundary.
  Go here for "why is it designed this way?".
  [`docs/DESIGN.md`](docs/DESIGN.md) (英語、正本) /
  [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md) (日本語) — 設計の全体:
  アーキテクチャ、型マッピング層、循環参照検出、NRT 方針、プラグイン
  機構、出力パイプライン、CI 設計、MVP の境界線。「なぜこの設計なのか」
  はこちらへ。
- [`HANDOFF.md`](HANDOFF.md) (English) / [`HANDOFF_jp.md`](HANDOFF_jp.md)
  (日本語) — the session-by-session build log: what was verified
  hands-on, individual decisions and their rationale, bugs found and
  fixed, known limitations, and the current task priority list. The
  `§N` references throughout this README point here.
  [`HANDOFF.md`](HANDOFF.md) (英語) / [`HANDOFF_jp.md`](HANDOFF_jp.md)
  (日本語) — セッションごとの作業ログ: 実機で検証した内容、個々の判断と
  その理由、発見・修正したバグ、既知の制限、現在のタスク優先順位。本
  README 中の `§N` 参照はこのファイルを指します。
- [`CLAUDE.md`](CLAUDE.md) — repo and architecture guidance for AI
  coding agents working on this project.
  [`CLAUDE.md`](CLAUDE.md) — このプロジェクトで作業する AI コーディング
  エージェント向けのリポジトリ・アーキテクチャ解説。

## Directory Structure / ディレクトリ構成

```
oxygene-tsgen/
├── README.md
├── LICENSE                      # MIT
├── CLAUDE.md                    # Guidance for AI coding agents / AIエージェント向け解説
├── HANDOFF.md                   # Session-by-session build log (English) / セッションごとの作業ログ (英語版)
├── HANDOFF_jp.md                # Build log (Japanese) / 作業ログ (日本語版)
├── docs/
│   ├── DESIGN.md                # Design document (English, canonical) / 設計書 (英語版、正本)
│   └── DESIGN_jp.md             # Design document (Japanese) / 設計書 (日本語版)
├── reports/
│   └── *-issue-tracker.csv      # Per-session issue log, cross-referenced with HANDOFF.md / セッションごとの課題管理表 (HANDOFF.mdと相互参照)
├── src/Tsgen/                   # CLI implementation (Oxygene) / CLI実装 (Oxygene)
│   ├── Cli/Program.pas          # Argument parsing + pipeline wiring / 引数解析とパイプライン結線
│   ├── Loading/                 # Stage 1: MetadataLoadContext-based assembly loader / Stage 1: MetadataLoadContextベースのアセンブリローダー
│   ├── Nrt/                     # Tokenizer-based NRT source scanner + provider chain / TokenizerベースのNRTソーススキャナ + プロバイダチェーン
│   ├── Inertia/                 # --mode inertia: Inertia.Render call-site scanner + reachability BFS / --mode inertia: Inertia.Render呼び出し検出 + 到達可能性BFS
│   ├── Ir/                      # Stage 2: lightweight IR + generics-aware type mapper / Stage 2: 軽量IR + generics対応型マッパー
│   ├── Emit/DtsEmitter.pas      # Stage 4: single-file .d.ts emitter / Stage 4: 単一ファイル .d.ts エミッター
│   ├── Diagnostics/             # Pipeline-stage diagnostics / パイプラインステージの診断情報
│   └── Tsgen.elements           # Project file / プロジェクトファイル
├── tests/fixtures/              # Snapshot-test fixtures (.pas + cases.json + expected/*.d.ts) / スナップショットテストのフィクスチャ
├── tools/
│   ├── dev-build.ps1            # Build wrapper working around an EBuild deps.json gap / EBuildのdeps.jsonの穴を回避するビルドラッパー
│   └── run-tests.ps1            # Snapshot-test runner / スナップショットテストランナー
└── .github/
    └── workflows/               # CI (placeholder only for now) / CI (現時点ではplaceholderのみ)
```

## License / ライセンス

[MIT License](LICENSE) — this covers the tool's own source code.

[MIT License](LICENSE) — これは本ツール自体のソースコードに対する
ライセンスです。

The project is currently built with a **Trial** edition of RemObjects
Elements. Distributing anything built with the Trial edition requires at
least a Personal or Academic license (confirmed directly with the
vendor, `HANDOFF.md` §9) — because this project is built under a Trial
license, **we do not publish built binaries.** Publishing the source
code itself is fine — RemObjects explicitly welcomed it. If you clone
and build this project yourself under your own Personal, Academic, or
other RemObjects Elements license, you may distribute the resulting
binaries under the terms of that license.

本プロジェクトは現在 RemObjects Elements の **Trial 版**でビルドして
います。Trial 版でビルドした成果物の配布には、少なくとも Personal
または Academic ライセンスが必要です (ベンダーに直接確認済み、
`HANDOFF.md` §9) — 本プロジェクトは Trial ライセンスでビルドしている
ため、**私たちはビルド済みバイナリを公開しません。** ソースコード自体
の公開は問題ありません — RemObjects も明示的に歓迎しています。ご自身が
Personal・Academic 等の RemObjects Elements ライセンスをお持ちで、
本プロジェクトをクローンしてビルドされた場合は、そのライセンスの条件に
従ってビルド成果物を配布いただけます。
