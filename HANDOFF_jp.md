# HANDOFF: oxygene-tsgen

> 🇬🇧 [English version](./HANDOFF.md)

このファイルはセッション間 (Fable5による設計フェーズ → Sonnetによる実装フェーズ、
以降も) の申し送り用です。Phase 2 着手セッションは、まずこのファイルと
`docs/DESIGN.md` を読んでから作業を開始してください。

---

## 1. このセッション (Phase 1 / Fable5) で行ったこと

- `docs/DESIGN.md`: 最大構成の設計書を作成 (アーキテクチャ、型マッピング層、
  循環参照検出、NRT解析方針、メタデータ反映、出力構成、プラグイン機構、
  IRデータ構造、API連携、CI設計、MVPスコープと実装順序)。
- `README.md`: プロジェクト概要とステータスを記載。
- `src/`, `tests/`, `.github/workflows/` をディレクトリのみ作成 (実装コードなし)。
- 実装コードは一切書いていません。パッケージのインストールも実行していません。
- `git push` は実行していません (ローカルコミットのみ、`origin` には触れていません)。

## 2. DESIGN.md 作成時に判断に迷った点・複数案の選定理由

### 2.1 パイプライン段数: 5段階 + IR を挟むか、2段階の簡略構成か

- 検討した代替案: 「Loader が直接 TS AST を組み立てる」簡略パイプライン。
- 採用: IR (`IrAssembly`) を挟む5段階パイプライン (`docs/DESIGN.md` §1)。
- 理由: `.d.ts` / zod スキーマ / API クライアントという複数の出力形式が
  同じ解析結果 (NRT解析、循環参照検出等) を共有する必要があるため、
  IRを共通基盤にする方が重複実装を避けられると判断した。
- 迷った点: MVP規模のツールとしてはオーバーエンジニアリングという見方もできる。
  MVPでは Stage 2 (NRT解析等) を簡略化した「軽量IR」から始める方針にしたが、
  「軽量IR」の具体的な省略範囲はPhase 2で最初に決める必要がある
  (§3 タスクリスト参照)。

### 2.2 型マッピングルールの優先順位方式: スコアリング方式 vs チェーン方式

- 検討した代替案: 複数ルールが `CanHandle` した場合に「最も詳細にマッチした
  ルール」を自動選択するスコアリング方式。
- 採用: 明示的な優先順位チェーンで「最初にCanHandleしたもの勝ち」
  (`docs/DESIGN.md` §2.2, §2.3)。
- 理由: スコアリング方式は暗黙的で、プラグイン作者から見て「なぜ自分のルールが
  呼ばれないか」が分かりにくくなる懸念があった。デバッグのしやすさを優先。

### 2.3 プラグインの配布方式: 動的アセンブリロード vs 宣言的設定ファイル

- 検討した3案 (`docs/DESIGN.md` §6.3の比較表): (A) .NETアセンブリの動的ロード、
  (B) JSON/YAML等の宣言的ルール、(C) 外部プロセスとのプロトコル通信。
- 採用: Bをまず実装し、Aは将来の拡張インターフェースとして用意するに留める。
  Cは現時点でスコープ外。
- 理由: 一般的なコード生成ツール (TypeGen, NSwag, OpenAPI Generator等) の
  実運用パターンからの類推で、カスタマイズ要求の大半は宣言的ルールで
  足りると判断した。ただし実際の需要は未検証であり、Phase 2以降で
  ユーザーフィードバックがあれば優先度を見直すべき。

### 2.4 NRT情報が不明な場合の既定動作: 安全側(nullable扱い) vs 型の有用性側(non-null扱い)

- 採用: どちらかに決め打ちせず、`INullabilityProvider` チェーンで
  `Unknown` 状態を第一級で扱い、ユーザーが `--nrt-unknown-policy` で
  ポリシーを選択できるようにする設計とした (`docs/DESIGN.md` §4.2, §4.3)。
- 理由: ツールが暗黙に安全性判断を行うと、ランタイムエラー (安全側に倒しすぎて
  誤ってnullを許容しない設計を書かせる、または逆に過剰にnullableにして
  型の有用性を下げる) のどちらのリスクも生む。明示的にユーザーに選ばせる方が
  誠実だと判断した。

### 2.5 循環参照検出アルゴリズム: 単純DFS vs Tarjan SCC

- 採用: Tarjan の強連結成分分解 (`docs/DESIGN.md` §3.2)。
- 理由: 循環の「有無」だけでなく「循環に含まれる型のグループ」が
  zodスキーマの`lazy化`や出力順序決定 (トポロジカルソート) に必要になるため、
  最初からSCCベースで設計する方が後工程との整合性が良いと判断した。
  単純DFSでの検出は実装は簡単だが、グルーピング情報を別途求め直す二度手間になる。

