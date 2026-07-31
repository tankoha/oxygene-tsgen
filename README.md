# oxygene-tsgen

> .NET assembly → TypeScript type definition (`.d.ts`) generator CLI, written in
> Oxygene (RemObjects Elements, .NET / Echoes target).
> **Status: design phase complete, implementation not yet started.** See
> [`docs/DESIGN.md`](docs/DESIGN.md) for the full design and
> [`HANDOFF.md`](HANDOFF.md) for open questions and the Phase 2 starting point.

## これは何か

.NET アセンブリ (`*.dll`) を読み込み、そこに含まれる型情報 (クラス、インターフェース、
enum、ジェネリクス、nullable参照型、属性、XMLドキュメントコメント等) をもとに
TypeScript の型定義ファイル (`.d.ts`) を生成する CLI ツールです。

将来的には型定義だけでなく、以下も生成対象に含める設計になっています
(詳細は [`docs/DESIGN.md`](docs/DESIGN.md) 参照):

- `System.Text.Json` の属性等を反映したプロパティ名変換、`[Obsolete]` →
  `@deprecated` などのメタデータ反映
- バリデーション属性 (`[Required]`, `[Range]` 等) から zod/io-ts のような
  ランタイム検証スキーマの生成
- OpenAPI仕様と連携したエンドポイント単位の TypeScript API クライアント
  (fetch ラッパー) 生成
- インクリメンタル生成、Watchモード、CIでの生成物差分チェック

実装言語には [RemObjects Elements](https://www.remobjects.com/elements/) の
Oxygene (Object Pascal 系言語、.NET ターゲットの Echoes バックエンドを使用) を
使用します。

## 想定ユースケース

- .NET バックエンド (ASP.NET Core 等) の DTO/エンティティ定義を単一の真実源とし、
  TypeScript フロントエンドの型を自動生成して手動同期によるドリフトを防ぐ。
- 既存の OpenAPI 生成パイプラインでは表現しきれない nullable / ジェネリクス /
  enum の精度を、アセンブリのリフレクション情報から直接補う。
- .NET ライブラリを社内 SDK として配布する際、TypeScript 版クライアントも
  同時に自動生成する。

## 現在のステータス

**Phase 1 (設計フェーズ) 完了。実装 (Phase 2) は未着手です。**

このリポジトリには現時点で実装コードは含まれていません。
`src/`, `tests/` はディレクトリのみ用意されており、内容は空です。

- 設計書: [`docs/DESIGN.md`](docs/DESIGN.md)
  — アーキテクチャ、型マッピング層、循環参照検出、NRT解析方針、プラグイン機構、
  出力パイプライン、CI設計、MVPスコープと実装順序の提案を含みます。
- 申し送り事項: [`HANDOFF.md`](HANDOFF.md)
  — 設計判断で迷った点、Oxygeneの `System.Reflection` 互換性に関する
  未検証事項、Phase 2で最初に着手すべきタスクの優先順位。

## MVP (Phase 2 最初の到達目標)

- 基本型マッピング (プリミティブ型、既知のBCL型)
- enum (数値 or 文字列リテラルUnion、設定で選択)
- nullable参照型の反映
- 名前空間 → ESモジュール階層での `.d.ts` 出力

詳細は [`docs/DESIGN.md` §10](docs/DESIGN.md#10-mvp-scope-and-the-boundary-for-future-extensions)
を参照してください。

## ディレクトリ構成

```
oxygene-tsgen/
├── README.md
├── LICENSE                   # MIT
├── HANDOFF.md                 # セッション間の申し送り事項
├── docs/
│   ├── DESIGN.md               # 設計書 (Phase 1 成果物、英語版)
│   └── DESIGN_jp.md            # 設計書 (日本語版)
├── src/                       # 実装 (Phase 2、現時点では空)
├── tests/                     # テスト (Phase 2、現時点では空)
└── .github/
    └── workflows/             # CI (Phase 2、現時点ではplaceholderのみ)
```

## ライセンス

[MIT License](LICENSE)
