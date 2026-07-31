# oxygene-tsgen 設計書 (Phase 1)

**ステータス**: 設計フェーズ完了。実装 (Phase 2) 未着手。
**対象**: 最大構成 (フルスコープ) の設計。MVP範囲は本書末尾で明示する。
**実装言語**: Oxygene (RemObjects Elements, `.NET` ターゲット = **Echoes** バックエンド)。

このドキュメントは「なぜこの設計にしたか」を必ず併記する。理由の記述を省略した箇所はない
(不明な場合は「未決定・要検証」として明記している)。判断に迷った箇所の詳細は
`HANDOFF.md` に整理してあるので、Phase 2 着手時は本書と合わせて読むこと。

---

## 0. 目的とスコープ

### 0.1 目的

.NET アセンブリ (`*.dll`) を `System.Reflection` (相当) で読み込み、TypeScript の型定義
(`*.d.ts`)、および任意でランタイム検証スキーマ (zod/io-ts) や API クライアント関数を
生成する CLI ツール。生成物は Node.js / ブラウザ双方の TypeScript プロジェクトから
利用できることを想定する。

### 0.2 想定ユースケース

- ASP.NET Core などの .NET バックエンドの DTO/エンティティ定義を単一の真実源とし、
  フロントエンド (TypeScript/React/Vue 等) の型を自動生成してドリフトを防ぐ。
- OpenAPI をすでに生成しているプロジェクトで、型情報をより正確に (ジェネリクス・
  nullable・enum など) TypeScript に反映したい場合の代替/補完。
- 社内 SDK として .NET ライブラリを配布しつつ、TypeScript 版クライアントも自動生成したい
  場合。

### 0.3 非目標 (Non-Goals)

- .NET → TypeScript の「トランスパイル」(ロジック/実行コードの変換) は行わない。
  対象はあくまで型・シグネチャ・メタデータであり、メソッド本体は生成しない
  (API 関数のみ、HTTP 呼び出しラッパーとして生成する。詳細は §7)。
- 全ての .NET 型システムの機能を網羅することは目指さない (例: 任意の deep な
  リフレクションのみで表現される動的型、`dynamic`、リフレクション専用の内部型など)。
  未対応の型は明示的に `unknown`/`any` にフォールバックし、警告を出す方針とする
  (詳細は §2.4)。

---

## 1. アーキテクチャ全体図

### 1.1 コンポーネント分割

```mermaid
flowchart TD
    CLI["CLI Frontend<br/>引数解析 / 設定ファイル読込 /<br/>サブコマンドdispatch<br/>(generate, watch, check, init-config)"]
    CFG["Configuration Resolver<br/>tsgen.config.* を読込み、各層のオプションと<br/>プラグイン一覧を確定したResolvedConfigを生成"]
    S1["Stage 1: Assembly Loader<br/>対象+依存アセンブリをメタデータのみで読込<br/>(実行はしない。MetadataLoadContext相当を利用/自作)<br/>出力: RawAssemblyModel"]
    S2["Stage 2: Semantic Analyzer / IR Builder<br/>型・メンバー・属性・XMLドキュメントを統合<br/>NRT解析・循環参照検出・ジェネリクス解決・enum戦略判定<br/>出力: IrAssembly"]
    S3["Stage 3: Type Mapping Layer (Pluggable)<br/>IrType→TsTypeExpressionへの変換ルール解決<br/>組み込み+カスタムオーバーライド+プラグインのチェーン(§3)"]

    subgraph S4["Stage 4: Emitters (出力形式ごとに分離・並列実行可能)"]
        direction LR
        S4DTS["DtsEmitter<br/>(.d.ts生成)"]
        S4SCHEMA["SchemaEmitter<br/>(zod/io-ts等)"]
        S4API["ApiClientEmitter<br/>(fetchラッパー関数生成)"]
    end

    S5["Stage 5: Writer / Diff Engine<br/>ファイル書き出し、または--checkモードで<br/>既存生成物とのdiffのみ計算(CI用)<br/>インクリメンタル生成キャッシュ管理"]

    CLI --> CFG --> S1 --> S2 --> S3 --> S4
    S4DTS --> S5
    S4SCHEMA --> S5
    S4API --> S5

    Watcher["Watcher<br/>(dllのmtime監視 / dotnet build連携)"] -.->|変更検出時にStage1以降を再実行| S1
    PluginHost["Plugin Host<br/>(プラグインの検出・ロード・ライフサイクル管理)"] -.->|拡張ポイントへ登録| S3
    Diag["Diagnostics<br/>(全ステージ共通のログ/警告/エラー収集)"] -.->|未対応型・循環参照の警告等を集約| S2
```

補助コンポーネント (上記パイプラインの外側):

- **Watcher**: ファイルシステム監視 (対象 .dll の mtime、または `dotnet build` 連携)
  → 変更検出時に Stage 1 以降を再実行。
- **Plugin Host**: プラグインの検出・ロード・ライフサイクル管理 (§6)。
- **Diagnostics**: 全ステージ共通のログ/警告/エラー収集 (未対応型のフォールバック、
  循環参照の警告などを一元的に集約し、CLI 終了時にサマリ表示)。

### 1.2 設計判断: なぜ5段階パイプライン+IRを挟むのか

- **理由1 (関心の分離)**: 「.NET のメタデータをどう読むか」と「TypeScript として
  どう表現するか」を混ぜると、リフレクション API の癖 (Oxygene 側の
  `System.Reflection` 互換実装の制約、§4 参照) が出力ロジック全体に染み出し、
  保守性が悪化する。IR を挟むことで、Stage 1/2 の変更 (例: 将来 Roslyn 経由の
  ソース解析を追加する等) が Stage 3/4 に影響しないようにする。