### 2.6 API連携: OpenAPI仕様自体を生成するか、既存OpenAPIと統合するだけに留めるか

- 検討: 本ツール自体でOpenAPI仕様 (JSON/YAML) を一から生成する案もあり得たが、
  ASP.NET Core向けのOpenAPI生成エコシステム (Swashbuckle等) が既に成熟している
  ため、車輪の再発明を避け「既存OpenAPI + アセンブリからの高精度型」を
  組み合わせる統合モードのみを設計した (`docs/DESIGN.md` §8.1)。
- 未解決: `operationId` とコントローラ/アクションのFQNを紐付ける具体的な
  慣習・実装方法は要調査 (§3 タスクリストに反映)。

### 2.7 README/DESIGN/HANDOFFの言語

- 日本語主体で記述した (ユーザーとのやりとりが日本語であるため)。
  ただしREADMEの冒頭のみ英語の1行サマリを添えた (GitHub上での一般的な
  発見性を考慮)。将来的にOSS公開を強く意識するなら英語版READMEの追加も
  検討の余地あり (Phase 2以降の判断事項として残す)。

### 2.8 DESIGN.mdの英訳 (追記: 別セッションでの作業)

- `docs/DESIGN.md` (旧: 日本語版) は `docs/DESIGN_jp.md` にリネームした上で、
  新規に英語版 `docs/DESIGN.md` を全文翻訳で作成した。両ファイルは相互に
  冒頭リンクを持つ (🇯🇵/🇬🇧)。今後 `docs/DESIGN.md` が「主」、
  `docs/DESIGN_jp.md` が日本語訳という位置づけになる。
- `README.md` 内の `docs/DESIGN.md#10-mvpスコープと将来拡張の境界線`
  (日本語見出しのMarkdownアンカー) は英訳により見出しが変わるため壊れる問題が
  あった。**案B (英語版DESIGN.mdの英語見出しアンカーに向け直す)** を採用し、
  `docs/DESIGN.md#10-mvp-scope-and-the-boundary-for-future-extensions` に修正した。
  - 理由: README冒頭は既に英語サマリを含んでおり、`docs/DESIGN.md` という
    ファイル名で参照されるデフォルトの設計書は英語版とする方針に合わせた。
    日本語で読みたい読者は各ファイル冒頭の言語切り替えリンクから
    `DESIGN_jp.md` に遷移できるため、README側のリンクを日本語版に
    向け直す (案A) 必要性は薄いと判断した。
- 本セクション以外の `docs/DESIGN.md §X` という記述 (URLアンカーを伴わない
  セクション番号参照) は、英語版・日本語版で見出し番号の構成が完全に
  一致しているため修正不要 (指示通り)。

### 2.9 入力方式の再検討: Oxygeneソース解析 vs コンパイル済みアセンブリのreflection
(§6のInertia.js方針転換後、2026-08-01時点での検討)

- 検討: §6でInertia.js対象バックエンドがOxygene専用と判明したことを受け、DLLの
  reflectionではなく、Oxygeneソースコード (プロジェクトファイル含む) を直接解析する
  方式への転換を検討した。ソース解析であれば、NRT (`nullable`/`not nullable`) を
  IL属性 (`NullableAttribute`等) の有無に頼らず構文から直接読めるほか、
  `Inertia.Render` 呼び出し検出 (`docs/DESIGN.md` §3.5参照) も構文木を辿るだけで
  済み、既存の二大技術的不確実性 (本ファイル §3の4番、および `docs/DESIGN.md` §3.5)
  を同時に解消できる可能性があった。
- 却下 (フルパーサー案のみ): RemObjects Elements/Oxygeneには、外部ツールが
  利用できる独立のパーサー/AST (抽象構文木) 専用のパブリックAPIが存在しないことを
  ユーザーが確認した (公開されているのは構文・名前空間のリファレンス
  https://www.remobjects.com/elements/oxygene/language のみで、
  Roslynの `Microsoft.CodeAnalysis` に相当するコンパイラAPIはない)。
  自前でOxygene文法の**完全な**パーサー/ASTを一から書く案は、既存の
  reflectionベース設計よりも遥かに大きな実装コスト・言語仕様変更への
  継続的な追従コストを伴うため、却下する。
- 判断を保留した別案 (フルパーサーとは別物、まだ却下していない): 「完全な文法解析」
  ではなく、`nullable`/`not nullable` トークンの検出や `Inertia.Render(...)`
  呼び出し箇所のテキストパターン検出のみを狙った、**軽量・部分的なソーステキスト
  スキャン** (正規表現 or 簡易tokenizer程度で、完全な構文木構築はしない) は
  上記のフルパーサー却下の理由 (実装コスト・言語仕様追従コスト) がそのまま
  当てはまるとは限らず、別途評価すべきものとして未検討のまま残っている。
  ただしこちらは複数行にまたがる呼び出し、ジェネリクス、エイリアス、
  ヘルパーメソッド経由の間接呼び出し等に弱いという固有のリスクがあるため、
  「安価だから採用」と即断せず、Phase 2で具体的に評価すること
  (下記§4のタスクリストにSDK同梱物の確認を追加した後、このスキャン方式の
  費用対効果も改めて検討する)。
