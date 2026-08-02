# oxygene-tsgen

> .NET assembly → TypeScript type definition (`.d.ts`) generator CLI, written in
> Oxygene (RemObjects Elements, .NET / Echoes target). Primary use case:
> generating Props types for **Inertia.js** page components (ASP.NET Core +
> Inertia.js) directly from controller code — see "What Is This?" below.
> **Status: Phase 1 (design) is complete, and Phase 2 (implementation) has a
> working, snapshot-tested CLI**, including a v1 of the Inertia.js-specific
> entry-point mode that is this tool's actual primary use case
> (`--mode inertia`: discovers `Inertia.Render` call sites and generates a
> Props interface per page, plus only the types actually reachable from
> them). It only resolves a constrained set of prop-value shapes so far
> (literals, parameter/local references, simple `new Type(...)`
> constructions — see "CLI Usage" below for the exact scope), and Shared
> Data merging / form-error types are not implemented yet. See "CLI Usage"
> and "Current Status" below for what actually exists today,
> [`docs/DESIGN.md`](docs/DESIGN.md) (English) /
> [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md) (日本語) for the full design, and
> [`HANDOFF.md`](HANDOFF.md) for the detailed build log and open questions.
>
> .NET アセンブリ → TypeScript 型定義 (`.d.ts`) 生成 CLI ツール。Oxygene
> (RemObjects Elements, .NET / Echoes ターゲット) で実装。主な用途は、
> ASP.NET Core + **Inertia.js** 構成のControllerコードから、Inertia.jsページ
> コンポーネント向けのProps型を直接生成することです (詳細は下記「これは何か」参照)。
> **現在のステータス: Phase 1 (設計) は完了し、Phase 2 (実装) は
> スナップショットテスト済みの動くCLIがあります**。このツール本来の主な
> 用途であるInertia.js固有のエントリーポイントモードのv1も含みます
> (`--mode inertia`: `Inertia.Render`呼び出し箇所を検出し、ページごとに
> Props interfaceと、そこから実際に到達可能な型だけを生成)。今のところ
> 解決できるprops値の形は限定的です (リテラル、パラメータ/ローカル変数
> への参照、単純な`new Type(...)`構築など — 正確な範囲は下記「CLIの
> 使い方」参照)。共有データのマージやフォームエラー型はまだ未実装です。
> 現時点で実際に存在するものは下記「CLIの使い方」
> 「現在のステータス」を、設計の詳細は
> [`docs/DESIGN.md`](docs/DESIGN.md) (英語) /
> [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md) (日本語)を、詳細な作業ログと
> 未解決事項は [`HANDOFF.md`](HANDOFF.md) を参照してください。

## What Is This? / これは何か