- **理由2 (テスト容易性)**: IR は素朴なデータ構造 (POCO/レコード) なので、
  Stage 3/4 のユニットテストは実アセンブリなしで IR を手組みして実行できる。
  実アセンブリ読み込みが絡む Stage 1/2 のテストと分離できる。
- **理由3 (複数出力形式への対応)**: `.d.ts` / zod スキーマ / API クライアントという
  3種の出力 (§0.2, §7) はいずれも「型が何であるか」という同じ情報を必要とするため、
  共通の IR から分岐させるのが自然。IR がなければ同じ解析ロジック
  (NRT解析、循環参照検出等) を出力形式ごとに重複実装することになる。
- **代替案として検討したもの**: 「Loader が直接 TS AST を組み立てる 2段階パイプライン」
  も検討したが、上記の理由で却下。小規模な CLI ツールとしてはオーバーエンジニアリング
  という意見もあり得るため、MVP (§8) では Stage 2 の一部 (NRT解析等) を簡略化した
  「軽量 IR」から始め、フルスコープの解析は段階的に追加する方針とする。

---

## 2. 型マッピング層の抽象化設計

### 2.1 基本構造

```oxygene
type
  // TypeScript側の型表現。AST寄りだが出力に必要な最小限の情報のみ持つ。
  TsTypeExpression = public class
  public
    Kind: TsTypeKind; // Primitive, Reference, Array, Tuple, Union, Generic, Literal, Function, ...
    Name: String;               // Reference/Generic の場合の型名 (例: "Array", "MyNamespace.Foo")
    TypeArguments: List<TsTypeExpression>; // ジェネリクス実引数
    ElementType: TsTypeExpression;         // Array/Nullable Union の要素型
    UnionMembers: List<TsTypeExpression>;  // Union (nullable は `T | null` として表現)
    LiteralValues: List<String>;           // 文字列リテラルUnion (enum戦略が string の場合)
  end;

  // 型マッピングルール1件の入力/出力契約
  ITypeMappingRule = public interface
    // このルールが IrType を処理できるかどうかを判定する (優先度付きチェーンで使用)
    method CanHandle(aType: IrType; aContext: MappingContext): Boolean;
    // 実際の変換。ネストした型 (ジェネリクス引数等) の解決は
    // aContext.ResolveType() を再帰的に呼び出す (下記2.3参照)
    method Map(aType: IrType; aContext: MappingContext): TsTypeExpression;
  end;
```

### 2.2 ルール解決の優先順位チェーン

```mermaid
flowchart TD
    Q["IrTypeを変換したい"] --> A["① ユーザー定義オーバーライド<br/>(tsgen.configで型のFQN指定)"]
    A -->|マッチせず| B["② プラグイン登録ルール<br/>(登録順、最初にCanHandleしたもの勝ち)"]
    B -->|マッチせず| C1["③a. 特殊ケース<br/>Nullable&lt;T&gt;, Task&lt;T&gt;/ValueTask&lt;T&gt;のunwrap,<br/>KeyValuePair&lt;K,V&gt;等"]
    C1 -->|マッチせず| C2["③b. コレクション<br/>List/IList/IEnumerable→Array,<br/>Dictionary→Record/Map"]
    C2 -->|マッチせず| C3["③c. 既知BCL型<br/>string, int系, bool, DateTime,<br/>Guid, decimal, ..."]
    C3 -->|マッチせず| C4["③d. enum<br/>(数値 or 文字列リテラルUnion, §2.5)"]
    C4 -->|マッチせず| C5["③e. ユーザー定義型<br/>class/struct/record/interface"]
    C5 -->|マッチせず| C6["③f. フォールバック<br/>(unknown + 警告ログ)"]

    A -->|マッチ| R["TsTypeExpression確定"]
    B -->|マッチ| R
    C1 -->|マッチ| R
    C2 -->|マッチ| R
    C3 -->|マッチ| R
    C4 -->|マッチ| R
    C5 -->|マッチ| R
    C6 --> R
```

### 2.3 拡張可能にする理由と設計

- **なぜ「チェーン+CanHandle」方式か**: 単純な `Dictionary<FQN, TsType>` のマップだと
  ジェネリクスや構造的な型 (タプル、配列の配列等) を表現できない。関数的なルール
  (`CanHandle`/`Map`) にすることで、「名前空間が `MyCompany.*` かつジェネリクスで
  `Result<T,E>` の形をしている型は `Result<T> | Error<E>` に変換する」といった
  構造的なマッチングが可能になる。これはプラグイン機構 (§6) の基盤でもある。
- **`MappingContext.ResolveType()` を再帰の入口にする理由**: 個々のルールが
  「自分の直接の型」だけでなく「ネストした型引数の解決」を毎回自前で書くと
  循環参照検出やキャッシュのロジックが重複する。`MappingContext` が
  訪問済み型のスタック (循環検出用、§3) とキャッシュ (同じ型を何度も解決しない)
  を一元管理し、ルール実装者はそれを意識しなくて良いようにする。
- **優先順位を「最初にCanHandleしたもの勝ち」にした理由**: スコア方式 (最も詳細な
  ルールを自動選択) も検討したが、実装が複雑になり、かつルール間の優先順位が
  暗黙的になり事故りやすい (プラグイン作者から見て「なぜ自分のルールが呼ばれないか」
  が分かりにくい)。明示的なチェーン順序の方がデバッグしやすく、設定ファイルで
  ユーザーが優先順位を上書きできる余地も残せる。