- 結論: 上記の判断保留を踏まえた上で、当面は引き続きコンパイル済みアセンブリの
  reflection方式を主軸に維持する。ただしこれは `docs/DESIGN.md` §3.5
  (エントリポイント駆動の型発見) を解決するものではない点に注意: 同セクションが
  指摘する通り、匿名型はILレベルでは名前情報が失われるため、IL/式木解析は
  ソースアクセスよりもむしろ難しくなり得る。したがって reflection方式の維持は
  §3.5の問題を「解決した」のではなく「未解決のまま持ち越した」に過ぎず、
  むしろ最も簡単だったかもしれない解決経路 (ソースアクセス) を自ら手放している
  可能性がある。§4 (NRT解析) の技術的不確実性についても同様に未解決のまま残る
  (Phase 2冒頭の検証タスクの優先順位は変わらず最優先のまま)。
- 再検討の余地: 将来 RemObjects社が公開パーサー/AST APIを提供した場合、
  または Fire/Water IDE の補完機能が Language Server Protocol (LSP) 相当の
  手段で構文情報を外部公開している場合は、ハイブリッド方式 (自プロジェクトの
  ソースは解析、BCL/NuGet等の外部依存はreflection) を再検討する価値がある。
  この確認は本格的なLSPプロトコル調査より先に、安価な手段 (下記§4参照) で
  着手できる。

---

## 3. Oxygeneの `System.Reflection` 互換性について調査中に見つかった制約・注意点

Web検索ツールを用いて調査した内容です (2026年7月時点)。RemObjects Elementsは
週次リリースのプロダクトのため、Phase 2着手時に一次情報の再確認を推奨します。

1. **.NETターゲットのバックエンド名は "Echoes"**。Oxygene/C#/Swift等の複数
   フロントエンド言語が共通のバックエンドでIL生成する構成であり、
   RemObjects公式説明では「Microsoftの Visual C#/VB コンパイラと同様に
   IL codeへコンパイルされ、CLRが動く場所ならどこでも動く」とされている。
   → 標準的なメタデータ (型、メンバー、カスタム属性一般) は
   `System.Reflection` 互換APIから問題なく読めると考えてよさそうだが、
   これはあくまで一般論であり、個別の挙動 (下記2, 3) は別途要検証。

2. **【最重要・未検証】NRT (`nullable`/`not nullable`) がIL上で
   `System.Runtime.CompilerServices.NullableAttribute` /
   `NullableContextAttribute` として出力されるかどうかは、公式ドキュメントの
   調査範囲では確認できなかった。** これらの属性はC#コンパイラ(Roslyn)固有の
   出力規約であり、CLR標準機能ではない。Oxygeneが同じ規約に従っているとは
   限らない。
   - Phase 2の最初期に、実際にOxygeneで `nullable`/`not nullable` を使った
     小さなテストアセンブリをビルドし、`ildasm`/`monodis`/`dotnet-ildasm`等で
     IL を逆アセンブルして `NullableAttribute`/`NullableContextAttribute`
     の有無を確認することを強く推奨する (具体タスクは §4 参照)。
   - もし別属性が使われている場合は、`docs/DESIGN.md` §4.2で設計した
     `INullabilityProvider` チェーンに `OxygeneNativeNullabilityProvider`
     を追加する形で対応可能 (設計上は吸収できるはずだが未検証)。

3. **Oxygeneのドキュメントコメント構文がC#と同じXML doc形式 (`AssemblyName.xml`)
   で出力されるかは未確認。** Oxygeneは `///` コメント記法をサポートしている
   と思われるが (要再確認)、MSBuildの `<GenerateDocumentationFile>` 相当の
   出力がElements側のビルド設定でどう有効化されるか、ファイル形式がC#の
   ものと完全互換かは公式ドキュメントで明示的に確認できなかった。

4. **アセンブリのメタデータのみ読み込む機構 (`MetadataLoadContext` 相当) が
   Oxygene/Echoesから利用できるかは未検証。** 本ツール自体を「対象アセンブリを
   実行せずメタデータだけ読む」設計にする場合 (§設計書全体の前提)、
   .NET標準の `System.Reflection.MetadataLoadContext` がOxygeneから
   問題なく呼び出せるか、あるいはECMA-335メタデータを自前でパースする
   必要があるかは技術検証が必要。