A CLI tool that reads .NET assemblies (`*.dll`) via reflection and generates
TypeScript types. Following a recent scope narrowing (see
[`HANDOFF.md`](HANDOFF.md) §6), its **primary use case is generating TypeScript
Props types for Inertia.js page components** in ASP.NET Core + Inertia.js
applications: it locates `Inertia.Render(componentName, data)` calls in
controller code and generates the TypeScript type for `data` as the Props type
consumed by the corresponding frontend page component (e.g.
`resources/js/Pages/PageName.tsx`) — together with related "shared data" and
form-validation-error types (see below). **Note**: the target ASP.NET Core
Inertia adapter is **InertiaNetCore**, and the target frontend framework is
**React** (both decided 2026-08-01) — see
[`docs/DESIGN.md` §11](docs/DESIGN.md#11-open-questions) /
[`HANDOFF.md` §6.4](HANDOFF.md#64-open-questions).

.NET アセンブリ (`*.dll`) をリフレクションで読み込み、TypeScript の型を生成する
CLI ツールです。最近のスコープ絞り込み ([`HANDOFF.md`](HANDOFF.md) §6 参照) により、
**主な用途は ASP.NET Core + Inertia.js 構成のアプリケーションにおける、Inertia.js
ページコンポーネント向け TypeScript Props型の生成**になりました。Controllerコード中の
`Inertia.Render(componentName, data)` 呼び出しを検出し、対応するフロントエンド側ページ
コンポーネント (例: `resources/js/Pages/PageName.tsx`) が受け取るProps型として `data`
の型を生成します。あわせて、関連する「共有データ」型やフォームバリデーションエラー型も
生成対象です (下記参照)。**なお**、採用するASP.NET Core向けInertiaアダプタは
**InertiaNetCore**、想定フロントエンドフレームワークは**React**にそれぞれ
決定しました (2026-08-01)。詳細は
[`docs/DESIGN.md` §11](docs/DESIGN.md#11-open-questions) /
[`HANDOFF.md` §6.4](HANDOFF.md#64-open-questions) を参照してください。

Beyond Page Props themselves, the design also covers (see
[`docs/DESIGN.md`](docs/DESIGN.md) / [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md)
for details):

Props型自体に加えて、以下も生成対象に含める設計になっています
(詳細は [`docs/DESIGN.md`](docs/DESIGN.md) / [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md) 参照):

- **Shared Data types**, merging data injected on every page (auth user, flash
  messages, etc. via the Inertia middleware's `share()`-equivalent) with each
  page's own Props
  全ページ共通で注入される「**共有データ**」型 (認証ユーザー、フラッシュメッセージ等。
  Inertiaミドルウェアの `share()` 相当の機構経由) を各ページ固有のPropsとマージ
- **Form/`useForm()` error-shape types**, derived from .NET validation
  attributes (`[Required]`, etc.) for Inertia's client-side `useForm()` hook
  .NETのバリデーション属性 (`[Required]` 等) から導出する、Inertiaのクライアント側
  `useForm()` フック向けの**フォームエラー形状**型
- (Secondary, still supported — see
  [`docs/DESIGN.md` §8.3](docs/DESIGN.md#83-generic-restopenapi-integration-secondary-de-prioritized))
  generic .NET → TypeScript type-definition generation for projects not using
  Inertia.js, runtime validation schemas (zod/io-ts) from validation
  attributes, and per-endpoint TypeScript API client (fetch wrapper)
  generation integrated with an OpenAPI spec
  (副次的、引き続きサポート — [`docs/DESIGN.md` §8.3](docs/DESIGN.md#83-generic-restopenapi-integration-secondary-de-prioritized)
  参照) Inertia.jsを使わないプロジェクト向けの汎用 .NET → TypeScript 型定義生成、
  バリデーション属性からの zod/io-ts ランタイム検証スキーマ生成、OpenAPI仕様と連携した
  エンドポイント単位の TypeScript API クライアント (fetch ラッパー) 生成

The implementation language is Oxygene from [RemObjects
Elements](https://www.remobjects.com/elements/) (an Object Pascal-family
language, using the Echoes backend for the .NET target).

実装言語には [RemObjects Elements](https://www.remobjects.com/elements/) の
Oxygene (Object Pascal 系言語、.NET ターゲットの Echoes バックエンドを使用) を
使用します。

## Intended Use Cases / 想定ユースケース

- Auto-generate the Props type for an Inertia.js page component directly from
  the ASP.NET Core controller action that renders it via
  `Inertia.Render(componentName, data)`, instead of hand-maintaining a
  duplicate shape on the frontend that can silently drift from the backend.
  ASP.NET CoreのControllerアクションが `Inertia.Render(componentName, data)`
  でレンダリングするInertia.jsページコンポーネントのProps型を、フロントエンド側で
  手動で二重管理してドリフトさせるのではなく、Controllerコードから直接自動生成する。
- Merge each page's own Props with "shared data" injected on every page (auth
  user, flash messages, etc.) into a single, consistent type.
  各ページ固有のPropsと、全ページに注入される「共有データ」(認証ユーザー、
  フラッシュメッセージ等) を単一の一貫した型にマージする。
- Generate the field-name → error-message shape for Inertia's `useForm()`
  client hook directly from .NET validation attributes (`[Required]`, etc.),
  keeping frontend form-error handling in sync with backend validation without
  hand-maintained duplication.
  Inertiaの `useForm()` クライアントフック向けの、フィールド名→エラーメッセージの
  型を .NET側のバリデーション属性 (`[Required]` 等) から直接生成し、フロントエンド側の
  フォームエラー処理をバックエンドのバリデーションと手動同期せずに済むようにする。
- (Secondary, for projects not using Inertia.js) Treat DTO/entity definitions
  in a .NET backend more generally as the single source of truth, and
  auto-generate TypeScript frontend types to prevent drift from manual
  syncing — see [`docs/DESIGN.md` §8.3](docs/DESIGN.md#83-generic-restopenapi-integration-secondary-de-prioritized)
  for this now-secondary generic REST/OpenAPI-integrated mode.
  (副次的、Inertia.jsを使わないプロジェクト向け) より一般的に、.NET バックエンドの
  DTO/エンティティ定義を単一の真実源とし、TypeScript フロントエンドの型を自動生成して
  手動同期によるドリフトを防ぐ。この、今では副次的な汎用REST/OpenAPI連携モードの詳細は
  [`docs/DESIGN.md` §8.3](docs/DESIGN.md#83-generic-restopenapi-integration-secondary-de-prioritized)
  参照。

## Current Status / 現在のステータス

**Phase 1 (design) is complete. Phase 2 (implementation) has a working CLI,
hardened well past the original MVP bullet list, now including a v1 of
the Inertia.js entry-point mode that is this tool's actual primary use
case.**

**Phase 1 (設計) は完了。Phase 2 (実装) は、当初のMVP箇条書きをかなり
超えてハードニングされた動くCLIがあり、このツール本来の主な用途である
Inertia.jsエントリーポイントモードのv1も含みます。**

**Implemented (`src/Tsgen`, see [`CLAUDE.md`](CLAUDE.md) and
[`HANDOFF.md`](HANDOFF.md) §12–§24 for the full build log):**

- Stage 1 Loader — metadata-only assembly loading via
  `System.Reflection.MetadataLoadContext` (no execution of target code).
  Skips non-public/nested/generic-*definition* types, with a warning
  naming the count.
- NRT (nullable reference type) resolution via a swappable
  `INullabilityProvider` chain (`docs/DESIGN.md` §4.2): a
  Tokenizer-based Oxygene source scan (`--source <dir>`) as the primary
  provider, falling back to "known CLR value types (including
  `Nullable<T>`) are non-nullable/nullable by default" for anything the
  scan has no opinion on — the `Nullable<T>` half of that works from
  reflection alone, no `--source` needed. Handles multi-type `type`
  sections and indexer-style properties; nested types are a known,
  documented gap (`HANDOFF.md` §18.1/§20).
- Stage 2 IR — a lightweight intermediate representation carrying a
  structural CLR type reference (`RawTypeRef`: arrays, generic
  arguments) and tri-state nullability, unresolved until the emitter.
- Stage 3/4 type mapping + emitter — generics (`List<T>`-family → `T[]`,
  `Dictionary<K,V>`-family → `Record<K,V>`, `Nullable<T>`/`Task<T>`/
  `ValueTask<T>` unwrapping), references between the tool's own emitted
  types, and single-file `.d.ts` output with a choice of enum style and
  NRT-unknown-member policy (see "CLI Usage" below). The full pluggable
  `ITypeMappingRule` chain is not yet implemented — type mapping is a
  fixed set of rules, not user-extensible yet.
- **`--mode inertia`**: entry-point-driven discovery (`docs/DESIGN.md`
  §3.5) — finds `Inertia.Render` call sites, resolves the props shape
  built up via `props['key'] := value;` assignments in the same method,
  and emits only the types actually reachable from them. See "CLI Usage"
  below for the exact value-expression shapes it resolves today.
- A `Tsgen.Diagnostics` component: pipeline stages return diagnostics
  instead of writing to the console directly, deduplicated and printed to
  stderr by the CLI.
- Automated snapshot tests (`tools/run-tests.ps1`): 6 fixtures, 14 cases.

**実装済み (`src/Tsgen`。詳細な作業ログは [`CLAUDE.md`](CLAUDE.md) と
[`HANDOFF.md`](HANDOFF.md) §12–§24 を参照):**

- Stage 1 Loader — `System.Reflection.MetadataLoadContext` によるメタデータ
  のみのアセンブリ読み込み (対象コードを実行しない)。非public/nested/
  generic*定義*型はスキップし、件数を警告として表示。
- NRT (nullable参照型) の解決は、差し替え可能な `INullabilityProvider`
  チェーン (`docs/DESIGN.md` §4.2) 経由: Tokenizerベースの Oxygene
  ソーススキャン (`--source <dir>`) を主プロバイダとし、スキャンが
  判定できないものについては「既知のCLR値型(`Nullable<T>`を含む)は
  既定でnon-nullable/nullable」にフォールバックする — `Nullable<T>`側は
  `--source`なしでもreflectionだけで動作する。1つの`type`セクション内の
  複数型宣言やindexer形式のプロパティに対応。nested typesは既知の、
  文書化済みの未対応事項 (`HANDOFF.md` §18.1/§20)。
- Stage 2 IR — 構造化されたCLR型参照(`RawTypeRef`: 配列、generic引数)と
  三値のnullabilityを、Emitterまで未解決のまま運ぶ軽量な中間表現。
- Stage 3/4 型マッピング + Emitter — generics(`List<T>`系 → `T[]`、
  `Dictionary<K,V>`系 → `Record<K,V>`、`Nullable<T>`/`Task<T>`/
  `ValueTask<T>`のアンラップ)、このツール自身が出力する型同士の参照、
  そしてenumスタイルとNRT-unknownメンバーのポリシーを選択できる単一
  ファイルの`.d.ts`出力(下記「CLIの使い方」参照)。完全にプラガブルな
  `ITypeMappingRule`チェーンは未実装 — 型マッピングは固定のルール集合で
  あり、まだユーザー拡張はできない。
- **`--mode inertia`**: エントリーポイント駆動の型発見
  (`docs/DESIGN.md` §3.5)— `Inertia.Render`呼び出し箇所を見つけ、
  同じメソッド内の`props['key'] := value;`という代入で組み立てられた
  propsの形状を解決し、そこから実際に到達可能な型だけを出力する。
  今日解決できる正確な値の式の形は下記「CLIの使い方」参照。
- `Tsgen.Diagnostics`コンポーネント: パイプラインの各ステージはコンソール
  に直接書き込む代わりに診断情報を返し、CLIが重複排除した上でstderrへ
  出力する。
- 自動化されたスナップショットテスト (`tools/run-tests.ps1`): 6フィクスチャ・
  14ケース。

**Not yet implemented / 未実装:**

- Shared Data merging and form-error types (`docs/DESIGN.md` §2.6 items
  2–3) — the other two Inertia-specific targets alongside Page Props.
- Cycle detection (deliberately deferred — not load-bearing for the
  current `.d.ts`-only emitter, `docs/DESIGN.md` §3.3), the pluggable
  type-mapping/plugin chain, split-file output, real nested-type support
  (`docs/DESIGN.md` §10.2 has the post-MVP priority order).
- `--mode inertia`'s own known v1 gaps: `new class(...)` anonymous-literal
  prop values, props built across multiple methods/classes, conditional
  key-setting, `Inertia.Defer`/`Inertia.Merge` unwrapping (`HANDOFF.md`
  §24.6 has the full list).

- 共有データのマージとフォームエラー型 (`docs/DESIGN.md` §2.6の項目
  2–3) — Page Propsと並ぶ、残り2つのInertia固有ターゲット。
- 循環参照検出 (あえて先送り — 現状の`.d.ts`専用Emitterにとっては
  必須ではないため、`docs/DESIGN.md` §3.3)、プラガブルな型マッピング/
  pluginチェーン、split-file出力、nested typesの本当のサポート
  (post-MVPの優先順位は `docs/DESIGN.md` §10.2 参照)。
- `--mode inertia`自身の既知のv1のギャップ: `new class(...)`による
  anonymousリテラルのprops値、複数メソッド/クラスにまたがって構築される
  props、条件分岐依存のキー設定、`Inertia.Defer`/`Inertia.Merge`の
  アンラップ (完全な一覧は`HANDOFF.md` §24.6)。

- Design document: [`docs/DESIGN.md`](docs/DESIGN.md) (English) /
  [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md) (日本語)
  — covers the architecture, type mapping layer, cycle detection, NRT
  analysis policy, plugin mechanism, output pipeline, CI design, and a
  proposed MVP scope and implementation order.
  設計書: [`docs/DESIGN.md`](docs/DESIGN.md) (英語) /
  [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md) (日本語)
  — アーキテクチャ、型マッピング層、循環参照検出、NRT解析方針、プラグイン機構、
  出力パイプライン、CI設計、MVPスコープと実装順序の提案を含みます。
- Handoff notes: [`HANDOFF.md`](HANDOFF.md)
  — the full session-by-session build log: what was verified hands-on,
  design decisions and why, bugs found and fixed, and the current task
  priority list.
  申し送り事項: [`HANDOFF.md`](HANDOFF.md)
  — セッションごとの詳細な作業ログ: 実機で検証した内容、設計判断とその理由、
  発見・修正したバグ、現在のタスク優先順位。

## CLI Usage / CLIの使い方

Build with `tools/dev-build.ps1` (not `EBuild.exe` directly — see
[`CLAUDE.md`](CLAUDE.md) for why), then run:

`tools/dev-build.ps1` でビルドしてください (`EBuild.exe` を直接使わない
理由は [`CLAUDE.md`](CLAUDE.md) 参照)。ビルド後は以下のように実行します:

```
tsgen generate --assembly <path.dll> --source <dir> --out <dir> \
  [--mode assembly|inertia] \
  [--enum-style numeric|union] \
  [--nrt-unknown-policy nullable|non-null|mark-unknown]
```

- `--mode` — `assembly` (default) generates types for every public type in
  the assembly, as described throughout this section. `inertia` instead
  scans `--source` for `Inertia.Render(componentName, propsVar)` call
  sites and generates one Props interface per call site plus only the
  types actually reachable from them (`docs/DESIGN.md` §3.5, `HANDOFF.md`
  §24) — this is the tool's actual primary use case ("What Is This?"
  above), but is newer and narrower in scope than `assembly` mode: it
  only resolves prop values that are literals, a parameter/local variable
  reference, or a non-generic `new NamedType(...)`/`new NamedType`
  expression, built up via `var props := new InertiaProps; props['key']
  := value; ...` in the *same* method as the `Render` call (the only
  pattern Oxygene can actually produce — it has no working object/
  collection-initializer syntax, see `HANDOFF.md` §22.3). Anything else
  (anonymous `new class(...)` literals, props assembled across multiple
  methods, conditional key-setting, `Inertia.Defer`/`Inertia.Merge`) is
  not yet resolved and falls back to `unknown` plus a diagnostic naming
  the key, rather than a silent guess. `--mode inertia` requires
  `--source` (there is nothing to scan without it).
  `assembly`(既定)は、このセクション全体で説明している通り、アセンブリ内の
  全ての公開型に対して型を生成する。`inertia`は代わりに`--source`を走査して
  `Inertia.Render(componentName, propsVar)`呼び出し箇所を検出し、呼び出し
  箇所ごとに1つのProps interfaceと、そこから実際に到達可能な型だけを生成
  する(`docs/DESIGN.md` §3.5、`HANDOFF.md` §24)— これはこのツール本来の
  主な用途(上記「これは何か」参照)だが、`assembly`モードより新しく、対応
  範囲も狭い: 解決できるprops値は、リテラル、パラメータ/ローカル変数への
  参照、非genericの`new NamedType(...)`/`new NamedType`式のみで、
  `Render`呼び出しと*同じ*メソッド内で`var props := new InertiaProps;
  props['key'] := value; ...`という形で構築されたものに限る(Oxygeneが
  実際に生成しうる唯一のパターン — 動作するオブジェクト/コレクション
  初期化子構文が存在しないため、`HANDOFF.md` §22.3参照)。それ以外
  (anonymousな`new class(...)`リテラル、複数メソッドにまたがって組み立て
  られるprops、条件分岐依存のキー設定、`Inertia.Defer`/`Inertia.Merge`)
  はまだ解決できず、黙って推測するのではなく`unknown`とキー名を含む診断
  警告にフォールバックする。`--mode inertia`は`--source`を必須とする
  (それなしでは走査する対象が何もない)。
- `--assembly` (required) — path to the built target `.dll`, loaded as
  metadata only via `MetadataLoadContext`.
  (必須) — 対象の `.dll`。`MetadataLoadContext` でメタデータのみ読み込む。
- `--source` (optional, strongly recommended) — directory containing the
  target's Oxygene `.pas` source. Without it, the CLI warns and every
  member falls back to `--nrt-unknown-policy`'s default, since reflection
  alone cannot recover NRT info for Oxygene-authored code at all (see
  "Known unresolved technical risk" in [`CLAUDE.md`](CLAUDE.md)).
  (オプション、強く推奨) — 対象のOxygene `.pas` ソースが入っている
  ディレクトリ。省略するとCLIが警告を出し、全メンバーが
  `--nrt-unknown-policy` の既定値にフォールバックする。Oxygene製コードは
  reflectionだけではNRT情報を一切復元できないため
  ([`CLAUDE.md`](CLAUDE.md) の「未解決の技術リスク」参照)。
- `--out` (required) — output directory; writes `index.d.ts` there.
  (必須) — 出力先ディレクトリ。そこに `index.d.ts` を書き出す。
- `--enum-style` — `numeric` (default, `export enum Foo { A = 0, ... }`)
  or `union` (`export type Foo = "A" | "B" | ...;`).
  `numeric` (既定、`export enum Foo { A = 0, ... }`) または `union`
  (`export type Foo = "A" | "B" | ...;`)。
- `--nrt-unknown-policy` — how to render a member whose nullability is
  genuinely `Unknown` after the `INullabilityProvider` chain runs (an
  explicit `nullable`/`not nullable` annotation always wins regardless of
  this flag; an unannotated *value-typed* member such as `Int32`/
  `Boolean`/`DateTime`/`Guid` resolves to not-nullable automatically and
  is **not** affected by this flag either — only unannotated
  *reference-typed* members are genuinely `Unknown`):
  「`INullabilityProvider`チェーンを通しても本当に`Unknown`のままの
  メンバーをどう出力するか」を指定 (明示的な`nullable`/`not nullable`
  注釈があれば、このフラグに関係なく常にそちらが優先される。
  `Int32`/`Boolean`/`DateTime`/`Guid`のような無注釈の*値型*メンバーは
  自動的にnon-nullableへ解決されるため、このフラグの影響を**受けない** —
  このフラグが効くのは、無注釈の*参照型*メンバーが本当に`Unknown`の
  場合のみ):
  - `nullable` (default) — `T | null`
  - `non-null` — `T`
  - `mark-unknown` — `T; // nrt: unknown` (bare type, same as `non-null`,
    plus a trailing comment — TypeScript's type system has no way to
    express "nullability undetermined" as distinct from "confirmed
    non-nullable", so a comment is what keeps it visually/grep-ably
    distinct)
    (`non-null`と同じ素の型に、末尾の行コメントを付与したもの —
    TypeScriptの型システムには「nullability未確定」を「non-nullable
    確定」と区別して表現する手段がないため、コメントで目視・grep両方
    から区別できるようにしている)

## MVP (Phase 2 Initial Target) / MVP (Phase 2 最初の到達目標)

**✅ Implemented** — this was the originally-scoped MVP target, and the
actual build now exceeds it (multi-type sections, indexer properties, the
`INullabilityProvider` chain, `mark-unknown`; see "Current Status"
above):

**✅ 実装済み** — これは当初スコープしていたMVPの到達目標であり、
実際のビルドは既にこれを超えています (複数型セクション、indexer
プロパティ、`INullabilityProvider`チェーン、`mark-unknown`など。
上記「現在のステータス」参照):

- Basic type mapping (primitives, known BCL types)
  基本型マッピング (プリミティブ型、既知のBCL型)
- Enums (numeric or string-literal union, selectable via config)
  enum (数値 or 文字列リテラルUnion、設定で選択)
- Reflecting nullable reference types
  nullable参照型の反映
- `.d.ts` output following a namespace → ES module hierarchy (the
  single-file half of this — split-file/ES-module output is still
  post-MVP, see `docs/DESIGN.md` §7.3)
  名前空間 → ESモジュール階層での `.d.ts` 出力 (このうち単一ファイル側
  のみ実装済み。split-file/ESモジュール出力は引き続きpost-MVP、
  `docs/DESIGN.md` §7.3 参照)

See [`docs/DESIGN.md` §10](docs/DESIGN.md#10-mvp-scope-and-the-boundary-for-future-extensions)
/ [`docs/DESIGN_jp.md` §10](docs/DESIGN_jp.md#10-mvpスコープと将来拡張の境界線) for details.

詳細は [`docs/DESIGN.md` §10](docs/DESIGN.md#10-mvp-scope-and-the-boundary-for-future-extensions)
/ [`docs/DESIGN_jp.md` §10](docs/DESIGN_jp.md#10-mvpスコープと将来拡張の境界線)
を参照してください。

## Directory Structure / ディレクトリ構成

```
oxygene-tsgen/
├── README.md
├── LICENSE                     # MIT
├── CLAUDE.md                   # Repo/architecture guidance for AI coding agents / AIエージェント向けリポジトリ・アーキテクチャ解説
├── HANDOFF.md                  # Handoff notes (English) / セッション間の申し送り事項 (英語版)
├── HANDOFF_jp.md                # Handoff notes (Japanese) / セッション間の申し送り事項 (日本語版)
├── docs/
│   ├── DESIGN.md                # Design document (English) / 設計書 (英語版)
│   └── DESIGN_jp.md             # Design document (Japanese) / 設計書 (日本語版)
├── reports/
│   └── *-issue-tracker.csv      # Per-session issue log (found/fixed, cross-referenced with HANDOFF.md) / セッションごとの課題管理表 (発見/対応、HANDOFF.mdと相互参照)
├── src/Tsgen/                  # CLI implementation (Oxygene) / CLI実装 (Oxygene)
│   ├── Cli/Program.pas          # Argument parsing + pipeline wiring / 引数解析とパイプライン結線
│   ├── Loading/                 # Stage 1: MetadataLoadContext-based assembly loader / Stage 1: MetadataLoadContextベースのアセンブリローダー
│   ├── Nrt/                     # Tokenizer-based NRT source scanner + INullabilityProvider chain / Tokenizerベースの NRT ソーススキャナ + INullabilityProvider チェーン
│   ├── Inertia/                 # --mode inertia: Inertia.Render call-site scanner + reachability BFS / --mode inertia: Inertia.Render呼び出し検出 + 到達可能性BFS
│   ├── Ir/                      # Stage 2: lightweight IR + generics-aware type mapper / Stage 2: 軽量IR + genericsに対応した型マッパー
│   ├── Emit/DtsEmitter.pas      # Stage 4: single-file .d.ts emitter / Stage 4: 単一ファイル .d.ts エミッター
│   ├── Diagnostics/             # Pipeline-stage diagnostics (see CLAUDE.md) / パイプラインステージの診断情報 (CLAUDE.md参照)
│   └── Tsgen.elements           # Project file / プロジェクトファイル
├── tests/fixtures/              # Snapshot-test fixtures (.pas + cases.json + expected/*.d.ts) / スナップショットテストのフィクスチャ
├── tools/
│   ├── dev-build.ps1            # Build wrapper working around an EBuild deps.json gap / EBuildのdeps.jsonの穴を回避するビルドラッパー
│   └── run-tests.ps1            # Snapshot-test runner / スナップショットテストランナー
└── .github/
    └── workflows/               # CI (Phase 2, placeholder only for now) / CI (Phase 2、現時点ではplaceholderのみ)
```

## License / ライセンス

[MIT License](LICENSE)

This covers the tool's own source code. It is currently built with a
**Trial** edition of RemObjects Elements, which does not permit
distributing built artifacts (binaries) — only source. See
[`HANDOFF.md` §9](HANDOFF.md#9-remobjects-licenseeula-confirmation-vendor-reply-2026-08-01)
for details.

これは本ツール自体のソースコードに対するライセンスです。現在は
RemObjects Elementsの**Trial版**でビルドしており、ビルド成果物
(バイナリ) の配布は許可されていません（ソースのみ配布可）。詳細は
[`HANDOFF_jp.md` §9](HANDOFF_jp.md#9-remobjectsライセンスeula確認-ベンダー回答2026-08-01)
を参照してください。