### 2.4 未対応型のフォールバック方針

- 変換できない型は `unknown` として出力し、`Diagnostics` に
  `WARN: cannot map type 'X', falling back to unknown` を記録する。
  CI の `--check --strict` モードではこれをエラー扱いにできるオプションを用意する
  (未対応型が知らぬ間に増えることを防ぐため)。
- **理由**: 生成を止めてしまうと「1つの型が読めないだけで全体が失敗する」という
  体験になり、大規模アセンブリでの採用障壁になる。段階的移行 (MVP → フルスコープ)
  の運用とも相性が良い。

### 2.5 enum 戦略 (数値 or 文字列リテラルUnion)

- 設定でグローバルデフォルト (`numeric` | `stringUnion` | `constObject`) を選び、
  型単位で `[TsEnumStrategy(...)]` 相当のカスタム属性、またはFQN指定の設定で
  上書き可能にする。
- `stringUnion` の場合、`[EnumMember(Value = "...")]` (`System.Runtime.Serialization`)
  や `System.Text.Json` の `[JsonStringEnumConverter]` /
  `[JsonPropertyName]` 相当の情報があればそれを文字列値として優先し、
  なければ C# 側のメンバー名をそのまま文字列値にする。
  - **理由**: JSON シリアライズ時の実際の値と TS 型が乖離すると意味がないため、
    シリアライズ属性を可能な限り信頼できる情報源として扱う。

---

## 3. 循環参照検出アルゴリズム

### 3.1 問題設定

TypeScript の `interface`/`type` 宣言自体は相互参照可能 (プロパティの遅延評価的な
性質のため、`interface A { b: B } interface B { a: A }` は問題ない)。
一方で問題になるのは:

1. **型引数の無限展開**: ジェネリクスの「構造的展開」を行う設計 (例: `Result<T,E>`
   を毎回インライン展開するような戦略) を採った場合、再帰的なジェネリクス
   (`TreeNode<T>` が `Children: List<TreeNode<T>>` を持つ、など) で無限ループする。
2. **zod/io-ts スキーマ生成**: ランタイム検証スキーマは「値」として定義されるため、
   TypeScript の型と違って遅延参照に工夫が要る (`z.lazy(() => schema)` 等)。
   循環を検出し、該当箇所を `lazy` 化する必要がある。
3. **単一ファイル出力時のトポロジカルソート**: 依存順に型定義を並べたい場合
   (可読性のため。TS的には順不同でも動くが人間が読みやすい方が良い)、循環がある
   グループはまとめて出力する必要がある。

### 3.2 アルゴリズム案

型を頂点、"直接参照" (プロパティ/フィールド/戻り値/引数の型として出現する) を
辺とする有向グラフに対し、**Tarjan の強連結成分分解 (SCC)** を IR構築の後処理
(Stage 2 の最終工程) として1回実行する。

```mermaid
flowchart TD
    In["入力: IrAssembly.Types<br/>(すべてのIrType)"] --> Edges["① 各IrTypeの直接依存(辺)を収集<br/>・プロパティ/フィールドの型(ジェネリクス引数含む)<br/>・基底クラス/実装インターフェース<br/>・ユーザー定義型のみ(BCL型は辺を張らない)"]
    Edges --> Tarjan["② Tarjan法 O(V+E) でSCCを求める"]
    Tarjan --> Check{"③ SCCのサイズが1かつ<br/>自己ループなし?"}
    Check -->|Yes| NotCyclic["IsCyclic = false"]
    Check -->|No| Cyclic["IsCyclic = true"]
    NotCyclic --> Topo["④ SCCを1頂点とみなしたDAG上で<br/>トポロジカルソートし出力順を確定"]
    Cyclic --> Topo
    Topo --> Out["出力: 各IrTypeの<br/>SccId / IsCyclic / TopologicalOrder"]
```

### 3.3 検出結果の使い道 (Emitter側の分岐)

- **DtsEmitter**: `interface`/`type` は循環があってもそのまま出力可能なため、
  基本的に `IsCyclic` を無視できる。ただし「型を構造的にインライン展開する」設定
  (例: タプル的な匿名型展開) を使う場合のみ、循環を検出したら強制的に名前付き型
  として切り出す (展開をやめる) フォールバックを行う。
- **SchemaEmitter (zod)**: `IsCyclic = true` の型は `z.lazy(() => ...)` で包み、
  かつ TypeScript の型注釈 (`z.ZodType<T>`) を明示することで zod の型推論の限界を
  回避する。circular でない型は通常通り即時評価の式で生成し、可読性を優先する。
- **単一ファイル出力**: SCC単位でグループ化して出力順を決定 (§3.2 手順4)。

### 3.4 なぜこの設計か

- Tarjan法を選んだ理由: 循環検出だけなら単純なDFSの「訪問中」フラグでも十分だが、
  「循環しているグループをまとめて扱う」(zodのlazy化やトポロジカル順出力) には
  SCC分解の結果 (グループ単位のまとまり) がそのまま使えるため、最初からSCCベースで
  設計する方が後工程との整合性が良い。DFSベースの単純な検出だと「循環に含まれる
  型集合」を再度別ロジックで求め直す二度手間になる。
- 計算量: O(V+E) で、アセンブリ中の型数が数千規模でも実用上問題にならない想定。
  実測はPhase 2で確認 (大規模アセンブリでのベンチマークをタスクリストに追加、
  HANDOFF.md参照)。