5. **プラグインの動的アセンブリロード (`docs/DESIGN.md` §6.3 方式A) の
   実現性は未検証。** ElementsのIslandバックエンド (AOTネイティブ) でCLIを
   ビルドする場合、動的ロードAPI自体が制約される可能性がある
   (AOT環境全般に言えることで、Elements固有の問題とは限らないが要確認)。

---

## 4. Phase 2 (実装フェーズ) が最初に着手すべきタスクの優先順位

**実機検証タスク (1, 2, 2.5) の実施環境について (2026-08-01時点でのメモ):**
これらはOxygeneのビルド・IL逆アセンブル・ローカルSDK同梱物の確認など、実際の
開発環境 (RemObjects Elements/Water) が必要なため、この設計フェーズのセッション
(Web/CLI環境) では実施できない。次回セッションは、Elements/Waterがインストール
済みのWindows機でClaudeデスクトップアプリ (Codeタブ) を使って行う想定。
Codeタブのローカルセッションはサンドボックス化されておらず、CLI版のClaude Codeと
同等にローカルのシェルコマンド・ファイルシステムにアクセスできることを確認済み。
ただしWindowsでBashを使うには事前に [Git for Windows](https://git-scm.com/downloads/win)
のインストールが必要 (未インストール時はPowerShellにフォールバックする)。

1. **【最優先・ブロッカー解消】Oxygene(Echoes)のNRT出力を実機検証する。**
   小さなOxygeneプロジェクトを作成し、`nullable`/`not nullable` を使った
   クラスをビルド、IL逆アセンブルで `NullableAttribute`/
   `NullableContextAttribute` の有無を確認する。この結果次第で
   `INullabilityProvider` の初期実装 (`RoslynStyleAttributeProvider` で
   足りるか、独自プロバイダが要るか) が決まる。
2. **アセンブリのメタデータ読み込み方式の技術検証。**
   `System.Reflection.MetadataLoadContext` 相当がOxygeneから使えるかを確認し、
   使えない場合の代替 (ECMA-335パーサ自作 or 既存ライブラリ調査) を洗い出す。
2.5. **【安価・先出し推奨】ローカルにインストール済みのElements/Water SDK内に、
   Fire/WaterのIDE補完機能が内部で使っている言語サーバーバイナリや
   AST-dump用の隠しコンパイラフラグが同梱されていないか確認する。**
   (§2.9で判断保留にした「軽量ソーステキストスキャン」案、および
   `docs/DESIGN.md` §3.5のエントリポイント駆動型発見の実現可能性に関わる。)
   IDEが補完・リファクタリングを提供している以上、何らかの形で構文情報を
   得ているはずで、それが外部から呼び出せる形で既にSDKに含まれていないかを
   確認するだけの作業のため、本格的なLSPプロトコル調査より先に数分〜数時間で
   着手できる。見つからなければ§2.9の「軽量スキャン vs reflection据え置き」の
   判断はそのまま。
3. **CLIの最小骨格 + Stage1(Loader)/Stage2(軽量IR)/Stage4(DtsEmitter)の
   MVP実装。** `docs/DESIGN.md` §10.1 のMVPスコープ (基本型、enum、nullable、
   名前空間出力) をまず動かす。循環参照検出やプラグイン機構はこの時点では
   実装しない (§10.2の優先順位に従う)。
4. **MVPに対する最小限のテスト基盤整備。** テスト用のOxygene製サンプル
   アセンブリ (プリミティブ型、enum、nullable参照型を含む小さなクラス群) を
   `tests/fixtures/` 相当に用意し、期待する`.d.ts`出力とのスナップショット
   比較を行う仕組みを最初に整える (以降の機能追加のリグレッション防止のため)。
5. **XML Doc → JSDoc、`[Obsolete]` → `@deprecated` の実装。**
   §10.2の3番目だが、実装コストが低く体感効果が高いため、MVP直後の
   早い段階での着手を推奨。
6. 以降は `docs/DESIGN.md` §10.2 の優先順位リストに従う
   (循環参照検出 → メタデータ属性反映 → カスタム型オーバーライド → ... )。

### その他、着手前に確認すべき小さな事項

- パッケージ配布方式 (npm / dotnet tool / 単体バイナリ) は`docs/DESIGN.md`
  §11の未解決事項4。実装のエントリポイント形式に影響するため、CLI骨格を
  書き始める前に方向性だけでも決めておくとよい。
- Elements/Oxygeneのビルド設定 (`.elements`/`.sln`相当のプロジェクトファイル
  構成) をこのリポジトリにどう組み込むか (`src/` 配下の構成) は、
  Phase 2着手時にElementsのCLIツールチェーンのドキュメントを確認しながら
  決定すること (本設計書では言語非依存の設計に留め、Oxygene固有の
  プロジェクト構成までは踏み込んでいない)。

---

## 5. 未整理のまま残した点 (念のため明記)

- `docs/DESIGN.md` はテキストベースの設計書であり、図はASCIIアート程度に
  留めている。より詳細なシーケンス図等が必要になった場合はPhase 2以降で
  別途作成すること。
- 外部ライブラリ (zod/io-ts、テスト用フレームワーク等) の具体的なバージョン
  選定・インストールは未実施 (指示により、候補提示のみに留めている)。
  zodはv3系とv4系でAPIに差異があるため、Phase 2着手時に最新の安定版を
  確認した上で選定すること。
- GitHub Actionsのworkflow YAMLは `.github/workflows/README.md` に方針のみ
  記載し、実装は行っていない (指示により優先度低として許容されている)。

---

## 6. 【重要・設計前提の追加】Inertia.js を主眼としたユースケースへの変更

本セクションは既存の `docs/DESIGN.md` / 本ファイルの §1–5 作成後に追加された前提です。
次にDESIGN.mdへ手を入れるセッション（Fable5再投入 or Phase 2実装セッション）は、
**このセクションを最優先で読んだ上で、既存設計のどこに影響するかを洗い出すこと。**

### 6.1 変更の趣旨

本ツール（oxygene-tsgen）の主要な用途を、汎用的な「.NETアセンブリ→TypeScript型定義
生成」から、**Inertia.js を使ったASP.NET Coreアプリケーションのフロントエンド向け
型生成**に絞り込む。すなわち、Controllerが `Inertia.Render(componentName, data)`
（対象アダプタは **InertiaNetCore** — 2026-08-01決定、§6.4参照。InertiaCoreの
開発が停滞しており、InertiaNetCoreは数少ない開発が活発なフォークの一つ
であるため）で返す `data` オブジェクトの型を、対応するフロントエンド側
ページコンポーネントの Props 型として生成することを主眼に据える。

### 6.2 既存設計への影響（洗い出しが必要な項目）

- **§8 (API連携) の位置づけ低下の可能性。** 既存設計は「OpenAPI仕様との統合」
  「エンドポイント単位のfetchラッパー生成」を志向していたが、Inertia.jsは
  通常のREST APIクライアントパターン（`fetch`でJSONを取りに行く）とは異なり、
  サーバーサイドルーティング + ページ遷移時にpropsが埋め込まれる方式。
  §8の設計をInertia向けに作り直す必要があるか、あるいは別ユースケースとして
  並存させるかを最初に判断すること。
- **新規に必要になりそうな型生成対象:**
  - **ページProps型**: `Inertia.Render("PageName", data)` の `data` の匿名型/
    POCOから、対応するフロントエンド側コンポーネント（`resources/js/Pages/PageName.tsx`
    等）が受け取るProps型を生成する対応表（component名 → props型）
  - **Shared Data型**: Inertiaミドルウェアの `share()` 相当の機構で全ページ共通の
    データ（認証ユーザー情報、フラッシュメッセージ等）が注入される場合、これを
    ページ固有Propsとマージした型にする必要がある（既存設計のマージ機構の有無を
    要確認）
  - **フォーム型（useForm対応）**: Inertiaクライアント側の `useForm()` フックは
    フォームフィールドの初期値・バリデーションエラー型を要求する。C#側のバリデーション
    属性（`[Required]`等、既存 §5 メタデータ反映の対象）から、バリデーションエラーの
    型（フィールド名→エラーメッセージのマッピング）を生成できると実用性が高い
- **循環参照検出（§3）・NRT解析（§4）はそのまま活きる可能性が高い**が、
  「ページ単位でどの型が必要か」を起点にした解析（エントリポイント駆動の型収集）
  という発想が新たに必要になる。既存設計は「アセンブリ全体をスキャンして全型を
  出力する」前提だったため、「Controller の `Inertia.Render` 呼び出し箇所を検出し、
  そこから使われている型だけを辿る」という探索方式への転換が要る可能性がある
  （＝静的解析でC#メソッド本体のIL/式木を追う必要が出てくるかもしれない）。

### 6.3 検討すべき新規調査項目（Phase 2冒頭のタスクリストに追加）

- ~~採用するASP.NET Core向けInertiaアダプタの選定~~ **決定: InertiaNetCore**
  (2026-08-01、§6.4参照)。
- 選定したアダプタが `Inertia.Render(componentName, data)` の `data` を
  どう型付けしているか（`object` 引数なのか、ジェネリクスがあるのか）の実装確認
- Controller メソッド本体から `Inertia.Render` 呼び出しを検出する方式の技術検証
  （Roslyn的な式木解析が必要になるか、IL解析で足りるか）
- ~~フロントエンド側のフレームワークの想定~~ **決定: React**
  (2026-08-01、§6.4参照) — 生成するProps型は `interface Props { ... }`
  形式とし、Vueの`defineProps<...>()`やSvelte向けの形は採らない。

### 6.4 未決事項

- ~~アダプタの選定~~ **2026-08-01決定: InertiaNetCore。** 理由（ユーザーより）:
  InertiaCoreの開発が停滞しており、InertiaNetCoreは数少ない開発が活発な
  フォークの一つであるため。
- ~~フロントエンドフレームワークの選定~~ **2026-08-01決定: React。**
  理由（ユーザーより）: デジタル庁が公開しているリファレンススニペットが
  Reactで提供されているため。
- 既存の §8（汎用API連携）をInertia向けに置き換えるか、別モードとして
  両立させるかは要判断（オーバーエンジニアリング回避の観点では、
  当面Inertia向けに一本化する方がMVPとしてはシンプル）。

---

## 7. タスク2.5 実施結果: SDK同梱物のLSP/AST-dump機能調査 (Windows実機, 2026-08-01)

環境: RemObjects Elements 13.0.0.3101 (develop),
`C:\Program Files (x86)\RemObjects Software\Elements\`

### 7.1 調査方法

自前でlexerを組む前に、IDE自身の補完機能が既に使えるものを公開して
いないか確認した — どこかからトークン/構文情報を取得しているはずだから。
Elements SDKの公開API面をさらっと眺めていたら見つかった。

### 7.2 発見事項

1. **【重要】公開・インスタンス化可能な本物のOxygeneトークナイザーが存在する。**
   `RemObjects.Elements.Oxygene.dll` の
   `RemObjects.Elements.Code.Oxygene.Tokenizer`
   (コンストラクタ引数: `RemObjects.Elements.Code.TokenStream`、
   これも `public`) は `public` クラスで、IDE自身が補完に使う本番品質の
   レキサー。トークン種別・行/列位置を取得できる。
   → §2.9で保留にした「軽量ソーステキストスキャン」は、**自作の正規表現/
   簡易tokenizerではなく、この公式Tokenizerに乗る方式を推奨**。文字列
   リテラル・コメント・補間文字列を正しく無視した上で `nullable`/
   `not nullable` トークン検出や `Inertia.Render(...)` 呼び出し検出の
   括弧対応ができ、自作字句解析より言語仕様追従コストが大幅に下がる。
   ただし構文木 (式のネスト構造) までは提供しないため、複数行にまたがる
   呼び出しやジェネリクスの `<>` 判定は、トークン列の上に軽量パーサーを
   自前で被せる必要が残る (フルパーサーよりは遥かに軽量で済む)。

2. **コンパイラ内部にAST的なノード型が公開型として大量に存在する
   (`RemObjects.Elements.Compiler.dll`)。**
   `RemObjects.Elements.Code.CallExpressionTransform`,
   `IfStatementTransform`, `TypeStatementTransform`,
   `MethodStatementTransform` 等、式/文の種類ごとの型が `public`
   としてエクスポートされている。ただしこれらはコンパイラのパス変換
   パイプライン内部のノード型であり、Roslynの
   `SyntaxFactory.ParseSyntaxTree` に相当する「ソース文字列→構文木」の
   単純な公開エントリポイントは見当たらなかった。完全なコンパイル
   ユニット/プロジェクトコンテキストのセットアップが必要になる可能性が
   高く、簡単に呼び出せる代物ではなさそう (深追いしていない、要追加調査)。

3. **`RemObjects.Elements.Tools.dll` に `IOxygeneCodeModelParser`
   (`Parse(string) : System.CodeDom.CodeCompileUnit`) が存在するが、
   実装クラス名が `WinFormsCodeParser` であり、WinFormsデザイナー用の
   宣言的コード (`InitializeComponent()` 相当) を読み書きするための
   CodeDOMベースの限定的パーサーと判断される。** CodeDOMは表現力が
   限定的で一般的な式評価をサポートしないため、任意のメソッド本体内の
   `Inertia.Render(...)` 呼び出し検出のような汎用解析には向かない。

4. 独立したLSP実装や「AST-dump専用の隠しCLIフラグ」は見つからなかった。
   Water/Fire IDEの補完機能は、おそらく上記2のコンパイラ内部コード品質
   チェック機構をホストプロセス内で直接呼び出しており、外部プロセス向け
   LSPサーバーとしては切り出されていない模様。

### 7.3 §2.9・§4への影響 (方針)

- 「軽量ソーステキストスキャン」案は、**公式 `RemObjects.Elements.Code.
  Oxygene.Tokenizer` をベースにする方式**で採用する方向性を推奨する。
  この判断により、reflection方式との比較検討 (§2.9の判断保留事項) を
  Phase 2の早い段階で再開できる。
- フルAST方式 (上記2) は公開エントリポイントが不明瞭で追加調査コストが
  高いため、当面は見送り、Phase 2後半で余力があれば再検証する。

---

## 8. タスク1 実施結果: OxygeneのNRT出力を実機検証 (Windows実機, 2026-08-01)

**結論 (最重要ブロッカー解消): OxygeneのEchoesバックエンドは、`nullable`/
`not nullable` の情報をコンパイル済みアセンブリのメタデータに一切出力
しない。** `NullableAttribute`/`NullableContextAttribute` はおろか、
それに類する独自の属性・カスタム修飾子 (modopt/modreq) も一切見つから
なかった。§3-2の未検証事項は「Roslynと異なる独自属性を使っている」では
なく、「**そもそもIL/メタデータに何の痕跡も残さない**」という、
設計への影響がより大きい結果で確定した。

### 8.1 検証方法

1. `nullable String` / `not nullable String` を使ったフィールド・プロパティ・
   メソッド引数/戻り値を持つ最小クラスライブラリプロジェクトを作成
   (`.elements` プロジェクトファイル、`TargetFramework=.NETStandard`,
   `Mode=Echoes`)。
2. `EBuild.exe` でビルド (Release構成)。ビルド時点で判明した副次的事実:
   **`not nullable` なフィールド/プロパティは宣言時の初期化がコンパイラに
   強制される** (`E: Not nullable type requires initialization`) —
   すなわちnullableチェック自体はOxygeneコンパイラが実際に強制する
   本物の言語機能である (見せかけの構文ではない)。
3. 生成された `NrtProbe.dll` を .NET リフレクション
   (`System.Reflection.Assembly.LoadFile` + `CustomAttributeData`) で検査し、
   アセンブリ/モジュール/型/フィールド/プロパティ/メソッド引数・戻り値の
   全レベルでカスタム属性を列挙。あわせて `GetOptionalCustomModifiers()` /
   `GetRequiredCustomModifiers()` でmodopt/modreqも確認。

### 8.2 検証結果

- アセンブリレベル属性: `DebuggableAttribute`, `TargetFrameworkAttribute` のみ
  (Nullable関連なし)。
- モジュールレベル属性: なし。
- 型レベル属性 (`NrtProbe.Sample`): なし。
- フィールド属性: `NullableField` / `NotNullableField` / `PlainField`
  いずれも属性なし (プロパティの自動生成バッキングフィールドには
  `CompilerGeneratedAttribute` のみ付与、Nullableとは無関係)。
- プロパティ属性: `NullableProp` / `NotNullableProp` / `PlainProp`
  いずれも属性なし。
- メソッド引数・戻り値属性: `NullableParamMethod` / `NotNullableParamMethod`
  いずれの引数・戻り値にも属性なし。
- フィールドの custom modifiers (modopt/modreq): 全フィールドで空。
- アセンブリ内に `Nullable` を含む名前の型定義 (Roslynが旧TFM向けに
  埋め込むことがある `NullableAttribute`/`NullableContextAttribute` の
  自前定義) も存在しない。
- `ildasm` 等での生IL相互検証はツール未導入のため実施していないが、
  `CustomAttributeData` はメタデータテーブルを直接読む方式であり、
  上記の「属性なし」という結果自体はこれ単独で確定的と判断してよい。

### 8.3 設計への影響 (`docs/DESIGN.md` §4 の見直しが必要)

- **reflectionベースの `INullabilityProvider` チェーンだけでは、Oxygene
  自身が書いたコードのNRT情報を一切復元できない。** `RoslynStyleAttribute
  Provider` はOxygene製アセンブリに対しては常に "Unknown" を返すことになる
  (C#で書かれた依存先アセンブリに対してのみ有効)。
- 本ツールの主要ユースケース (Inertia.jsのPage Props/Controller自体が
  Oxygene製、§6参照) では、**NRT情報が必要ならソースレベルでの検出が
  必須**という結論になる。ここで §7 (タスク2.5) で見つけた公式
  `RemObjects.Elements.Code.Oxygene.Tokenizer` が直接活きる: `nullable`/
  `not nullable` トークンをソースから拾う軽量スキャン方式を、
  `INullabilityProvider` チェーンの実質唯一の実用的な実装として
  最優先で採用する必要がある (reflectionベースの代替案は同アセンブリ内
  Oxygeneコードに対しては機能しないため)。
- `docs/DESIGN.md` §4.2/§4.3 (「安全側 vs 有用性側、`--nrt-unknown-policy`
  で選択可能にする」という設計) はそのまま活きるが、"Unknown" ケースが
  「稀な例外」ではなく「reflection経路では常時発生する既定状態」に
  近い扱いになる点は明記しておく必要がある。
- 次にDESIGN.mdへ手を入れるセッションは、本セクションの結果を踏まえて
  `INullabilityProvider` の初期実装を「トークンスキャン方式」を主軸に
  据えて更新すること。

---

## 9. RemObjectsライセンス/EULA確認 (ベンダー回答、2026-08-01)

Elements SDKの公開API面をさらっと使う (§7) ことについて、Trial版の
ライセンス上の立場をRemObjectsに直接メールで確認した。同日 (2026-08-01)
に回答を得た。

### 9.1 質問と回答

1. **Elements SDKの公開されている型をさらっと眺める行為 (§7で実施) は、
   Trial版EULAにおける「リバースエンジニアリング」に該当するか？**
   → 該当しない ("i don't believe so")。
2. **公開`Tokenizer`クラスを、SDKのDLL自体を再配布せずに実行時の依存
   関係として参照・呼び出すことは許可されるか？**
   → 許可される ("Without redistributing these yourself, sure.")。
3. **ツールのソースコードを公開し続けてよいか？**
   → 問題ない。むしろ歓迎された ("Certainly. In fact i'd love to see
   it!")。
4. **Trial版でビルドしたバイナリを公開してよいか？**
   → **不可。** 「何かを配布するには」少なくともPersonalまたは
   Academicライセンスが必要とのこと。これは本リポジトリで既に
   運用ルール化していた制約 (Trial版でビルドした成果物はコミット・
   公開しない) を、ベンダー自身の言葉で裏付ける形になった。

**適用範囲についての注記:** ここで確認できたのは、あくまで質問した
狭い範囲の内容だけである — 公開API面をリフレクションでさらっと眺める
ことと、公開クラスを実行時に依存として使うこと。逆コンパイルや
逆アセンブルなど、上記で明示的に聞いていない行為にまで話を広げて
解釈しないこと。

### 9.2 回答から新たに浮上した未確認の制約

質問4への回答には、配布制限とは別に「製品を3日間より長く使うにも」
Personal/Academicライセンスが必要、という一文も含まれていた。これは
配布の有無とは無関係に、Trial版自体の**使用期限が3日**である可能性を
示唆しているが、正確な意味は未確認のまま:

- インストール (2026-08-01) からの暦日で3日か？
- 実際に使用した累積日数で3日か？
- 評価「セッション」の回数で3回か？

**この点は未解決。** Phase 2 (実装) はまだ始まっておらず、Elements/
EBuildを継続的にハンズオンで使う必要があるため、Phase 2を通してTrial版
の延長利用に頼る前に、RemObjectsへの確認 (またはPersonal/Academic
ライセンスの予算確保) を先に済ませておくべきである。3日間の期限が
切れるリスクがあるなら、§4の項目3 (MVP実装) に着手する前にフォロー
アップすること。

### 9.3 §11項目4 (配布/パッケージング方式) への影響

「配布/パッケージング方式」の未決事項は、技術的な優劣だけでなく
ライセンス状況とセットで決める必要がある: standaloneバイナリ配布
(npm同梱バイナリ、dotnet toolパッケージなど、ビルド成果物を配布する
あらゆる方式を含む) は、どのパッケージング方式を選んでも、少なくとも
Personal/Academicライセンスを取得するまでは実行できない。ソースのみの
配布はこの制約を受けない。

### 9.4 新たな調査の手がかり: 標準reflection外にNRT情報がある可能性 (未確認)

同じ回答の中で、EchoesがNullableAttribute/NullableContextAttributeを
出力しない (§8) と伝えたところ、RemObjectsの担当者はこう付け加えた:
「ああ、その情報はおそらくアセンブリのmetadata.fxスライスにあるはず」

これは、§8で確認した標準のECMA-335カスタム属性テーブル
(`CustomAttributeData`経由) 以外の場所——おそらくElements独自の
メタデータ領域/リソース ("metadata.fx") ——にNRT情報が存在する
可能性を示唆している。「おそらく (probably)」という言い回しから、
担当者自身も確信は持てていない様子で、この用語自体もまだ独自に
検証していない。未調査のまま。

**もしこれが事実であれば、§7/§8.3で採用したTokenizerによるソース
レベルスキャンを使わずに、NRT情報を直接復元できる**ことになり、
`INullabilityProvider` の設計をかなり簡略化できる可能性がある。
**§8.3の「Tokenizerが実質唯一の実用的な実装」という結論を、この点が
確認できるまで最終結論として扱わないこと。** フォローアップの方法は
2つ:

- 実機調査: コンパイル済みアセンブリのリソース/カスタムメタデータ
  セクションを覗き、"metadata.fx" に該当するものがあるか、標準の
  `System.Reflection` 以外の、文書化されたElements APIで読み取れるか
  を確認する。
- RemObjectsに直接、"metadata.fx"が具体的に何を指すか、コンパイラの
  外部から読み取り可能か (可能ならどうやって) を聞き返す。
