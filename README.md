# oxygene-tsgen

> .NET assembly → TypeScript type definition (`.d.ts`) generator CLI, written in
> Oxygene (RemObjects Elements, .NET / Echoes target). Primary use case:
> generating Props types for **Inertia.js** page components (ASP.NET Core +
> Inertia.js) directly from controller code — see "What Is This?" below.
> **Status: design phase complete, implementation not yet started.** See
> [`docs/DESIGN.md`](docs/DESIGN.md) (English) /
> [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md) (日本語) for the full design, and
> [`HANDOFF.md`](HANDOFF.md) for open questions and the Phase 2 starting point.
>
> .NET アセンブリ → TypeScript 型定義 (`.d.ts`) 生成 CLI ツール。Oxygene
> (RemObjects Elements, .NET / Echoes ターゲット) で実装。主な用途は、
> ASP.NET Core + **Inertia.js** 構成のControllerコードから、Inertia.jsページ
> コンポーネント向けのProps型を直接生成することです (詳細は下記「これは何か」参照)。
> **現在のステータス: 設計フェーズ完了、実装は未着手です。** 設計の詳細は
> [`docs/DESIGN.md`](docs/DESIGN.md) (英語) /
> [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md) (日本語)、未解決事項とPhase 2の
> 着手点は [`HANDOFF.md`](HANDOFF.md) を参照してください。

## What Is This? / これは何か

A CLI tool that reads .NET assemblies (`*.dll`) via reflection and generates
TypeScript types. Following a recent scope narrowing (see
[`HANDOFF.md`](HANDOFF.md) §6), its **primary use case is generating TypeScript
Props types for Inertia.js page components** in ASP.NET Core + Inertia.js
applications: it locates `Inertia.Render(componentName, data)` calls in
controller code and generates the TypeScript type for `data` as the Props type
consumed by the corresponding frontend page component (e.g.
`resources/js/Pages/PageName.tsx`) — together with related "shared data" and
form-validation-error types (see below). **Note**: which ASP.NET Core Inertia
adapter (InertiaNetCore / InertiaCore / inertia-dotnet / etc.) and which
frontend framework (React / Vue / Svelte) to target are still open decisions —
see [`docs/DESIGN.md` §11](docs/DESIGN.md#11-open-questions) /
[`HANDOFF.md` §6.4](HANDOFF.md#64-open-questions).

.NET アセンブリ (`*.dll`) をリフレクションで読み込み、TypeScript の型を生成する
CLI ツールです。最近のスコープ絞り込み ([`HANDOFF.md`](HANDOFF.md) §6 参照) により、
**主な用途は ASP.NET Core + Inertia.js 構成のアプリケーションにおける、Inertia.js
ページコンポーネント向け TypeScript Props型の生成**になりました。Controllerコード中の
`Inertia.Render(componentName, data)` 呼び出しを検出し、対応するフロントエンド側ページ
コンポーネント (例: `resources/js/Pages/PageName.tsx`) が受け取るProps型として `data`
の型を生成します。あわせて、関連する「共有データ」型やフォームバリデーションエラー型も
生成対象です (下記参照)。**なお**、採用するASP.NET Core向けInertiaアダプタ
(InertiaNetCore / InertiaCore / inertia-dotnet 等) や想定フロントエンドフレームワーク
(React / Vue / Svelte) はまだ未決定です。詳細は
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

**Phase 1 (design phase) complete. Implementation (Phase 2) has not started.**

**Phase 1 (設計フェーズ) 完了。実装 (Phase 2) は未着手です。**

This repository does not yet contain any implementation code. `src/` and
`tests/` exist only as empty directories.

このリポジトリには現時点で実装コードは含まれていません。
`src/`, `tests/` はディレクトリのみ用意されており、内容は空です。

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
  — points that were difficult to decide during design, unverified points
  around Oxygene's `System.Reflection` compatibility, and the priority order
  of tasks Phase 2 should tackle first.
  申し送り事項: [`HANDOFF.md`](HANDOFF.md)
  — 設計判断で迷った点、Oxygeneの `System.Reflection` 互換性に関する
  未検証事項、Phase 2で最初に着手すべきタスクの優先順位。

## MVP (Phase 2 Initial Target) / MVP (Phase 2 最初の到達目標)

- Basic type mapping (primitives, known BCL types)
  基本型マッピング (プリミティブ型、既知のBCL型)
- Enums (numeric or string-literal union, selectable via config)
  enum (数値 or 文字列リテラルUnion、設定で選択)
- Reflecting nullable reference types
  nullable参照型の反映
- `.d.ts` output following a namespace → ES module hierarchy
  名前空間 → ESモジュール階層での `.d.ts` 出力

See [`docs/DESIGN.md` §10](docs/DESIGN.md#10-mvp-scope-and-the-boundary-for-future-extensions)
/ [`docs/DESIGN_jp.md` §10](docs/DESIGN_jp.md#10-mvpスコープと将来拡張の境界線) for details.

詳細は [`docs/DESIGN.md` §10](docs/DESIGN.md#10-mvp-scope-and-the-boundary-for-future-extensions)
/ [`docs/DESIGN_jp.md` §10](docs/DESIGN_jp.md#10-mvpスコープと将来拡張の境界線)
を参照してください。

## Directory Structure / ディレクトリ構成

```
oxygene-tsgen/
├── README.md
├── LICENSE                   # MIT
├── HANDOFF.md                 # Handoff notes (English) / セッション間の申し送り事項 (英語版)
├── HANDOFF_jp.md               # Handoff notes (Japanese) / セッション間の申し送り事項 (日本語版)
├── docs/
│   ├── DESIGN.md               # Design document (English) / 設計書 (英語版)
│   └── DESIGN_jp.md            # Design document (Japanese) / 設計書 (日本語版)
├── src/                       # Implementation (Phase 2, currently empty) / 実装 (Phase 2、現時点では空)
├── tests/                     # Tests (Phase 2, currently empty) / テスト (Phase 2、現時点では空)
└── .github/
    └── workflows/             # CI (Phase 2, placeholder only for now) / CI (Phase 2、現時点ではplaceholderのみ)
```

## License / ライセンス

[MIT License](LICENSE)