---

## 4. NRT (Nullable Reference Types) 解析方針

### 4.1 調査結果のサマリ (Web調査ベース)

このセクションは Web 検索ツールを用いて調査した内容と、調査で確認できなかった
(=未検証・要実機検証) 部分を明確に分けて記載する。

**確認できたこと:**

- C# の Nullable Reference Types (NRT) は言語機能であり、CLR自体には
  nullability の概念がない。Roslyn (C#コンパイラ) は `?`/非`?` の情報を
  `System.Runtime.CompilerServices.NullableAttribute` (メンバー単位、
  `byte` または `byte[]` フラグ) と `NullableContextAttribute`
  (型/モジュール単位のデフォルト文脈) という、どちらも**標準の .NET カスタム属性**
  としてIL メタデータに埋め込む。値は `0=Unknown, 1=NotNullable, 2=Nullable`
  ([出典: Roslyn nullable-metadata docs, Rico Suter氏のブログ等])。
- これは **C#コンパイラ (Roslyn) 固有の出力規約** であり、CLR/BCL 標準の
  一部ではない。つまり「読む側」は `System.Reflection` の標準APIだけでなく、
  この特定のカスタム属性を認識してデコードするロジックを自前で書く必要がある
  (Roslynの `NullableAnnotation` 相当の情報は `System.Reflection` の
  標準プロパティとしては公開されていない)。
- Oxygene (Elements) は `.NET` ターゲットに **Echoes** という専用バックエンドを
  使用し、C#/VBコンパイラと同様に標準IL/メタデータを出力する
  (RemObjects公式: 「Microsoft の Visual C#/VB コンパイラと同様にIL codeへ
  コンパイルされ、CLRが動く場所ならどこでも動く」との説明あり)。
  標準IL出力である以上、`CustomAttributeData` としてのカスタム属性一般は
  `System.Reflection` 互換APIから読めるはずである。
- Oxygene 言語自体は `nullable T` / `not nullable T` という明示的なキーワードで
  nullability を表現する (C#の `T?`/`T!` に相当する Elements 統一構文の一種、
  RemObjects公式ドキュメント「Nullability」「Oxygene/Types/Nullability」による)。
  デフォルトは「参照型は nullable、値型は non-nullable」で C# と同じ考え方。

**確認できなかったこと (要実機検証、リスクとして明記):**

- Oxygene (Echoes バックエンド) が `nullable`/`not nullable` 修飾を実際に
  **`NullableAttribute`/`NullableContextAttribute` としてIL出力するかどうか**は、
  公式ドキュメント (docs.elementscompiler.com の Nullability 関連ページ) を
  調査した範囲では明記されていなかった。これは「Oxygeneで書かれたアセンブリを
  C#の慣習でNRT情報を読もうとしたときに実際に読めるか」を左右する最重要な
  未確認事項である。
- 仮に Oxygene が独自の属性 (例: `RemObjects.Elements.*Nullable*`) を使っている
  場合、本ツールはそちらも解釈できるようにする必要があるが、現時点でその属性の
  有無・名前は不明。

### 4.2 設計方針 (上記の不確実性を前提にした設計)

不確実性がある以上、**「NRT情報ソースを差し替え可能なプラガブルな抽象」**として
設計し、Phase 2 の最初期タスクとして実機検証 (§9, HANDOFF.md) を行い、
検証結果に応じて実装を確定する。

```oxygene
type
  // NRT解析結果。Emitter/型マッピング層はこれだけを見る。
  NullabilityInfo = public class
  public
    State: NullabilityState; // Unknown, NotNullable, Nullable
    Source: NullabilitySource; // どの情報源から判定したか (診断・デバッグ用)
  end;

  NullabilitySource = public enum (
    ExplicitAttribute,      // NullableAttribute等を直接発見
    ContextAttribute,       // NullableContextAttributeからの継承
    ValueTypeDefault,       // 値型のデフォルト規則から推定
    NoInformation           // 何も情報がなく Unknown 扱い
  );

  // 差し替え可能なNRT情報プロバイダ。複数登録可能で、優先順に最初に
  // Unknown以外を返したものを採用する (型マッピングのCanHandleチェーンと同じ思想)。
  INullabilityProvider = public interface
    method TryGetNullability(aMember: IrMemberRef; aContext: AnalysisContext): NullabilityInfo;
  end;
```

- **組み込みプロバイダ1: `RoslynStyleAttributeProvider`**: 標準の
  `NullableAttribute`/`NullableContextAttribute` を解釈する (C#/VBが生成する
  アセンブリ、および Echoes が同じ規約に従っている場合の Oxygene アセンブリの
  両方をカバーできる想定)。
- **組み込みプロバイダ2: `ValueTypeDefaultProvider`**: 属性が全く無い場合の
  フォールバックとして、値型は non-nullable、参照型は「情報無し=Unknown」とする
  保守的な規則 (Unknown は `.d.ts` では `T | null | undefined` 的に安全側へ倒すか、
  設定で「Unknown時は non-null 扱い」にするかを選べるようにする)。
- **拡張ポイント**: Phase 2 の実機検証で Oxygene 独自の属性が見つかった場合、
  `OxygeneNativeNullabilityProvider` を追加するだけで済むように、
  この抽象を最初から用意しておく。

### 4.3 なぜこの設計か

- 「不確実な外部要因 (コンパイラのメタデータ出力仕様) に依存する解析ロジックは、
  差し替え可能なプロバイダとして切り出す」という原則に基づく。もし
  `RoslynStyleAttributeProvider` だけをハードコードして実装し、後から
  Oxygene が別の属性を使っていると判明した場合、解析ロジック全体を書き直す
  リスクがある。プロバイダチェーンにしておけば追加のみで対応できる。
- Unknown 状態を明示的に第一級で扱う理由: 「わからない」を握りつぶして
  勝手に non-null と判定すると、実行時に null が来てランタイムエラーになる
  TypeScript コードを生成してしまう (安全性の欠如)。逆に全部 nullable
  扱いにすると型の有用性が下がる。ユーザーが `--nrt-unknown-policy`
  (仮称: `assume-nullable` | `assume-non-nullable` | `mark-unknown`) を選べる
  ようにし、暗黙の安全性判断をツールが勝手に行わないようにする。

---

## 5. メタデータ・属性反映

### 5.1 対応する属性・情報源

| 情報源 | 反映先 | 備考 |
|---|---|---|
| `System.Text.Json.Serialization.JsonPropertyName` | プロパティ名変換 | 最優先。無ければ `JsonNamingPolicy` 設定 (camelCase等) をシミュレートして命名規則変換 |
| `System.Text.Json.Serialization.JsonIgnore` | プロパティ除外 | `Condition` (WhenWritingNull等) は簡易対応、詳細はPhase 2で仕様確定 |
| XML Doc コメント (`///`, Oxygene側は `///` または `{{ }}` 相当の構文を要調査) | JSDoc (`/** ... */`) | アセンブリ横に生成される `.xml` ドキュメントファイルをMSBuild同様の慣習で探索して読み込む |
| `System.ObsoleteAttribute` | `@deprecated` JSDocタグ | `Message`/`IsError` も反映 |
| `System.ComponentModel.DataAnnotations.*` (`Required`, `StringLength`, `Range`, `RegularExpression`等) | zod/io-tsスキーマの制約 | §5.3 |
| `[EnumMember]` / `[JsonStringEnumConverter]` | enum文字列リテラル値 | §2.5 |

### 5.2 XML ドキュメントコメント統合の設計

- .NET の標準的な `AssemblyName.xml` (MSBuildが `<GenerateDocumentationFile>` で
  生成するもの) を、アセンブリ本体と同じディレクトリから探索して読み込む
  (見つからない場合は警告のみでスキップ、必須にはしない)。
- XMLの `<member name="...">` の `name` 属性 (例: `M:Namespace.Type.Method(System.String)`)
  から IR 内の該当メンバーへの解決テーブルを Stage 2 で構築する。
  **理由**: リフレクションメタデータには無いドキュメント文字列を紐付ける唯一の
  標準的な方法であり、C#/Oxygene問わず共通のXML形式であるため言語非依存に扱える。
- `<summary>` → JSDoc本文、`<param>` → `@param`、`<returns>` → `@returns`、
  `<exception>` → `@throws` の対応表をテンプレート化する。
- Oxygene側のドキュメントコメント構文がXML docコメントとして同一形式で
  出力されるかは要確認 (Phase 2着手時の確認事項としてHANDOFF.mdに記載)。

### 5.3 バリデーション属性 → zod/io-ts スキーマ

- `SchemaEmitter` は「バックエンド (zod / io-ts / 将来的にvalibot等)」を
  プラグイン的に切り替え可能にする (§6と同じプラグイン機構を再利用)。
- マッピング例:
  - `[Required]` → optional から必須へ (nullable/NRT解析結果と統合して判定)
  - `[StringLength(max, MinimumLength = min)]` → `z.string().min(min).max(max)`
  - `[Range(min, max)]` → `z.number().min(min).max(max)`
  - `[RegularExpression(pattern)]` → `z.string().regex(new RegExp(pattern))`
- **理由 (なぜ型定義と分離した別Emitterか)**: `.d.ts` は型情報のみで実行時コストが
  ゼロだが、zod等のスキーマは実行時に評価される値である。両者は「同じIRから
  生成されるが性質の異なる成果物」であるため、Stage 4 で別Emitterとして
  完全に分離し、`.d.ts` のみが必要なユーザーはSchemaEmitterを無効化して
  ビルドコストを避けられるようにする。

---

## 6. プラグイン機構のインターフェース設計

### 6.1 拡張ポイント一覧

1. `ITypeMappingRule` (§2) — 型変換ルールの追加
2. `INullabilityProvider` (§4) — NRT情報ソースの追加
3. `INamingStrategy` — プロパティ/型名の命名規則変換 (camelCase化等) の差し替え
4. `ISchemaBackend` — zod/io-ts等、スキーマ生成の出力方言の差し替え
5. `IEmitterExtension` — 出力ファイルへの前後処理フック (例: 生成物へのヘッダー
   コメント挿入、Prettier等のフォーマッタ連携)

### 6.2 プラグインパッケージの形

```oxygene
type
  // プラグインのエントリポイント。1プラグイン = 1個以上の拡張ポイント実装を登録する。
  ITsgenPlugin = public interface
    method GetName: String;
    method GetVersion: String;
    method Register(aRegistry: IExtensionRegistry);
  end;

  IExtensionRegistry = public interface
    method AddTypeMappingRule(aRule: ITypeMappingRule; aPriority: Int32 := 0);
    method AddNullabilityProvider(aProvider: INullabilityProvider; aPriority: Int32 := 0);
    method AddNamingStrategy(aName: String; aStrategy: INamingStrategy);
    method AddSchemaBackend(aName: String; aBackend: ISchemaBackend);
    method AddEmitterExtension(aExtension: IEmitterExtension);
  end;
```

### 6.3 プラグインの配布・ロード方式 (候補比較、未確定)

| 方式 | 長所 | 短所 |
|---|---|---|
| A. 同一.NETランタイム上の別アセンブリを動的ロード (Assembly.Load) | ネイティブに近い実行速度、型安全なインターフェース実装 | プラグイン側もOxygene/.NET言語で書く必要があり裾野が狭い。CLIツール自体の配布形態(AOT化するか等)に制約される可能性 |
| B. 設定ファイル (JSON/YAML) 上の宣言的ルール (属性名→TS型のマッピング表など) | 言語非依存、学習コストが低い、大半のカスタマイズ要求はこれで足りる | 「構造的な」複雑なルール (§2.3のような) は表現しにくい |
| C. 外部プロセス (別言語で書かれたプラグイン) とのプロトコル通信 (stdin/stdout JSON等) | 言語非依存で拡張性最大 | 実装コストが高く、パフォーマンスオーバーヘッドがある |

**方針**: B (宣言的ルール) をまず用意し、大半のユースケース (型オーバーライド、
命名規則、除外設定) をカバーする。A (アセンブリ動的ロード) はより高度な
拡張が必要になった場合の上位互換として `ITsgenPlugin` インターフェースを
用意しておくが、実装優先度はMVP後 (§8 Phase 2後半) とする。C は現時点では
スコープ外 (需要が明確になってから検討)。

- **理由**: プラグイン機構は「使われて初めて価値が出る」ものであり、複雑な
  動的ロード機構を先に作り込んでも、実際のカスタマイズ要求の8割は
  「この型はこう変換してほしい」「この命名規則を使いたい」という宣言的な
  ものである可能性が高い (一般的なコード生成ツール, 例: TypeGen, NSwag,
  OpenAPI Generator 等の実運用パターンからの類推)。まず設定ファイルベースで
  ニーズを満たし、本当に構造的な拡張が要る利用者向けにインターフェース
  (A方式) を後から生やす、という段階的releaseにする。

---

## 7. 出力生成パイプラインのデータ構造案

### 7.1 IR (中間表現) の主要構造

```oxygene
type
  IrAssembly = public class
  public
    Name: String;
    Modules: List<IrNamespaceModule>; // 名前空間ごとにグルーピング済み
    AllTypes: List<IrType>;           // フラットなリスト (SCC解析等で使用)
  end;

  IrNamespaceModule = public class
  public
    NamespaceName: String;   // 例: "MyCompany.Models"
    Types: List<IrType>;
    // 出力構成(§7.3)決定後にここに OutputFilePath が確定する (Stage 4で設定)
  end;

  IrType = public class
  public
    FullName: String;
    Kind: IrTypeKind; // Class, Interface, Struct, Enum, Record, DelegateAsFunction, Tuple
    BaseType: IrTypeRef;
    Interfaces: List<IrTypeRef>;
    GenericParameters: List<IrGenericParam>;
    Members: List<IrMember>;
    Attributes: List<IrAttribute>;   // 反映対象属性のみ保持 (§5.1)
    XmlDoc: XmlDocInfo;
    SccId: Int32;                    // §3
    IsCyclic: Boolean;               // §3
  end;

  IrMember = public class
  public
    Kind: IrMemberKind; // Property, Field, Method, EnumValue
    Name: String;
    JsonName: String;                // §5.1 適用後の最終プロパティ名
    ValueType: IrTypeRef;
    Nullability: NullabilityInfo;    // §4
    Attributes: List<IrAttribute>;
    XmlDoc: XmlDocInfo;
    IsIgnored: Boolean;              // [JsonIgnore]等
  end;

  IrTypeRef = public class
  public
    // 未解決の型参照 (ジェネリクス引数を含む可能性がある)。
    // MappingContext.ResolveType() を通して TsTypeExpression に変換される。
    ResolvedType: IrType;            // BCL外のユーザー定義型ならここに解決結果
    WellKnownKind: WellKnownTypeKind; // string/int/List<T>等、BCLの既知型ならこちら
    TypeArguments: List<IrTypeRef>;
  end;
```

### 7.2 各ステージのデータフロー

```mermaid
flowchart LR
    Raw["RawAssemblyModel<br/>(Stage1, ほぼ生の反射情報)"]
    Ir["IrAssembly<br/>(Stage2, 安定モデル。以降は<br/>これ以外を参照しない)"]
    Resolve["TypeMappingResolverで<br/>IrTypeRefをキャッシュ付きで解決<br/>(Stage3)"]
    Ast["軽量AST: TsSourceFile<br/>{ Path, Imports, Declarations }<br/>(Stage4, 各Emitterが構築)"]
    Write["ファイル書き込み<br/>または既存ファイルとのdiff計算<br/>(Stage5, --checkモード)"]

    Raw --> Ir --> Resolve --> Ast --> Write
```

**設計判断: Stage1のRawAssemblyModelとStage2のIrAssemblyをなぜ分けるか**
Oxygeneの `System.Reflection` 互換層の挙動 (§4.1で判明した通り、一部の
挙動が未検証) に将来変更が入っても、Stage2以降 (パイプラインの大部分) を
書き直さずに済むようにするため。Stage1は「.NETメタデータの生の姿を
IrAssemblyが要求する形に整形するだけ」の薄い層に留める。

### 7.3 出力構成の設計

- **名前空間 → ESモジュール階層**: デフォルトでは `MyCompany.Models.User`
  → `mycompany/models/user.d.ts` のようにディレクトリ階層へ1:1マッピングする
  設定 (`namespaceStrategy: "directory"`) と、名前空間ごとに1ファイル
  (`namespaceStrategy: "flat-per-namespace"`)、全体を1ファイルにまとめる
  (`namespaceStrategy: "single-file"`) の3種を切り替え可能にする。
  - **理由**: 小規模プロジェクトは単一ファイルの方が扱いやすく、大規模プロジェクト
    (数百型規模) はディレクトリ階層の方がIDEでの探索性・差分レビュー性が良い。
    どちらが正解ということはないため設定で選ばせる。
- **カスタム型オーバーライド設定**: `tsgen.config` に
  `typeOverrides: { "System.Guid": "string", "MyCompany.Money": { module: "./custom-types", name: "Money" } }`
  のような宣言的マッピングを許可し、これは §2.2 の優先順位チェーンの
  最上位 (ユーザー定義オーバーライド) として解決される。

---

## 8. API連携設計

### 8.1 OpenAPI仕様生成との統合

- 本ツールはOpenAPI仕様そのものは生成しない (ASP.NET Core側の
  `Microsoft.AspNetCore.OpenApi` / Swashbuckle 等、既存エコシステムに委ねる)。
  代わりに **「既存のOpenAPI JSON/YAMLを読み込み、型はそちらではなく
  本ツールが .NET アセンブリから生成した高精度な型に差し替える」**
  統合モードを用意する。
  - **理由**: OpenAPI (特にSwashbuckleの既定出力) はnullableやジェネリクスの
    表現力がTypeScriptほど高くなく、enumも文字列止まりになりがちなため、
    アセンブリから直接読む方が正確な型が得られる。一方でOpenAPIにはHTTPメソッド・
    パス・パラメータ位置(query/path/body)という、リフレクションだけでは
    (素朴には) 得られない情報がある。両者を組み合わせるのが最も実用的。
- 統合手順 (案): OpenAPI の `operationId` や `x-*` 拡張フィールドに .NET側の
  コントローラ/アクションのFQNを埋め込む慣習を前提とし (ASP.NET Core既定では
  `operationId` は自動生成されるため、埋め込みには
  `[EndpointName]`/カスタム属性、またはSwashbuckle設定側での工夫が必要になる
  可能性がある。要Phase 2調査)、その紐付けを使って型を差し替える。

### 8.2 エンドポイント単位のTypeScript関数 (fetchラッパー) 生成

```typescript
// 生成イメージ (ApiClientEmitter出力例)
export async function getUserById(
  id: string,
  options?: { signal?: AbortSignal; baseUrl?: string },
): Promise<User> {
  const res = await fetch(`${options?.baseUrl ?? ""}/api/users/${id}`, {
    signal: options?.signal,
  });
  if (!res.ok) throw new ApiError(res.status, await res.text());
  return (await res.json()) as User;
}
```

- HTTPクライアント実装は `fetch` 標準APIを既定とし、Axios等への差し替えは
  §6のプラグイン機構 (`IEmitterExtension` またはテンプレート差し替え) で
  対応する方針とする (fetchはNode.js 18+/ブラウザ双方で標準なので依存ゼロで
  動くことを優先)。
- レスポンスの実行時検証 (zod等) をここに挟むかはオプション化する
  (`apiClient.validateResponse: boolean`)。検証を有効にする場合は
  §5.3のSchemaEmitterの出力を利用する。

---

## 9. 開発体験 / CI 設計

### 9.1 インクリメンタル生成

- 入力ハッシュ (対象アセンブリのファイルハッシュ + 設定ファイルのハッシュ +
  ツール自体のバージョン) をキーに、Stage 1-4 の結果をキャッシュする。
  キャッシュヒット時はStage 5 (書き込み) のみ実行、もしくは書き込みすら
  スキップ (出力先の内容と一致していれば)。
- **理由**: watch モードでの再生成速度、および大規模アセンブリでのCLI体験
  向上のため。キャッシュは `.tsgen-cache/` 的なディレクトリに置き、
  `.gitignore` 対象とする想定。

### 9.2 Watch モード

- 対象アセンブリファイルのファイルシステム監視 (mtime/ハッシュベースの
  ポーリング、またはOS通知APIが使えるならそちらを優先)。
- .NET側のビルド (`dotnet build`) の完了を検知して再生成する運用を想定するため、
  「ファイル変更検知後、一定時間 (デバウンス、既定500ms程度) 待ってから
  再読み込みする」設計とする (ビルド中の中間状態のdllを読みに行って失敗する
  ことを避けるため)。

### 9.3 CI差分チェック (`--check` モード)

- 生成物をリポジトリにコミットする運用のプロジェクト向けに、
  「実際に生成し、既存のコミット済みファイルと完全一致するか」を検証し、
  不一致ならnon-zero終了 + diff表示するモードを用意する。
- **設計判断: なぜ生成→比較方式で、ハッシュだけの比較にしないか**:
  ハッシュ不一致だけだと「なぜ不一致か」がCIログから分からず開発者体験が悪い。
  実際にdiffを出すことで、CI上でも「どのプロパティ/型が変わったか」が
  一目でわかるようにする (Stage5のDiff Engineをこのモードでも再利用、§1.1)。

### 9.4 GitHub Actions組み込み設計 (方針のみ、YAML実装は優先度低)

```yaml
# .github/workflows/generate-check.yml (設計イメージ、Phase 2で実装)
# トリガ: pull_request (対象アセンブリ or 設定ファイルに変更があった場合)
# ジョブ:
#   1. .NET側をビルドしてアセンブリを生成 (対象リポジトリの構成に依存するため
#      ユーザー側のワークフローとの合成が前提。本リポジトリが提供するのは
#      「tsgen generate --check」を実行する再利用可能ワークフロー
#      (workflow_call) の形を基本とする)
#   2. oxygene-tsgen CLI (リリース済みバイナリ or コンテナイメージ) を実行
#   3. --check モードで差分があれば fail、コメントでdiffをPRに投稿 (任意)
```

- **理由 (再利用可能ワークフローを基本形にする理由)**: 本ツールはあくまで
  CLIであり、.NET側のビルド方法はユーザーのプロジェクト構成に強く依存する
  (対象フレームワーク、マルチプロジェクト構成等)。汎用性を持たせるには
  「ビルド後のアセンブリパスを受け取って `--check` を実行するだけ」の
  最小限の再利用可能ワークフローを提供し、ビルドステップ自体はユーザーの
  既存ワークフローに任せるのが最も柔軟。

---

## 10. MVPスコープと将来拡張の境界線

### 10.1 MVP (Phase 2 初期実装対象)

要件定義時点で合意済みの通り、以下を最小到達点とする:

- 基本型マッピング (プリミティブ、`string`/`number`/`boolean`/`Date`等の既知BCL型)
- enum (数値 or 文字列リテラルUnion、設定で選択可能。§2.5の簡易版)
- nullable参照型の反映 (§4のプロバイダ抽象は用意するが、実装は
  `RoslynStyleAttributeProvider` 相当の1系統のみで開始し、実機検証結果を
  見てから広げる)
- 名前空間 → ESモジュール階層での `.d.ts` 出力 (単一/分割ファイルの基本切替)
- CLIとしての最小構成 (`tsgen generate --assembly X.dll --out ./dist`)

### 10.2 MVP後・段階的に追加する機能 (優先度順の目安)

1. ジェネリクス (`List<T>`, `Dictionary<K,V>`) の一般化、継承/インターフェース
2. 循環参照検出 (§3) — 型が増えてくると必要性が高まるため、MVP直後に着手
3. XML Doc → JSDoc、`[Obsolete]` → `@deprecated` (メタデータ層の中でも
   実装コストが低く効果が高いため優先)
4. `System.Text.Json` 属性による命名変換
5. カスタム型オーバーライド設定 (§7.3)
6. record/タプル対応
7. バリデーション属性 → zod/io-tsスキーマ生成 (§5.3)
8. プラグイン機構 (§6) — 宣言的ルール (方式B) から
9. OpenAPI統合・APIクライアント生成 (§8) — 依存範囲が広いため後半
10. インクリメンタル生成・Watchモード・CI差分チェック (§9) — CLIの基本機能が
    安定してから開発体験向上として着手

### 10.3 境界線の考え方

- **理由**: MVPは「動くものを最速で手元のプロジェクトに試せる」ことを優先し、
  型の正確性 (nullable, enum) と出力の使いやすさ (名前空間構造) を最優先項目とした。
  メタデータ層 (XMLdoc, 属性) やAPI連携は「型が正しく生成できる」という
  土台が無いと価値が発揮できないため、後回しにする。プラグイン機構は
  「何を拡張したいか」の実例がある程度溜まってから設計を固める方が
  無駄がないため、意図的に後半に配置している。

---

## 11. 未解決事項 (Open Questions)

Phase 2着手前、または着手直後に解決すべき事項。詳細は `HANDOFF.md` にも記載。

1. **Oxygeneコンパイラ(Echoes)がNRT情報を`NullableAttribute`/
   `NullableContextAttribute`として出力するか** — 実機検証が必要 (§4.1)。
2. **Oxygene製アセンブリに対する`System.Reflection`相当APIの具体的な実行環境**
   — 本ツール自体をOxygeneで書く場合、対象アセンブリの読み込みに
   `System.Reflection.MetadataLoadContext` (実行せずメタデータのみ読む標準機構)
   がOxygene/Echoesから素直に使えるか、あるいは自前でECMA-335メタデータ
   パーサを書く必要があるか、の技術検証。
3. **Oxygeneのドキュメントコメント構文とXML doc出力の互換性** (§5.2)。
4. **配布・パッケージング方式** — npm経由 (Node.jsバイナリ同梱 or npmラッパー)、
   単体バイナリ配布 (Elements/Islandでネイティブビルドする案も含む)、
   dotnet toolとしての配布、の比較検討が未着手。
5. **プラグインのアセンブリ動的ロード方式 (§6.3 方式A)** の技術的実現性
   (Echoes上での動的ロードAPIの有無)。

---

## 12. 参考にした調査ソース

- RemObjects Elements公式ドキュメント: Nullability関連
  (`docs.elementscompiler.com/Oxygene/Types/Nullability/`,
  `docs.elementscompiler.com/Concepts/Nullability/`)
- RemObjects公式サイト: Elements/Echoesバックエンドの説明
  (`remobjects.com/elements/technologies.aspx`)
- .NET NRTメタデータ規約: Roslyn `nullable-metadata.md`
  (github.com/dotnet/roslyn)、Rico Suter氏・Maarten Balliauw氏の解説記事
- 上記はいずれも2026年7月時点のWeb検索結果に基づく。RemObjects Elementsは
  週次リリースサイクルのプロダクトであるため、Phase 2着手時に最新ドキュメント
  との差分がないか再確認することを推奨する。
