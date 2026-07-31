# oxygene-tsgen

> .NET assembly → TypeScript type definition (`.d.ts`) generator CLI, written in
> Oxygene (RemObjects Elements, .NET / Echoes target).
> **Status: design phase complete, implementation not yet started.** See
> [`docs/DESIGN.md`](docs/DESIGN.md) (English) /
> [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md) (日本語) for the full design, and
> [`HANDOFF.md`](HANDOFF.md) for open questions and the Phase 2 starting point.
>
> .NET アセンブリ → TypeScript 型定義 (`.d.ts`) 生成 CLI ツール。Oxygene
> (RemObjects Elements, .NET / Echoes ターゲット) で実装。
> **現在のステータス: 設計フェーズ完了、実装は未着手です。** 設計の詳細は
> [`docs/DESIGN.md`](docs/DESIGN.md) (英語) /
> [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md) (日本語)、未解決事項とPhase 2の
> 着手点は [`HANDOFF.md`](HANDOFF.md) を参照してください。

## What Is This? / これは何か

A CLI tool that reads .NET assemblies (`*.dll`) and generates TypeScript type
definition files (`.d.ts`) based on the type information they contain
(classes, interfaces, enums, generics, nullable reference types, attributes,
XML doc comments, etc.).

.NET アセンブリ (`*.dll`) を読み込み、そこに含まれる型情報 (クラス、インターフェース、
enum、ジェネリクス、nullable参照型、属性、XMLドキュメントコメント等) をもとに
TypeScript の型定義ファイル (`.d.ts`) を生成する CLI ツールです。

The design also covers more than plain type definitions going forward (see
[`docs/DESIGN.md`](docs/DESIGN.md) / [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md)
for details):

将来的には型定義だけでなく、以下も生成対象に含める設計になっています
(詳細は [`docs/DESIGN.md`](docs/DESIGN.md) / [`docs/DESIGN_jp.md`](docs/DESIGN_jp.md) 参照):

- Property name conversion reflecting `System.Text.Json` attributes, and
  metadata mapping such as `[Obsolete]` → `@deprecated`
  `System.Text.Json` の属性等を反映したプロパティ名変換、`[Obsolete]` →
  `@deprecated` などのメタデータ反映
- Generation of runtime validation schemas (zod/io-ts, etc.) from validation
  attributes (`[Required]`, `[Range]`, etc.)
  バリデーション属性 (`[Required]`, `[Range]` 等) から zod/io-ts のような
  ランタイム検証スキーマの生成
- Generation of per-endpoint TypeScript API client functions (fetch wrappers)
  integrated with an OpenAPI spec
  OpenAPI仕様と連携したエンドポイント単位の TypeScript API クライアント
  (fetch ラッパー) 生成
- Incremental generation, watch mode, and CI diff-checking of generated output
  インクリメンタル生成、Watchモード、CIでの生成物差分チェック

The implementation language is Oxygene from [RemObjects
Elements](https://www.remobjects.com/elements/) (an Object Pascal-family
language, using the Echoes backend for the .NET target).

実装言語には [RemObjects Elements](https://www.remobjects.com/elements/) の
Oxygene (Object Pascal 系言語、.NET ターゲットの Echoes バックエンドを使用) を
使用します。

## Intended Use Cases / 想定ユースケース

- Treat DTO/entity definitions in a .NET backend (ASP.NET Core, etc.) as the
  single source of truth, and auto-generate TypeScript frontend types to
  prevent drift from manual syncing.
  .NET バックエンド (ASP.NET Core 等) の DTO/エンティティ定義を単一の真実源とし、
  TypeScript フロントエンドの型を自動生成して手動同期によるドリフトを防ぐ。
- Fill in nullable/generics/enum precision that existing OpenAPI generation
  pipelines can't fully express, sourced directly from assembly reflection
  data.
  既存の OpenAPI 生成パイプラインでは表現しきれない nullable / ジェネリクス /
  enum の精度を、アセンブリのリフレクション情報から直接補う。
- When distributing a .NET library as an internal SDK, auto-generate a
  TypeScript client for it at the same time.
  .NET ライブラリを社内 SDK として配布する際、TypeScript 版クライアントも
  同時に自動生成する。

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
├── HANDOFF.md                 # Handoff notes between sessions / セッション間の申し送り事項
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
