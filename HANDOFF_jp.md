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
   **2026-08-02に解決、§10参照: 使える** — ただし§10で見つかった
   EBuild/NuGetのパッケージング上の穴への対処が必要。
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

**更新 (2026-08-02): フォローアップを送付済み、返信待ち。** §9.1と
同じ担当者Marcに直接メールし、「3日間」が「30日間」のtypoではないか
確認を依頼した — ユーザーは当初30日間のTrialを想定しており、その
前提で「3日間」という記述を鵜呑みにする前に確認しておきたいとのこと
だった。本稿執筆時点ではまだどちらとも確認が取れていない。上記の
「§4項目3に着手する前に」というトリガーポイントをすでに過ぎ、
Phase 2は§16まで進んだ状態でも返信は届いておらず、実際にはこの回答を
待たずにTrial版の利用を続けている。Marcから返信があり次第この節を
更新すること — もし本当に30日間であれば、課題管理表
(`reports/2026-08-02-issue-tracker.csv`)の項目#19の緊急度は大きく
下がる。

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

---

## 10. タスク2の結果: Oxygene/Echoesから`MetadataLoadContext`が使えるかの
    実機検証 (Windows実機、2026-08-02)

**結論 (§4項目2は解決): `System.Reflection.MetadataLoadContext`は
Oxygene/Echoeから使用可能**。これにより、設計全体の前提である「対象
アセンブリのメタデータのみを実行せずに読み込む」というStage 1
(Loader) の実装方針が技術的に成立することが確認できた。検証の過程で、
これとは別の実在するパッケージング上の穴 (§10.2参照) も見つかった —
このパッケージ1つに限らず、Echoes/.NETCore実行ファイルがNuGetの
実行時依存関係全般に頼る際に注意すべき点として記録しておく。

### 10.1 検証方法

1. 最小限のOxygeneクラスライブラリ (`TargetLib`、`.NETStandard` /
   `Mode=Echoes`) を作成。プロパティ2つとメソッド1つを持つクラスを1つ
   置き、「メタデータのみで読み込む対象アセンブリ」の役とした。
2. 別途、Oxygeneコンソールアプリ (`Probe`、`TargetFramework=.NETCore` /
   `Mode=Echoes`、`OutputType=Exe`) を作成し、
   `<NuGetReference Include="System.Reflection.MetadataLoadContext:8.0.0" />`
   という項目で`System.Reflection.MetadataLoadContext` NuGetパッケージを
   参照した (この構文は、`NuGetReference`を使っている唯一の同梱サンプルである
   公式ASP.NET Core/React用Waterプロジェクトテンプレートから確認した)。
3. `Probe`の`Main`は、ランタイムディレクトリ内のDLL一覧
   (`RuntimeEnvironment.GetRuntimeDirectory()`) と対象アセンブリのパスから
   `PathAssemblyResolver`を組み立て、`using`ブロックで`MetadataLoadContext`
   を開き、`TargetLib.dll`に対して`LoadFromAssemblyPath`を呼び、
   `GetTypes()` / `GetMembers()`でメタデータが読み取れることを確認する。
4. 両プロジェクトとも`EBuild.exe /Configuration:Release`でビルドし、
   生成された`Probe.exe`を直接実行した。

### 10.2 結果と、途中で見つかったパッケージング上の穴

- コードは**問題なくコンパイルできた** — `PathAssemblyResolver`/
  `MetadataLoadContext`の構築、ジェネリックの`List<String>`、`using`
  ブロックなど、この.NET BCL隣接のAPI群をOxygeneから呼び出すことに
  支障はなかった。
- **初回実行は失敗した**。DLLを手動で出力ディレクトリにコピーして
  物理的に存在させていたにもかかわらず、
  `System.IO.FileNotFoundException: Could not load file or assembly
  'System.Reflection.MetadataLoadContext, ...'`というエラーになった。
  根本原因: EBuildの`NuGetReference`解決が、要求したパッケージバージョン
  (`8.0.0`) を暗黙に`10.0.10`へ引き上げていた (インストール済みの.NET
  10 SDK/ランタイムに合わせたもの — このマシンにインストールされている
  共有ランタイムは`Microsoft.NETCore.App 10.0.9`)。しかし生成された
  `Probe.deps.json`は、そのターゲット向けの`dependencies`一覧に
  パッケージ名を記録しただけで、**どのDLLファイルがその依存を実体として
  提供するかを示す`"runtime"`アセットエントリを欠いていた**。この
  エントリがないと、`deps.json`から構築されるCLRの信頼済みプラット
  フォームアセンブリ一覧にそのファイルが含まれず、`.exe`のすぐ隣に
  置いてあっても見つからない。
- `Probe.deps.json`を手動でパッチし、パッケージのターゲットブロック下に
  欠けていた`"runtime": { "System.Reflection.MetadataLoadContext.dll": { ... } }`
  エントリを追加したところ、`Probe.exe`が正常に実行できることを確認し、
  これが実際の根本原因であると裏付けが取れた:
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
- **新たな未調査事項 (これ以上は未調査): `Mode=Echoes` /
  `TargetFramework=.NETCore`の実行ファイルにおいて、EBuildの
  `NuGetReference`パッケージングがNuGet由来の依存関係の実行時アセット
  エントリを`deps.json`へ確実には反映しないように見える。** これは
  元々のMetadataLoadContextの疑問とは別の、ビルドツールチェーン側の
  リスクである。このパッケージ1つに限らず、本ツールが実行時に依存する
  ことになる*あらゆる*NuGetパッケージに影響しうるため、Phase 2のCLI
  スケルトンが実行時に使うNuGet依存関係を初めて持つ前に、実際の修正
  (または少なくとも文書化された回避策 — 例: ビルド後の`deps.json`
  パッチ工程、あるいは自動アップグレードの経路を踏まないパッケージ
  バージョンへの固定など) が必要である。これが他のパッケージ、他の
  ターゲットフレームワーク・モニカーでも再現するか、あるいは
  「EBuildが要求より新しいバージョンへ『アップグレード』したパッケージ」
  に限って起きるのかは未確認 — Phase 2でCLIスケルトンが最初の実際の
  NuGet依存関係を持つタイミングで、早めに再確認する価値がある。

### 10.3 成果物について

`TargetLib`/`Probe`の検証用プロジェクトは、このセッションのTemp
スクラッチパッド配下でビルドしたものであり、本リポジトリ配下では
ない — 使い捨てのハンズオン検証であって、リポジトリのフィクスチャ
ではなく、セッションをまたいで残ることはない。この結果の再現確認を
後で行いたい場合は、これらのファイルがまだ存在すると仮定せず、§4
項目4に沿って`tests/fixtures/`配下に小さなフィクスチャとして作り
直すこと。

### 10.4 設計への影響

- `docs/DESIGN.md` §11項目2 (今回のタスクが答えた未決事項) は解決済みと
  してよい: メタデータのみの読み込みを`MetadataLoadContext`経由で行う
  ことが、Stage 1 (Loader) の確定した実装方針であり、この部分について
  ECMA-335パーサの自作や代替ライブラリは不要である。
- §10.2のNuGet/`deps.json`パッケージングの穴は、`docs/DESIGN.md`が
  これまで想定していなかった新しいリスクである (設計は依存関係の
  デプロイについて標準的な.NETツールチェーンの挙動を前提としていた)。
  §4項目3 (CLIスケルトン) の着手を妨げるものではないが、スケルトンが
  何らかの実行時NuGet依存関係を持つようになった時点で念頭に置くこと —
  `EBuild`のコンパイルが成功したからといって、正しくデプロイ可能な
  出力になっているとは限らないので、確認すること。

---

## 11. Phase 2着手: MVPスコープの決定 (2026-08-02)

§4項目3のための`src/`実装コードを書き始める前に、以下のスコープ判断を
行った (ユーザーに実際の分岐として確認を取ったものはその旨明記、それ
以外は実装上のデフォルト判断としてここに記録し、暗黙のまま進めない)。
実際に何を作ったかの詳細な報告は§12にある。

- **MVPのnullable(NRT)対応は、最初からTokenizerベースのソーススキャン
  を使う**。`docs/DESIGN.md` §10.1が元々書いていた「reflectionスタブ
  のみ」の経路ではない。ユーザー確認済み: これにより、Oxygene製の
  すべての型でnullabilityが常に`Unknown`になってしまうMVPを出すのでは
  なく、§8.3の結論をきちんと反映させることになる。帰結として、CLIには
  `docs/DESIGN.md` §10.1が元々描いていた`--assembly`/`--out`だけの
  形に加えて、新たに`--source <dir>`という入力が必要になる。
- **NRTスキャナのスコープ: MVPではプロパティとフィールドのみ。**
  メソッドのパラメータ/戻り値のnullability (§8の実機検証でも対象に
  含めていた) は見送る — Inertia Page Propsの形 (§6) には影響しない、
  実際にシリアライズされるのはプロパティ/フィールドの方だから。
- **出力モード: MVPでは単一ファイルの`.d.ts`のみ**(.NETの名前空間に
  対応する`declare namespace`をネストした1ファイル)。
  `docs/DESIGN.md` §7.3が併せて説明しているsplit-file / ESモジュール
  レイアウトは見送る。
- **型マッピング: MVPではStage 3の代わりにハードコードしたプリミティブ
  /enumマッピング関数を使う**。プラガブルな`ITypeMappingRule`チェーン
  ではない — `docs/DESIGN.md` §10.2がプラグイン機構をpost-MVPリストの
  終盤に置いている方針と一致する。
- **enum戦略: numericとstring-literal-unionの両方を実装**、
  `--enum-style`フラグで切り替え可能(emitter内の小さな分岐で済むので
  安く済み、§10.1の「設定で選択可能」という文言からわざわざ1つに絞る
  理由はない)。
- これらの決定により、§4項目3(本タスク)のスコープは: Stage 1 Loader
  (§10の`MetadataLoadContext`によるreflection) + プロパティ/フィールド
  限定のTokenizer NRTスキャン + 軽量Stage 2 IR + Stage 4の単一ファイル
  `DtsEmitter`、に収まる。循環参照検出・ジェネリクス・split-file出力・
  プラグインチェーン・メソッドレベルNRTはすべて`docs/DESIGN.md` §10.2
  通りpost-MVPのまま。

---

## 12. タスク3の結果: MVP実装 (`src/Tsgen`)、Windows実機、2026-08-02

**§4項目3が完了した。** `src/Tsgen`は実際に動くCLI
(`tsgen generate --assembly <dll> --source <dir> --out <dir>`) で、
Oxygeneでビルドされたアセンブリを`MetadataLoadContext`(§10)経由で
読み込み、そのソースを実際のOxygeneトークナイザで`nullable`/
`not nullable`をスキャンし、軽量IRを構築し、単一ファイルの`.d.ts`を
出力する。`tests/fixtures/SampleModel`に対してend-to-endで検証済み
(§12.5参照)。

### 12.1 プロジェクト構成

```
src/Tsgen/Tsgen.elements       -- Exe, Mode=Echoes, TargetFramework=.NETCore
src/Tsgen/Loading/              -- Stage 1: RawModel.pas, AssemblyLoader.pas
src/Tsgen/Nrt/                  -- NullabilityScanner.pas (Tokenizerベースのスキャン)
src/Tsgen/Ir/                   -- Stage 2: IrModel.pas, TypeMapper.pas, IrBuilder.pas
src/Tsgen/Emit/                 -- Stage 4: DtsEmitter.pas
src/Tsgen/Cli/Program.pas       -- 引数解析 + パイプライン接続
tools/dev-build.ps1             -- ビルド + deps.json回避策、§12.3参照
tests/fixtures/SampleModel/     -- 実機検証用フィクスチャ、§12.5参照
```

MVPではCLIからライブラリを分離せず単一プロジェクトとした — まだ別々の
利用者がいないので分離する理由がない。2つ目のエントリポイント
(MSBuildタスクやwatchモードのホストなど) が出てきたら見直すこと。

### 12.2 使えるトークナイザのエントリポイントを見つけるまで

`HANDOFF.md` §7では公式レキサーとして
`RemObjects.Elements.Code.Oxygene.Tokenizer`
(コンストラクタ引数は`TokenStream`) を挙げていたが、その公開APIは
生の逐次状態機械 (`Next()`、`CurrTokenID`、`Row`/`Col`など) で、
「文字列全体をトークナイズする」ような単純なエントリポイントは
なかった — §7.2の「トークンストリームの上にまだ軽量パーサを
乗せる必要がある」という警告通りだった。reflectionでの調査
(`ReflectionOnlyLoadFrom` + 依存関係チェーン`RemObjects.Elements.dll`、
`RemObjects.Elements.Code.dll`を手動で事前ロード。スクリプトからは
`ReflectionOnlyAssemblyResolve`を使えなかったための回避策) の過程で、
もっと扱いやすい代替が見つかった:

- **`RemObjects.Elements.Oxygene.SimpleTokenizer`** — `Parse(text:
  String): Void`と`Items: List<TokenValue>`
  (`TokenValue` = `{ Token: Int32, StartPos: Int32, Length: Int32 }`)を
  持つ公開の静的クラス。**実機での試行錯誤で見つかったクセ(どこにも
  文書化されていない):** `Parse`は常に与えた文字列の**先頭の1トークン
  だけ**しか返さない — 同じ文字列に対して繰り返し呼んでも進まない。
  そのためスキャナは、縮めていく部分文字列に対して`Parse`をループで
  呼び、毎回絶対オフセットを計算し直す方式にした。これで動くには
  動くが、末尾に何も続かない孤立した`.`(例えば末尾改行のない
  ユニットの最後の`end.`)を渡すと、`Parse`内部の何らかのループが
  暴走してプロセスが"Out of memory."で落ちる — `NullabilityScanner`
  では`Parse`を呼ぶ**前**に`remaining.Trim() = '.'`(および
  `Length = 0`)をチェックすることでこれを回避している(呼んだ後で
  はない)。将来このスキャナを書き直す際も、このガードか同等の対策を
  残すこと。
- **トークンID定数**は`RemObjects.Elements.Code.Oxygene.Token`
  (enumではなく、抽象の静的専用クラス) の公開static `Int32`フィールド
  として存在する。例: `TI_class=208`、`TI_nullable=250`、`TI_not=249`、
  `TI_property=259`、`TI_begin=205`、`TI_end=219`、`T_Identifier=100`、
  `TINT_WhiteSpace=69`、`T_Colon=104`、`T_SemiColon=110`、
  `T_OpenRound=105`、`T_CloseRound=106`、`T_Dot=103`。実際のスニペット
  に対する`SimpleTokenizer`の出力と突き合わせて正しいことを確認済み
  (§12.5のサンプルダンプ参照)。全フィールド一覧(277個)はここには
  転記していない — 今後さらに必要になったら(例えばメソッドレベルの
  NRT対応。パラメータリストのトークンなどが要る。§11で一部スコープ
  外にした部分)、`RemObjects.Elements.Oxygene.dll`の`Token`クラスに
  対して`ReflectionOnlyLoadFrom` + `GetFields(Public, Static)`で
  再度導出すること。

### 12.3 `deps.json`の穴はNuGetだけでなくローカルReferenceでも再現する

§10.2では`NuGetReference`でこの問題を確認したが、通常の
`<Reference Include="..."><HintPath>...</HintPath></Reference>`項目
(ここでは`RemObjects.Elements(.Code/.Oxygene).dll`に使用。`CLAUDE.md`の
ライセンス方針に従い`Private=False`、つまり明示的に自分たちの出力には
コピーしない設定) でも全く同じ形で再現した。つまりこれはNuGet固有の
問題ではなく、`Mode=Echoes` / `TargetFramework=.NETCore`の**実行
ファイル**において、基本フレームワークを超える参照全般に効いてくる
EBuildの一般的な穴だということになる。

**回避策を`tools/dev-build.ps1`として定型化した:** `EBuild.exe`を実行し、
4つの追加DLL (`System.Reflection.MetadataLoadContext.dll`はEBuildの
NuGetパッケージキャッシュから、残り3つの`RemObjects.Elements*`系DLLは
Elementsインストール先から) を`Bin/Release`にコピーし、
(`ConvertFrom-Json`/`ConvertTo-Json`経由で) `tsgen.deps.json`に欠けている
`"runtime"`アセットエントリを追加パッチする。ビルドのたびにこの
スクリプトを再実行すること — 素の`EBuild.exe`ビルドだけではコンパイル
は通っても、§10.2と同じく起動時に`FileNotFoundException`で落ちる。
このスクリプトは現在のElementsバージョン(`13.0.0.3101`)と、ローカルに
`.NET 10` SDKが入っていることを前提にハードコードしている — ローカル
環境が変わったらスクリプト内の`$RemObjectsElementsVersion`を更新する
こと。これはあくまで開発ループ用の便宜的スクリプトであり、EBuild本体
の不具合を修正するものではない(RemObjectsへの報告は未実施、他の
マシン/SDKでも再現するかは未確認のまま)。

### 12.4 Oxygeneコードを書く中で遭遇したその他の落とし穴

- **`nullable`、`property`、`namespace`は予約語**であり、自分の識別子
  (enumメンバー、フィールド名) には使えない — にもかかわらず、まさに
  `NullabilityScanner`が*他の*コードの中から検出しようとしている単語
  そのものである。リネーム対応: `RawMemberKind.Property` →
  `.PropertyMember`、`NullabilityKind.Nullable`/`.NotNullable` →
  `.IsNullable`/`.IsNotNullable`、`RawType.Namespace`/
  `IrTypeLite.Namespace` → `.NamespaceName`。すでに`Namespace`という
  名前を持つ*外部の*メンバー(例えばreflectionの
  `System.Type.Namespace`)を読み取るのは問題なくコンパイルできる —
  制約はあくまで、裸の予約語で自分の識別子を宣言することに対して
  であり、メンバーアクセスには及ばない。
- **Oxygeneの`case`文は、C#の`switch`のように文字列を対象にはできない
  らしい**(CLIフラグ解析とenum-文字列マッピングで試しただけで、公式
  ドキュメントでは未確認)。`String`を分岐対象にする箇所はリスクを
  取らず`if`/`else if`の連鎖にした。`Int32`のトークンID(順序型)に
  対する`case`はスキャナ全体で問題なく使えている。
- **`not nullable`のフィールド/プロパティは宣言時に初期化が必須**
  であることを改めて確認した(§8.1で既知): `property Id: not
  nullable String read write := '';` — `:= <デフォルト値>`は
  `read write`の**後**に置く、前ではない
  (`tests/fixtures/SampleModel/SampleModel.pas`)。

### 12.5 End-to-end検証

フィクスチャ: `tests/fixtures/SampleModel/SampleModel.pas` — enum
(`Status`) とクラス (`User`)。`User`には`not nullable`なプロパティ1つ、
`nullable`なプロパティ1つ、NRTアノテーションが全くないプロパティ2つ
(`--nrt-unknown-policy`の動作確認用)を持たせた。

コマンド (`tools/dev-build.ps1`実行後):
```
tsgen generate --assembly tests/fixtures/SampleModel/Bin/Release/SampleModel.dll \
               --source tests/fixtures/SampleModel \
               --out tests/fixtures/SampleModel/dist
```

出力 (`tests/fixtures/SampleModel/dist/index.d.ts`、デフォルトの
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
`Id`(明示的に`not nullable`)には`| null`が付かず、`DisplayName`
(明示的に`nullable`)には付く。`Age`/`IsAdmin`(アノテーションなし、
すなわち`Unknown`)は`--nrt-unknown-policy`のデフォルト(`nullable`)に
従う。`--enum-style union --nrt-unknown-policy non-null`で再実行した
ところ、enumは正しくstring-literal unionに切り替わり、`| null`は
`Age`/`IsAdmin`からのみ外れた(`DisplayName`からは外れなかった) —
このポリシーが本当に`Unknown`なメンバーにのみ適用され、明示的に
アノテーションされたメンバーには適用されないことが確認できた。

### 12.6 既知の限界・未対応事項

- **NRTスキャナはヒューリスティックであり、本物のパーサではない。**
  `class`/`record`/`interface`/`begin`/`try`/`case`のネストを単一の
  深さカウンタ+メソッドのパラメータリストを除外するための括弧深さ
  カウンタで追跡しているだけ(§11ですでにメソッドレベルNRTはスコープ
  外にした) — ネストした型、1つの`type`セクションに複数の型がある
  場合、インデクサ形式のパラメータを持つプロパティに対しては未検証。
  実際の、より大きなOxygene/Inertiaコードベースに頼る前に、
  `tests/fixtures/`によるケースを増やして堅牢化すること。
- 単一ファイルの`.d.ts`出力のみ、Stage 3のプラガブルチェーンの代わりに
  ハードコードしたプリミティブ/enum型マッピング、循環参照検出なし、
  ジェネリクスなし — すべて§11のスコープ決定と
  `docs/DESIGN.md` §10.2の既存のpost-MVP順序通り。
- `tools/dev-build.ps1`の`deps.json`パッチは回避策であり修正ではない。
  もし本プロジェクトが実際にパッケージ化/配布可能なビルドを必要と
  するようになったら(§9.3の通りTrialライセンスでは既にブロック
  されているが)、この穴には本当の解決が先に必要になる。
- 自動テストランナーはまだ組み込んでいない — `tests/fixtures/SampleModel`
  は今回のセッションで手動検証したのみ。§4項目4
  (スナップショット比較によるテスト基盤) は引き続き未着手。

---

## 13. レビュー後の修正 (Fable5による設計レビュー、同一セッション、2026-08-02)

設計レベルのレビュー(§11のスコープ決定と§12の実装内容を批評するよう
プロンプトしたFable5エージェントとして実行)で複数の問題が指摘された。
ユーザーは重要度の高いものをその場で修正することを選び、先送りにし
なかった。レビュー本文はここには転記せず、その結果として何を変更した
かのみ記録する。

- **IR再構成(レビューの主な構造的異議)。** `IrMemberLite`は、事前に
  マッピング済みの`TsType: String`や事前に解決済みの`IsNullable:
  Boolean`をもう保持しない — 代わりに生の`ClrTypeName: String`と
  三値の`Nullability: NullabilityKind`を保持する。`IrBuilder`
  (Stage 2)はもう`TypeMapper`を呼んだり`--nrt-unknown-policy`を適用
  したりしない — どちらも`DtsEmitter`(Stage 4)へ移した。理由:
  旧構造は暗黙のうちにStage 3(型マッピング)をStage 2に折り込んで
  しまっており、`docs/DESIGN.md` §1.2が明示的に却下した「Loaderが
  直接TS ASTを組み立てる」案を実質再現していた上、
  `docs/DESIGN.md` §4.3の`mark-unknown`ポリシーに必要な「明示的な
  アノテーション」と「Unknown+ポリシー適用」の区別も潰していた。
  `IrBuilder.Build`と`DtsEmitter.Emit`のシグネチャもこれに合わせて
  変更した(`src/Tsgen/Ir/IrBuilder.pas`、
  `src/Tsgen/Emit/DtsEmitter.pas`参照)。
- **`NullabilityScanner`のトークンIDを
  `RemObjects.Elements.Code.Oxygene.Token`の公開static フィールドへの
  直接参照に変更した**(`Token.TI_class`、`Token.TI_nullable`など)。
  ハードコードしたローカルのマジックナンバーではなくした — Elementsは
  週次リリース製品であり(§3)、これらはコンパイラ内部の序数だから。
- **実バグを1つ修正した**: 複数識別子のフィールド宣言
  (`FirstName, LastName: nullable String;`)で、コロン直前の1つを
  除く全ての名前が無言で`Unknown`のままになっていた。
  `tests/fixtures/SampleModel/SampleModel.pas`にこの形の宣言を
  回帰テストケースとして追加し、修正後は両方とも正しく`nullable`に
  なることを確認した。
- **不正確なコメントを修正した**: `NullabilityScanner.pas`に「ネスト
  した型は"innermost type"が勝つ」という趣旨のコメントがあったが、
  実際のコードは逆(`currentTypeName`は一度しか代入されないため、
  外側の型が勝つ)だった。コメントを修正、挙動自体は変更なし
  (引き続き既知の限界、§12.6)。
- **`TypeMapper`のフォールバックを`'any'`から`'unknown'`に変更した**。
  `docs/DESIGN.md` §2.4が未マッピング型に対して指定しているポリシーに
  合わせた(従来の`'any'`フォールバックは、まさにこのツールの価値の
  核心である型安全性が失われる箇所で、無言で型チェックを無効化して
  いた)。このフォールバックが発動した際、`DtsEmitter`が未マッピング
  のCLR型とメンバー名を示す警告も出すようにした。
- **従来無言だった2つの失敗モードに警告を追加した**: `Program.pas`は
  `--source`が省略された場合(全メンバーがNRT情報ゼロのままunknown-
  policyのデフォルトにフォールバックする)に警告を出すようになり、
  `AssemblyLoader`は非public/ネスト/ジェネリック/非対応種別の型を
  無言で捨てるのではなく、件数をカウントして警告するようになった。
- **`.gitignore`を強化した**: `bin/`/`obj/` → `[Bb]in/`/`[Oo]bj/`
  (Elementsはフォルダ名を大文字始まりの`Bin`にする。小文字のみの
  パターンはWindowsのファイルシステムが大文字小文字を区別しない
  ことに偶然助けられていただけだった)。加えて`*.deps.json`/
  `*.runtimeconfig*.json`パターンも明示的に追加し、ビルド成果物を
  誤ってコミットしないための保険を増やした。
- **`IsTypeOpen`のルックバック上限を8から64トークンに引き上げた**
  (`class`/`record`/`interface`の前に長い修飾子の連なりがあると
  超えかねない、恣意的に小さすぎる上限だった)。
- 上記すべての後、`tools/dev-build.ps1`と
  `tests/fixtures/SampleModel`のend-to-end確認(デフォルトフラグ、
  および`--enum-style union --nrt-unknown-policy non-null`)を再実行
  — 新しい`FirstName`/`LastName`の回帰テストケース分を除いて出力は
  変わらず、今回の再構成によるリグレッションがないことを確認した。

**今回あえてやらなかったこと**(レビューではこれらも指摘されたが、
規模が大きい、あるいは緊急度が低いため、将来のセッションに残した。
レビューが提案した順序で列挙する):
1. §9.4の"metadata.fx"の手がかりを確認すること(もしNRT情報が
   メタデータから直接復元可能だと分かれば、Tokenizerスキャナという
   アプローチ全体が不要になる可能性がある — 安価に確認できるので、
   スキャナの堅牢化にこれ以上投資する前にやるべき)。
2. `tests/fixtures/SampleModel/dist/index.d.ts`を、固定したスナップ
   ショットテストの基準として自動比較スクリプトと共にコミットする
   こと(§4項目4) — レビューは「今後のIR変更の前に」やることを
   提案していた。§13の再構成の前にはそれをやらず、代わりに手動での
   出力比較で確認し、今回はたまたまうまくいった。これは「今回は
   たまたま切り抜けられた」だけであって、「順序に関する助言が
   もう不要になった」という意味ではないと捉えること — *次の*構造
   変更の前にはスナップショット基盤を必須の前提条件とすべき(下の
   項目3がまさにそういう種類の変更にあたる)。
3. `NullabilityScanner.Tokenize`を、`SimpleTokenizer`の縮小部分文字列
   ループ方式から、本来の逐次型`RemObjects.Elements.Code.Oxygene.
   Tokenizer`/`TokenStream`へ書き直すこと(§12.2) — OOMガード、
   セーフティカウンタ、O(n²)の文字列コピーを取り除けるが、§12.2で
   あえて避けた低レベルAPIの調査を再び開くことになる。修正作業に
   折り込むには十分大きく、独立したセッションに値する。
4. `INullabilityProvider`チェーンの抽象化と、3つ目
   (`mark-unknown`)の`--nrt-unknown-policy`値の追加 — 上記のIR
   再構成により、三値の`Nullability`がemitterまで保持されるため、
   どちらも今なら実装しやすくなっている。ただし実際に配線するのは
   新規スコープであり、既存実装への「修正」ではない。
5. `docs/DESIGN.md` §4の書き直し(2026-08-01から追跡中、引き続き
   未着手)と、§10.1/§11の陳腐化したMVP記述の同期 — これはコードでは
   なくドキュメント上の負債であり、レビューは現在この点が設計書の
   3箇所に広がっていると指摘した。
6. §9.2のTrialライセンス3日間上限問題の解決 — コードのタスクでは
   なく、ベンダーへのフォローアップかライセンス購入の判断が必要。
   レビューは、Phase 2が継続的にEBuildを使い続けている現状を踏まえ、
   この問題の緊急度が増していると指摘した。
7. ~~`deps.json`の実行時アセットの穴(§10.2/§12.3)をRemObjectsに
   報告すること。~~ **完了、2026-08-02、§17参照。** これは元の
   レビューで`.gitignore`の修正と並んで「先延ばしにすべきでない」
   リストに入っていたが、このセクションの一回目の記載では抜け落ちて
   いた — 修正内容を検証する2回目のレビューでこの抜けが指摘された。
   RemObjectsは(§9で)一度メールに迅速に対応済みで、Elementsは週次
   リリースなので、実際に上流で修正してもらえる見込みは十分ある。

---

## 14. §9.4フォローアップ解決: `metadata.fx`にNRT情報は含まれない(Windows実機検証、2026-08-02)

**結論(§13あえてやらなかったこと項目1 / §9.4を解決): `metadata.fx`
マニフェストリソースは実在するが、nullable/not nullable情報は
含んでいない。** §8.3の結論は変わらない: TokenizerベースのソースAPI
スキャンが、実用上唯一の`INullabilityProvider`実装であり続ける。
コードの変更は伴わないが、未解決の疑問を1つ閉じ、スキャナのさらなる
作業(§13あえてやらなかったこと項目3)を保留する理由を取り除いた。

### 14.1 検証方法

1. このセッション途中で.NET 10 SDKをこのマシンにインストールした
   (それまではランタイムのみが入っており、`dotnet new`/`dotnet build`
   がブロックされていた)。
2. `src/Tsgen`には属さない使い捨てのコンソールアプリを書いた(セッションの
   scratchpadでのみビルド・実行し、コミットは一切していない)。標準の
   ドキュメント化されたAPIである`System.Reflection.PortableExecutable.
   PEReader` + `System.Reflection.Metadata.MetadataReader`を使い、
   `tests/fixtures/SampleModel/Bin/Release/SampleModel.dll`と
   `src/Tsgen/Bin/Release/tsgen.dll`の`ManifestResource`エントリを
   列挙した。
3. 両アセンブリとも、**`metadata.fx`**という名前のマニフェストリソースを
   ちょうど1つ埋め込んでいることを確認した(`Implementation`はnil、
   つまりアセンブリ自身のCOR20リソースBlobに格納されている) — §9.4の
   RemObjects担当者の("probably"付きの)発言とほぼ一致する。リソース
   先頭には`ROSF`というマジックバイト(おそらく「RemObjects Software
   Format」)があった。
4. リソース本体をダンプし、手動で調査した: 印字可能文字列の粗い
   スキャンと、`SampleModel.User`の既知のプロパティ名(`Id`、
   `DisplayName`、`Age`、`IsAdmin`、`FirstName`、`LastName`)周辺を
   狙ったヘックスダンプを行った。

### 14.2 `metadata.fx`の実際の中身

- 参照アセンブリ名の大きなフラットリスト(`Echoes`、`mscorlib`、
  `netstandard`、`System.Collections.Concurrent`など — このプロジェクト
  固有ではなく、.NETの参照アセンブリ/facade一覧そのものに見える)。
- メンバーごとのコンパクトなシンボル索引: プロパティ/フィールドごとに、
  素の名前、メンバー種別タグ(プロパティとフィールドでタグが異なる)、
  XMLドキュメントID風のシグネチャ文字列(`P:Id`、`F:FirstName`、
  メソッドについては`M:get_Id-System.String`、
  `M:set_DisplayName-System.String`等)を含むレコード。§7が推測していた
  IDEの補完/「シンボル検索」機能を支える索引のように見える —
  名前/種別/シグネチャの検索テーブルであって、完全な意味モデルではない。
- 上記のメンバーレコードから参照される、正規化された型名文字列の小さな
  重複排除テーブル(`System.String`、`System.Int32`、`System.Boolean` —
  それぞれちょうど1回だけ出現)。

### 14.3 `metadata.fx`からNRTを復元できないと言える理由

`Id`(`not nullable String`)のレコードと、`DisplayName`/`Age`/`IsAdmin`
(それぞれ`nullable`/未注釈のString、Int32、Boolean)のレコードを
バイト単位で比較した — 元の§8実機検証と同じソースファイル
(`tests/fixtures/SampleModel/SampleModel.pas`)を使っているため、各
メンバーの宣言上のnullabilityという正解はすでに独立に分かっている:

- 宣言されたnullabilityに関わらず、すべてのプロパティレコードは
  **完全に同一のバイト構造**を持つ(タグの並びは同じで、名前文字列・
  その長さ・小さな連番インデックス値だけが異なり、いずれも
  nullabilityとは無関係)。
- 正規化された型名テーブルには`System.String`のエントリが
  **1つだけ**存在し、`Id`(not nullable)と`DisplayName`(nullable)の
  両方から共有されている — もしnullabilityが別の参照型(例えば
  ラッパー型名)として符号化されているなら、少なくとも2種類の
  String関連エントリが必要になるはずだが、実際には1つしかない。
- その共有された`System.String`エントリへの2つの使用箇所参照
  (1つは`Id`のget/set用、もう1つは`DisplayName`のget/set用)は、
  一方が`not nullable`でもう一方が`nullable`であるにもかかわらず、
  **バイト単位で完全に同一**だった。

これは`ROSF`バイナリプロトコルの全面的なリバースエンジニアリングでは
ない(それははるかに大規模で、価値の低い作業になる可能性が高く、
§9.4が求めていた「安価な最初の一手」の範囲を明確に超える) — しかし
今回の論点にとって直接、正解データに基づいた比較であり、3つの観点
すべてで否定的な結果が得られた。これ以上投資せずに疑問を閉じるには
十分である。

### 14.4 設計/タスクリストへの影響

- `HANDOFF.md` §9.4の「標準reflection以外の場所にNRT情報がある
  可能性」という手がかりは解決した: **ない**、少なくとも標準の
  `metadata.fx`リソースの中には。`docs/DESIGN.md` §4を再度見直す
  必要はない — §8.3からすでに文書化されているTokenizerベーススキャン
  という結論はそのまま正しい。
- §13あえてやらなかったこと項目3(`NullabilityScanner`を
  `SimpleTokenizer`から、本来の逐次型
  `RemObjects.Elements.Code.Oxygene.Tokenizer`/`TokenStream`へ
  書き直すこと)は、この未解決の疑問に足を引っ張られることなく
  進められるようになった。
- 副次的な発見(今回は対応せず): §13までの間、このマシンには.NET
  ランタイムのみが入っており、SDKは入っていなかった — `dotnet
  build`/`dotnet new`/`dotnet run`は使えず、`EBuild.exe`経由の
  ビルド済みapphost(`tsgen.exe`など)を実行することしかできなかった。
  この調査を進めるために、2026-08-02のセッション途中でSDKを
  インストールした。`tools/dev-build.ps1`(引き続きEBuild主導)への
  影響はないはずだが、今後のセッションで素の`dotnet`ツールチェーンに
  直接手を伸ばしたくなった場合、SDKが既に入っていることは覚えておく
  価値がある。

---

## 15. §4項目4完了: スナップショットテスト基盤 (Windows実機検証、2026-08-02)

**§13あえてやらなかったこと項目2が完了した。** `tools/run-tests.ps1`は
CLIと`tests/fixtures/`配下の全フィクスチャをビルドし、各フィクスチャの
`cases.json`で宣言されたケースごとに`tsgen`を1回実行し、結果を
コミット済みの`expected/*.d.ts`スナップショットと比較する。これは
レビューの当初の順序に従い、§13あえてやらなかったこと項目3(NRT
スキャナのトークナイズループの作り直し)より**先に**あえて行った —
§14がその作業を保留する理由をすでに取り除いていたためである。

### 15.1 構成

```
tests/fixtures/SampleModel/
  SampleModel.pas / .elements   -- 変更なし
  cases.json                     -- 新規: {name, args, expected}のリスト
  expected/
    default.d.ts                 -- CLIデフォルト(数値enum、nullable-unknown)
    union-nonnull.d.ts           -- --enum-style union --nrt-unknown-policy non-null
tools/run-tests.ps1              -- 新規: ランナー本体(詳細は下記)
```

`cases.json`があることで、ランナーはフィクスチャに依存しない汎用的な
作りになっている — 今後新しいフィクスチャを追加する際は、`.pas`/
`.elements`と`cases.json`を追加するだけでよく、`run-tests.ps1`自体は
変更不要。`cases.json`(または`.elements`ファイル)がないフィクスチャは、
テスト一式全体を失敗させるのではなく、警告付きでスキップされる —
セットアップ途中のフィクスチャが他のテストをブロックしないように
するため。

以前からコミットされていた`tests/fixtures/SampleModel/dist/index.d.ts`
(§12.5の手動検証由来)は削除した — 新しい`expected/default.d.ts`と
バイト単位で完全に同一だったため、`expected/`という規約に一本化して
置き換えた形になる。

### 15.2 ランナーの動作内容

1. 既存の`tools/dev-build.ps1`経由で`tsgen.exe`をビルドする
   (§10.2/§12.3の`deps.json`回避策を1箇所にまとめておくため)。
2. `.elements`ファイルと`cases.json`の両方を持つ各フィクスチャ
   ディレクトリについて、素の`EBuild.exe /Configuration:Release`で
   フィクスチャをビルドする。**フィクスチャについては`deps.json`の
   パッチは不要** — `tsgen.exe`とは異なり、フィクスチャのDLLは
   実行されることがなく、`tsgen`が(§10の)`MetadataLoadContext`経由で
   メタデータとして読み込むだけなので、`tsgen.exe`自体に必要な
   ランタイムアセットの穴の回避策はここには当てはまらない。
3. 各ケースについて、そのケースの`args`を付けて`tsgen generate
   --assembly <fixture.dll> --source <fixtureDir> --out
   tests/fixtures/<Fixture>/_actual/<case.name>`を実行し、`index.d.ts`
   を`expected/<...>`と比較する(比較前に両者とも改行コードを正規化
   するので、将来gitの設定やエディタに起因するCRLF/LFの食い違いが
   誤検知の失敗を生まないようにしている)。
4. `-UpdateSnapshots`スイッチ: 比較する代わりに現在の出力から
   `expected/*.d.ts`全体を再生成する — 意図的な出力変更を行った際の
   通常のスナップショットテストのワークフロー(その後は他のスナップ
   ショットテストと同様、素の`git diff`で差分が意図通りか確認する)。
5. ケースごとに`[PASS]`/`[FAIL]`の行を出力し(失敗時は`Compare-Object`
   による行単位の差分も表示)、最後にサマリー件数を出す。何か1つでも
   失敗すれば非ゼロで終了する。`_actual/`は各フィクスチャのケース
   実行後に削除される(`.gitignore`に追加済み)ので、成功・失敗に
   関わらず実行後のツリーはクリーンな状態を保つ。

### 15.3 検証

- クリーンな状態での実行: 両ケース(`default`、`union-nonnull`)とも
  成功。
- 失敗パスを確認するため、`expected/default.d.ts`をわざと壊した
  (`Active = 0` → `Active = 99`): ランナーは正しい行単位の差分
  (`expected: Active = 99,` / `actual: Active = 0,`)付きで`[FAIL]`を
  報告し、終了コード1で終了した。もう一方のケースは引き続き正しく
  `[PASS]`と報告された。スナップショットを元に戻して再実行し、
  クリーンな状態に戻ったことを確認した。
- すでに一致している出力に対して`-UpdateSnapshots`を実行しても、
  内容上の差分は生じなかった(`git status`で確認済み)、つまり何も
  実際には変わっていない場合は冪等である。

### 15.4 設計/タスクリストへの影響

- §13が「次の構造変更」の前提条件として設定していたもの(あえて
  やらなかったこと項目2、ここで完了)は満たされた。§13あえてやらな
  かったこと項目3(`NullabilityScanner`を`SimpleTokenizer`から
  作り直すこと) — 次の構造変更の候補 — は、リグレッション用の
  セーフティネットが整った状態で進められる。
- 現時点ではフィクスチャは`SampleModel`の1つのみで、enum、明示的な
  `nullable`/`not nullable`、`Unknown`ポリシーへのフォールバックを
  カバーしている。ネストした型、1つの`type`セクション配下に複数の
  型がある場合、インデクサ形式のプロパティパラメータリストは
  **カバーしていない** — §12.6ですでに指摘済みのスキャナの既知の
  限界のままである。これらのケースを演習するフィクスチャを追加する
  ことは、§13あえてやらなかったこと項目3にとってちょうどよい
  付随作業になるはずだ。スキャナの作り直しは、まさにこうした限界を
  修正するか、新たにリグレッション用に固定するかのどちらかを行う
  タイミングだからである。

---

## 16. §13あえてやらなかったこと項目3完了: NRTスキャナを本物のトークナイザへ移行 (Windows実機検証、2026-08-02)

**`NullabilityScanner.Tokenize`は`SimpleTokenizer`を使わなくなった。**
現在は`RemObjects.Elements.Code.TokenStream`を通じて本物のOxygene
トークナイザを駆動しており、§12.2/§13が指摘していた3つの問題
(OOMガード、セーフティカウンタ、O(n²)の縮小部分文字列コピー)が
すべて解消された。既存のスナップショット一式(§15)で出力に変化が
ないことを検証済みで、加えてトークナイザに敏感な挙動を固定する
新しいフィクスチャも追加した。

`CLAUDE.md`のモデル選択指針が、このスキャナを名指しでOpus向きの
コアとして挙げていたことに従い、Sonnet 5ではなくOpus 5で実施した。

### 16.1 §12.2の想定より良かったAPI

§12.2は、この作り直しが`Tokenizer`の生の逐次ステートマシン
(`Next()`、`CurrTokenID`、`Row`/`Col`)を手で回すことを意味すると
想定し、それを前提に作業規模を見積もっていた。しかし実際にはその
必要はなかった: **`RemObjects.Elements.Code.TokenStream`
(`RemObjects.Elements.Code.dll`ではなく`RemObjects.Elements.dll`に
ある)は`ViewableList<Fragment>`を継承しており、ファイル全体を1回の
呼び出しでトークナイズして**、結果を素の配列として公開する。実際に
使える形は以下の通り:

```
Languages.Register(new OxygeneLanguage);          // プロセスにつき1回
var stream := new TokenStream(FragmentType.Oxygene, false);
stream.SetText(text);                              // ここでトークナイズ、Load()不要
for i := 0 to stream.Count - 1 do
  ... stream.Items[i] ...                          // Fragment
```

- `RemObjects.Elements.Code.Fragment`はpublicな`Token: Int32`、
  `StartPos: Int32`、`Length: Int32`フィールドに加え、`GetString()`と
  `IsWhitespace`プロパティを持つ — つまり`SimpleTokenizer`の
  `TokenValue`が持っていたのと同じ情報だが、1トークンずつではなく
  入力全体に対して本物のレキサーが生成したものである。
- **`FragmentType.Oxygene = 1`** がコンストラクタに渡す列挙値。
- **登録ステップが自明でない部分。** `TokenStream`のコンストラクタは
  プロセスグローバルな`RemObjects.Elements.Languages`レジストリから
  プロバイダを解決するが、`RemObjects.Elements.Oxygene.dll`を単に
  参照するだけではレジストリは埋まらない — 先に
  `Languages.Register(new OxygeneLanguage)`を呼ばないと、構築時に
  `System.Exception: Unsupported Language: Oxygene`が投げられる。
  これは一度きりのグローバルな副作用なので、`NullabilityScanner`は
  `class var`のフラグでガードしている。

`Tokenize`より下のすべてが引き続きローカルな`ScanToken`のリストに
対して動作するため、変更は1メソッドと`uses`節のみで済んだ —
`ScanFile`、`IsTypeOpen`、`FindTypeNameBefore`、`ScanMemberDecl`は
一切手を入れていない。将来再びトークナイザを差し替えることがあれば、
このseamは維持する価値がある。

### 16.2 Oxygeneを書く前に実機で確認した挙動

EBuildの往復を繰り返しながら推測で進めるのではなく、セッションの
scratchpadの使い捨てコンソールアプリからAPIを実行して調べた(§14.1と
同じ、使い捨てでコミットしない方式):

- `SetText()`だけで`Items`/`Count`が充填される。`Load()`は不要。
- **すべてのストリームは長さ0の`T_EOF`フラグメントで終わる**ので、
  スキャナはこれをスキップする必要がある。
- `Items`は容量分の大きさを持つ配列なので、ループの上限は
  `Items.Length`ではなく`Count`である。
- 空白のフラグメントはデフォルトでは一切出力されないが、**コメントの
  フラグメントは出力され**、`IsWhitespace = true`を伴う。スキャナは
  `IsWhitespace`に加えて空白/コメント/XMLドキュメントのトークンIDでも
  明示的にフィルタしており、従来のフィルタを厳密に保っている。
- **`SimpleTokenizer.Parse`が内部で暴走し「Out of memory」で落ちていた
  (§12.2)、末尾が改行なしの`"end."`という入力が、ここでは問題なく
  トークナイズされる**(`TI_end`、`T_Dot`、`T_EOF`の3フラグメント)。
  よって`remaining.Trim() = '.'`のガードは、移設ではなく削除された。
- `&`でエスケープされた識別子(メンバー名として使う`&class`)については、
  トークナイザは`&`をすでに取り除いた状態で`T_Identifier`として報告し、
  `GetString()`、`GetOriginalString()`、`StartPos`/`Length`による生の
  スライスの3つすべてが一致する。スキャナは`GetString()`を使っており、
  これはreflection側がメンバー名として見るものと一致する — 従来の
  生スライス方式では得られなかった小さな正確性の向上である。

### 16.3 新フィクスチャ: `tests/fixtures/TokenizerEdgeCases`

§15.4の提案に従い、また既存の`SampleModel`フィクスチャが今回の
作り直しで実際に変わった部分を何一つ演習していないために追加した。
各メンバーがそれぞれ何を証明するかにちなんだ名前を持つクラスを1つ
宣言しており、ファイルは**意図的に`end.`で終わり末尾に改行がない** —
旧スキャナをクラッシュさせていた入力そのものである。

`cases.json`で2ケースを固定している: CLIデフォルトと、
`--nrt-unknown-policy non-null`。**判別力を持つのは`non-null`の方で
ある** — デフォルトポリシーでは、`Unknown`なメンバーと、漏れた
`nullable`を誤って拾ってしまったメンバーの両方が`| null`として
出力されるため、漏れがあっても気づかないまま通ってしまう。
`non-null`では`Unknown`は素のまま出力され、本物の注釈だけが`| null`を
保つので、スナップショットが両者を実際に区別できる。今後NRT関連の
フィクスチャを追加する際に覚えておく価値がある: デフォルトポリシー
だけのスナップショットは、これらのフィクスチャが存在する理由そのもの
であるバグの種類を、まさに隠してしまいうる。

ベースラインとしてコミットする前に、単に「動いたから」ではなく目視で
正しさを確認した: 行コメント、ブロックコメント、XMLドキュメント
コメント、および文字列リテラルのデフォルト値の中に現れる
`nullable`/`not nullable`は、いずれも正しく後続のメンバーに注釈を
付けず、一方で本物の注釈と複数識別子宣言は引き続き正しく解決される。
スキャナはこのファイルに対してちょうど5メンバーの注釈を報告し、
これは本物の注釈の数5と一致する。

### 16.4 これで直っていないこと

§12.6の限界は変わっていない — 今回置き換えたのは*トークンの生成
方法*であって、それを走査するヒューリスティックではない。ネストした型、
1つの`type`セクション配下の複数の型、インデクサ形式のプロパティ
パラメータリストは依然として未対応であり、`ScanFile`は今もパーサでは
なく深さカウンタによるヒューリスティックのままである。ただしこれらの
下にはスナップショットの網が張られたので、§15より前と比べれば次に
着手する対象として安全になっている。

---

## 17. RemObjectsへの2件のベンダーフォローアップを送付 (2026-08-02)

§13で「先延ばしになっている」と指摘していたコード外の2項目を、
このセッションで送付した。1通にまとめず、それぞれ独立した問い合わせ
として別々に送っている — `deps.json`のバグはエンジニアリング/EBuild
寄りの問題であり、Trial期間の質問はライセンス/営業寄りの問題であって、
RemObjects側で同じ担当者が処理するとは限らないためである。「以前の
やり取りのフォローアップ」という体裁でまとめてしまうと、汎用サポート
窓口を見る担当者にはその前の文脈が伝わらず、メリットもない。

1. **`deps.json`の実行時アセットの穴(§10.2/§12.3/§16.1)、§13項目7。**
   `support@remobjects.com`宛に、(§9のスレッドへの返信ではなく)
   新規の独立したバグ報告として送付した。内容は: 再現手順
   (`NuGetReference`がローカルにインストール済みのより新しいバージョン
   へ黙ってアップグレードされ、結果として生成される`deps.json`の
   ターゲットブロックに`"runtime"`アセットエントリが欠けること)、
   根本原因の確認(欠けているエントリを手動で追加すると直ること)、
   ローカルの`Reference`/`HintPath`でも同じ症状が再現するという発見
   (NuGet固有ではないということ)、環境情報(Elements 13.0.0.3101、
   .NET 10 SDK/ランタイム)、そして`talk.remobjects.com`を検索した
   ところ似ているが完全には一致しない古いスレッド(18830、18544、
   19464、27688)が見つかったので、重複報告か新規報告かはRemObjects側
   で判断してもらえるよう明記した点。回帰テストの種として
   `tools/dev-build.ps1`の回避策を共有してもよい旨も申し出た。本稿
   執筆時点ではまだ返信はない。

2. **§9.2のTrial期間に関する質問。** ユーザーが別途、Marcに直接
   (§9.1のスレッドを継続する形で)メールし、最初の返信にあった
   「3日間」という数字が「30日間」のtypoではないか確認を依頼した —
   ユーザーは当初から30日間のTrialを想定していた。現在の状況は
   §9.2の更新済みの記述を参照のこと。まだどちらとも確認は取れて
   いない。もし30日間だと判明すれば、課題管理表
   (`reports/2026-08-02-issue-tracker.csv`)の項目#19や、この
   ドキュメント自体が繰り返し発している「Trial版の延長利用に頼る前に
   確認すること」という警告(§4のタスクリスト、§9.3)の緊急度の
   大部分は解消される — Marcから返信があった時点で、デフォルトで
   重要度「高」の未解決項目として引き継ぎ続けるのではなく、改めて
   見直す価値がある。

**このセッション開始時点(2026-08-02、同日後半)の状況:** 作業を
続ける前に両方の受信箱を確認したが、RemObjectsからの返信はまだ
どちらの件についてもない。ユーザーによれば、§9/§17の最初の返信は
米国時間の金曜日、時間外に対応してくれたCEO本人からのものだった
とのことで、週末は追撃せずそのまま待つ方針とした。ベンダー確認待ち
の2件はコード面では動きがない状態のまま — このセッションで代わりに
何を行ったかは§18(NRTスキャナのハードニング、コードのみで完結、
ベンダー依存なし)を参照。

---

## 18. NRTスキャナのハードニング: indexerプロパティを修正、複数型/typeセクションを検証、nested typesは対象外に(Windows実機検証、2026-08-02)

`HANDOFF.md`の§12.6/§16.4で挙げていた既知の限界リスト(nested types、
1つの`type`セクション内の複数型、indexer形式のプロパティパラメータ
リスト)への対応。§15のスナップショットテストの安全網ができたことで、
この種のスキャナ変更に着手しやすくなった(§16.4自身がそう推奨して
いた)。ユーザーは他の候補(ベンダーフォローアップ、
`INullabilityProvider`チェーン/`mark-unknown`ポリシー、
`docs/DESIGN.md` §10.2の次のpost-MVP項目)よりもこちらを選んだ。

### 18.1 修正に着手する前に見つかったスコープの誤認

スキャナを触る前に、`AssemblyLoader.pas`と`DtsEmitter.pas`がnested
typesを実際どう扱っているかを確認した — スキャナ自身のコメント
(自分自身を「犯人」扱いしていた)を鵜呑みにせずに。**`AssemblyLoader.
Load`は`t.IsNested`な型を`RawAssembly`に届く前にすべて除外している**
(`AssemblyLoader.pas:27`、§13の「非public/nested/generic/未対応種別の
型をスキップ」警告の一部)。そして**`DtsEmitter`にはネストした
`interface`をinterface内に出力する仕組みがそもそも存在しない**
(namespaceレベルの入れ子(`declare namespace { ... }`)のみ)。結論:
`NullabilityScanner`のnested type属性付けだけを直しても、生成物には
一切反映されない — nested typeのメンバーはスキャナが何というキーで
属性を付けようと、そもそもIRにもEmitterにも届かないからである。
本当にnested typesに対応するには、Loader・IRのキー形式・Emitterの
3段階すべてに手を入れる必要があり、スキャナだけのパッチでは済まない。

> **訂正(§20、2026-08-02、同日後半):** Fable5レビューにより、上記の
> 段落には見落としがあったことが判明した。誤属性は単にnested type
> 自身の(見えない)データを孤児にするだけでなく、**同名の外側の
> メンバーの辞書エントリを黙って上書き**しうる — これは`.d.ts`に
> 実際に反映される出力を汚染する。§20で修正済み。この節の「生成物には
> 一切反映されない」という主張を鵜呑みにする前に§20を参照のこと。

**ユーザー判断(2026-08-02): 今回はnested typesを対象外とする。**
`NullabilityScanner.pas`のヘッダーコメントは、古い「ハードニングすべき」
という文言をそのまま引きずるのではなく、この事実(なぜ今は意味が
ないのか、単に未対応というだけでなく)を記録するよう更新した。
nested typesへの対応は、`AssemblyLoader.pas` +
`IrBuilder.pas`/`IrModel.pas`(nested typeのキー形式 —
CLRの`Type.FullName`は`Outer+Inner`を使う) +
`DtsEmitter.pas`(ネストした`interface`の出力)にまたがる、将来の
別タスクとして扱うこと。スキャナだけで少しずつ対応しようとしない。

### 18.2 indexer形式のプロパティ: 実バグを修正

`NullabilityScanner.ScanFile`の`TOK_PROPERTY`分岐は、プロパティ名の
直後のトークンが`TOK_COLON`であることを前提にしていた
(`property Name: Type ...`)。indexer宣言
(`property Item[aIndex: Int32]: not nullable String read ... write ...;`)
では、そこに`TOK_OPENBLOCK`(`[`)が来るため、分岐全体の条件が
成立せず、indexerプロパティは元のソースの内容にかかわらず常に
`Unknown`扱いのまま、無言で検出漏れとなっていた。`AssemblyLoader`は
`t.GetProperties(...)`経由でindexerプロパティ自体は問題なく読み込んで
いる(reflectionの`PropertyInfo.Name`は`"Item"`となり、indexパラメータ
は無視される)ので、これは純粋にスキャナ側の穴であり、Loader側の
問題ではなかった。

修正: プロパティ名の直後のトークンが`TOK_OPENBLOCK`だった場合、
ブラケットの深さを追跡しながら対応する`TOK_CLOSEBLOCK`まで読み飛ばし、
そこから改めて`TOK_COLON`を探すようにした — メソッドのパラメータ
リストを除外するために既にある`parenDepth`の丸括弧スキップと同じ形を、
`(...)`ではなく`[...]`向けに適用しただけである。`Token.T_OpenBlock`/
`Token.T_CloseBlock`が`[`/`]`に対応する正しい定数であることは、
使い捨てのPowerShellプローブ(3つの`RemObjects.Elements*.dll`を
`Add-Type -Path`で読み込み、`Languages.Register(new OxygeneLanguage)`
した上で`TokenStream.SetText`を呼ぶ、§16.1と同じAPIの使い方)で
indexerのサンプルを実際にトークナイズして確認した — 推測に頼らな
かった。命名が非自明だったため(`[`/`]`に対応するのは
`T_OpenBlock`/`T_CloseBlock`であり、それとは別に無関係な
`T_CloseBracket`というフィールドも存在するので、「Bracket」で
推測していたら誤った定数を選んでいたはずである)。

### 18.3 1つの`type`セクション内の複数型: 既に正しく動作していることを確認、修正不要

`ScanFile`を注意深く読んだところ、`currentTypeName`/`typeDepth`は、
`depth = typeDepth`となる任意の型の`end`で無条件にリセットされており、
1つの`type`セクションにいくつ型宣言が並んでいようと、リセット処理が
「最初の型だけ」に限定されている箇所はどこにもなかった。コード
読解だけを鵜呑みにせず、後述(§18.4)の新規フィクスチャで実機
確認も行った: 1つの`type`セクション内で隣り合う2つのクラスに、
同名だが正反対のnullabilityを持つメンバーを宣言し、もし何らかの
漏れがあれば1つの誤った辞書エントリに衝突していたはずというケース。
ここではコード変更は不要だった — 単に、これまでフィクスチャで
検証されたことがなかっただけで、実際にはもう正しく動いていた。

### 18.4 新規フィクスチャ: `tests/fixtures/MultiTypeAndIndexer`

1つの`type`セクションの下にある隣り合う2つのクラス(`Alpha`、
`Beta`)がそれぞれ`Name`という名前のプロパティを正反対の
nullabilityで宣言する(`Alpha.Name`はnullable、`Beta.Name`は
not nullable)— §18.3の判別力を持つケース。`Beta`はさらにindexer
プロパティ(`Item[aIndex: Int32]`、not nullable、自動実装の
`read write`ではなく明示的な`GetItem`/`SetItem`メソッドで実装 —
indexedプロパティにはコンパイラが自動生成できる単一のバッキング
フィールドが存在しないため)と、無注釈の`Count: Int32`(本物の
`Unknown`メンバーを混在させるため)も宣言する。`cases.json`には
2ケースをロック(CLIデフォルトと`--nrt-unknown-policy non-null`) —
`CLAUDE.md`にある、NRT系フィクスチャには必ずnon-nullケースも
含めるという既定方針に従った。

ベースラインとしてコミットする前に実機で確認した(`-UpdateSnapshots`
を信用するだけでなく): ビルドしたフィクスチャDLLに対して直接
`tsgen`を実行し、出力を確認 — `Alpha.Name`と`Beta.Name`は互いに
漏れることなく正しいnullabilityで出力され、`Beta.Item`(indexer)は
両方のポリシーで`not nullable`(`| null`なし)として返ってきた。
これだけで既に「not nullableとして検出された」ことと「一切検出されず
Unknownにフォールバックした」こと(Unknownならデフォルトポリシーで
`| null`が付く)を区別できている — non-nullケースはさらに
`Beta.Item`と(本物の`Unknown`である)`Beta.Count`を区別しており、
`CLAUDE.md`が`TokenizerEdgeCases`について既に記載している
検出漏れ検知のロジックと一致する。`SampleModel`と
`TokenizerEdgeCases`のスナップショットはスキャナ変更後もバイト単位で
同一のままだった(両方とも`git diff`が空)— `TOK_PROPERTY`分岐の
書き換えによる退行がないことを確認した。

### 18.5 検証

- `tools/dev-build.ps1` — クリーンビルド、新規警告なし。
- `tools/run-tests.ps1 -UpdateSnapshots`、続けて`tools/run-tests.ps1`
  (通常モード): 3つのフィクスチャ全体で6/6ケースがパス
  (`MultiTypeAndIndexer` x2、`SampleModel` x2、
  `TokenizerEdgeCases` x2)。
- `SampleModel`/`TokenizerEdgeCases`の期待値スナップショットに対する
  `git diff`: 空(退行なし)。

### 18.6 今回直していないこと

- nested typesはエンドツーエンドで未対応のまま。今回、単なる
  スキャナだけの穴ではなく、3段階(Loader/IR/Emitter)にまたがる
  ギャップだと分かった — §18.1参照。ユーザーの明示的な判断により、
  今回は着手していない。
- `ScanFile`は今も深さカウンタ方式のヒューリスティックであり、
  パーサーではない。今回はそれが認識できるメンバー宣言の「形」
  (indexer)を広げただけで、根底にあるネスト/型追跡モデル自体は
  変えていない。

---

## 19. Diagnosticsコンポーネントを追加: `DtsEmitter.Emit`/`AssemblyLoader.Load`を再び純粋関数に(Windows実機検証、2026-08-02)

課題管理表(`reports/2026-08-02-issue-tracker.csv`)の項目#22を解決。
§13のレビュー後修正パスで指摘され、その場では直さず「将来
Diagnosticsコンポーネントを実装するとき」に先送りしていたもの。
ユーザーが次にこれを選び、最小限のstderrだけのパッチではなく、
本格的なDiagnosticsコンポーネントの導入を希望した — CSVの当該行の
文言自体(「将来Diagnosticsコンポーネント実装時に」)がどちらの
選択肢も開いたままにしていたので、決め打ちせず着手前にユーザーに
確認を取った。

### 19.1 実際に何が非純粋だったか、なぜ問題だったか

`AssemblyLoader.Load`(Stage 1)と`DtsEmitter.Emit`(Stage 4)は
どちらも警告のために`writeLn`を直接呼んでいた(スキップした型数、
未マッピングCLR型のフォールバック)— `docs/DESIGN.md`のパイプライン
設計は各ステージを単体でテスト・合成できる純粋なデータ変換として
扱う前提だったにもかかわらず。純粋性の問題そのものに加え、
未マッピング型の警告には実際のノイズ問題もあった: *メンバーごと*に
1回出力していたため、1つのカスタムPOCO型が多数のプロパティで使われる
(Inertia Page Propsのユースケース(§6)では現実的な形)と、根本原因を
1回だけ表示するのではなく、ほぼ同じ行がコンソールを埋め尽くして
いた。

### 19.2 追加したもの

新規ファイル `src/Tsgen/Diagnostics/Diagnostics.pas`
(`Tsgen.Diagnostics`名前空間、`Tsgen.elements`の`Compile`リストの
先頭に追加 — `AssemblyLoader`/`DtsEmitter`/`Program`が全てこれに
依存するようになったため): `DiagnosticSeverity`列挙型(今のところ
`Warning`のみ)、`Diagnostic`クラス(`Severity` + `Message`)、
単一の`AddWarning(aMessage)`メソッドと`Items`プロパティを持つ
`DiagnosticList`収集クラス。

- `AssemblyLoader.Load`は`aDiagnostics: DiagnosticList`引数を
  新たに受け取るようになった。スキップした型数の警告は`writeLn`では
  なく`aDiagnostics.AddWarning(...)`経由になった。
- `DtsEmitter.Emit`も同じ引数を受け取る。未マッピング型の警告は
  まず「集約」する形に再構成した: `EmitType`が新たに2つの引数を
  受け取る — CLR型名をキーとする`Dictionary<String, List<String>>`
  (値はそれを使っている`"Type.Member"`の一覧)と、初出順を記録する
  `List<String>`(`Emit`内に既にある`byNamespace`/`order`ペアと
  同じ「Dictionaryのイテレーション順に依存しない」という理由に基づく
  もので、新規に持ち込んだのではなく既存の流儀を踏襲)。全ての型の
  出力が終わった後、`Emit`が`unmappedOrder`を1回だけ走査し、
  未マッピング型ごとに1つの診断を追加する。例:
  `"no type mapping for DiagProbe.Widget, emitting \"unknown\"
  (3 member(s), e.g. Holder.A)"`。
- `Program.pas`(CLIのエントリーポイントであり、自身の進捗行を除いて
  コンソールに触れることが許される唯一の場所)が`DiagnosticList`を
  1つ生成し、`AssemblyLoader.Load`と`DtsEmitter.Emit`の両方に
  引き回す。既存の「`--source`未指定」警告もこれ経由にした
  (これまでは独自の`writeLn`直接呼び出しだったが、他の2つと
  統一)。集約された診断は、すべての処理が終わった最後に(「Wrote
  ...」行の後で)まとめて1回、`Console.Error.WriteLine('Warning: ' +
  d.Message)`経由で出力される — stdoutではなく**stderr**へ。進捗の
  ナレーションと警告を分離している。`Console.Error`を使うため
  `Program.pas`の`uses`節に`System`の追加が必要だった。

### 19.3 検証

- `tools/dev-build.ps1`: クリーンビルド、新規警告なし。
- `tools/run-tests.ps1`: 3フィクスチャ全体で6/6ケースが引き続き
  パス。`.d.ts`の出力はバイト単位で変更前と同一(diagnosticsは
  生成ファイルの内容には触れず、警告の出力先・出力方法のみ変更)。
- 使い捨てのscratchpadフィクスチャ(リポジトリにはコミットしない —
  §14.1/§16.2/§18.2と同じ使い捨てプローブの流儀)による重複排除の
  実機確認: 3つのプロパティ(`Holder.A`/`B`/`C`)のプロパティ型として
  使われる未マッピングのカスタム型`Widget`。この変更前なら実行中に
  ほぼ同一の`writeLn`行が3回出力されていたはずのところ、新しい
  ビルドではstderrにちょうど**1行**だけ出力されることを確認した
  (目視だけでなく`2>stderr.txt`のリダイレクトで検証):
  `Warning: no type mapping for DiagProbe.Widget, emitting "unknown"
  (3 member(s), e.g. Holder.A)`。

### 19.4 設計/タスクリストへの影響

- 課題管理表の項目#22は解決 — `AssemblyLoader.Load`と
  `DtsEmitter.Emit`は再び純粋関数になった(データと
  `DiagnosticList`を結果として返すのみで、直接のI/Oはない)。
  `docs/DESIGN.md`のパイプラインステージ設計の意図に合致する。
- `DiagnosticSeverity`は今のところ`Warning`のみ。将来
  `Error`/`Info`が必要になったステージが出てきたら、`writeLn`に
  逆戻りするのではなく、この列挙型と`DiagnosticList`を拡張する
  のが正しい継ぎ目である。
- これは`docs/DESIGN.md` §6がpost-MVPのpluginチェーン向けに
  スケッチしている`IEmitterExtension`/diagnostics寄りの拡張点にも
  わずかに近づくものだが、pluginの仕組み自体は今回追加していない —
  純粋に、既存の2ステージが問題をどう報告するかという内部的な
  リファクタリングである。

---

## 20. §18/§19(コミット`b9627df`/`ce1be2d`)のFable5レビューとその対応(Windows実機検証、2026-08-02)

ユーザーが、§18/§19の元になった2つのコミットについて、独立した
Fable5レビューを2つの明示的な観点で依頼した: 対応内容の内部整合性、
そして今回の作業が他の場所に新たな不整合を持ち込んでいないか。
レビューはバックグラウンドの`general-purpose`エージェント
(`model: fable`)として、独立したworktree内で、修正は行わずレビュー
のみ行う指示のもとで実行した。手法: `CLAUDE.md`、`HANDOFF.md`/
`HANDOFF_jp.md`の§19までの全文、実際のdiff(両コミットへの
`git show`)と現在のファイル内容、`docs/DESIGN.md`、課題管理表CSVを
読み込み、記録されている内容を鵜呑みにせず複数の主張を手でトレース
して検証した。ビルド/テスト実行は行わなかった(Trialライセンスの
使用量上限への慎重さ、`CLAUDE.md`の「ライセンス制約」節)— 以下の
指摘事項はすべて静的なトレースで検証され、指摘1についてはこの
セッションでさらに実機確認も行った(§20.3)。

### 20.1 レビュー結果

**観点1(内容の内部整合性): おおむねクリーン。** 日英のHANDOFF本文、
`CLAUDE.md`、CSV、実際のコードは、確認した実質的な論点すべてで
一致していた(トークン定数、`GetItem`/`SetItem`の理由付け、ケース数、
dedupメッセージの書式、`IsTypeOpen`に関する主張など)— 修正が必要
だったのは2件の軽微な言い回しの誤り(§20.4)以外になかったため、
詳細はここには再掲しない。

**観点2(新たな不整合): 3件**、深刻な順に:

1. **§18.1の「スキャナだけ直しても出力は変わらない」という根拠に
   実際には穴があった。** nested type自身のデータがEmitterに届かない
   (LoaderがIsNestedを除外し、Emitterにネストしたinterface出力機構が
   ない)というのは事実だが、誤属性はその見えないデータを孤児に
   するだけではない。`NullabilityScanner`の`TOK_PROPERTY`分岐には
   フィールド分岐が既に持っていた`(depth = typeDepth)`ガードが
   なかったため、nested type内の注釈付きプロパティは依然として
   *外側*の型に属性付けされ(`currentTypeName`はnested typeの本体内
   でも外側の型名のまま)、`ScanMemberDecl`の無条件の
   `aResult[key] := kind`書き込みにより、外側・nestedのどちらの
   宣言をスキャナが**最後**に通過するかで共有辞書キーの勝者が決まる。
   つまりnested typeの注釈が、`.d.ts`に実際反映される外側の同名
   メンバーのnullabilityを黙って上書きしうる。同じ誇張された主張が
   5箇所にあった: `HANDOFF.md`/`HANDOFF_jp.md` §18.1、
   `NullabilityScanner.pas`のヘッダーコメント、`CLAUDE.md`、CSV行31。
   nested typesのフルサポートを今回対象外にするという*判断*自体は
   問題なかったが、「スキャナだけの穴なら無害」という*根拠*の方が
   誤っていた。修正済み、§20.3参照。
2. **`docs/DESIGN.md` §4(および`DESIGN_jp.md`)が、§18.2で修正した
   はずのindexer形式のプロパティを依然「現在の制限」として記載して
   いた**うえ、参照先も古い節(§12.6/§13、正しくは§18)のままで、
   `SimpleTokenizer`への言及も古かった(実際は§16の時点で既に
   置き換え済み — この2コミットが持ち込んだ問題ではなく、同じ読み
   直しで見つかっただけ)。`b9627df`は`CLAUDE.md`/`HANDOFF.md`は
   更新したが、正典であるdesignドキュメントを更新し漏れていた。
   修正済み、§20.2参照。
3. **課題管理表CSVのフェーズ番号列が、途中から意味を変えてしまって
   いた。** 行1-30はHANDOFF節番号とは*一致しない*、同一セッション内の
   独自の連番を使っていた(例: フェーズ8=§14、フェーズ10=§16)。
   行31-33(`b9627df`)と行22の更新後解決フェーズ(`ce1be2d`)は
   代わりにHANDOFF節番号(18、19)をそのまま使っており、フェーズ10
   から18へ、間に何もないまま飛んでいた。修正済み、§20.2参照。

軽微(観点2)として指摘されたもう1件: §18.1の`IsNested`フィルタへの
`AssemblyLoader.pas:26`という引用は、§18執筆当時は正確だったが、
`ce1be2d`が`uses`節に`Tsgen.Diagnostics`の1行を追加したことで
フィルタが27行目にずれ、以後1行分ずれたままになっていた。これを
引用している`HANDOFF.md`と`HANDOFF_jp.md`(引用箇所はこの2つのみ)を
本節の編集の一部として修正した — §20の他の部分が反映された後の
フォローアップとして対応(「軽微」として一覧には挙がっていたが実際
にはまだ対応していなかったことをユーザーが指摘)。

観点1の軽微な言い回しの誤り2件(情報源間の不整合ではなく、単なる
不正確な表現)は§20.4に記載する。

### 20.2 修正: 指摘2と3(ドキュメントとCSV)

- `docs/DESIGN.md` §4 / `docs/DESIGN_jp.md` §4: `OxygeneSourceScanProvider`
  の段落を書き直し、indexerプロパティと複数型セクションが対応済みで
  ある旨(§18.2/§18.3)、現在は`SimpleTokenizer`ではなく
  `TokenStream`ベースの実装である旨を記載し、nested typesの制限を
  単なる「既知の制限」ではなくLoader+Emitterにまたがるギャップとして
  再定義し、参照先を§12.6/§18に付け替えた。
- `reports/2026-08-02-issue-tracker.csv`: 行31-33のフェーズ番号を18
  から**11**に(既存の連番方式を継続 — 11-17はまだ何にも使われて
  いなかった)、行22の解決フェーズを19から**12**に、それぞれ同じ
  連番に合わせてリナンバリングした(11=§18のNRTハードニング、
  12=§19のDiagnosticsコンポーネント)。今回のレビュー自体の指摘と
  対応は、フェーズ13(発見、「Fable5レビュー3回目」)とフェーズ14
  (対応、「修正対応2」)として記録した — 行34-38。

### 20.3 修正: 指摘1(実際のスキャナのバグ)

`NullabilityScanner.ScanFile`の`TOK_PROPERTY`分岐に、フィールド分岐が
既に持っていたのと同じ`(depth = typeDepth)`ガードを追加した
(`src/Tsgen/Nrt/NullabilityScanner.pas`)。`depth`が`typeDepth`を
超えた状態(nested typeの本体内、または理屈上は他の何らかのネストした
ブロック内)で見つかった`property`トークンは、これで
`currentTypeName`(外側の型)に属性付けされるのではなく、正しく
**無視**されるようになった。

**新規回帰フィクスチャ: `tests/fixtures/NestedTypeCollision`。**
`Outer`が`property Name: nullable String`を直接宣言し、その本体内に
nested typeとして`type Inner = public class ... property Name: not
nullable String ... end;`を宣言する — 同名メンバー、正反対の
nullability。`Outer`自身の宣言をnested typeより*前*に配置している
(順序が重要: `ScanMemberDecl`は無条件に上書きするため、最後に
スキャンされた宣言が最終的な辞書の値を決める。この順序にすることで
汚染が偶然マスクされず、実際に観測可能になる)。

「テストが通った」だけで済ませず、両方向を実機で確認してから
スナップショットのベースラインとして信頼した:
- `git stash`で修正を一時的に戻し、リビルドして`tsgen`を直接実行:
  `Outer.Name`が素の`string`として返ってきた — `Inner`の
  `not nullable`注釈によって`| null`が**誤って**失われていた。
  フィクスチャがバグを再現することを確認。
- `git stash pop`で修正を戻し、リビルドして`tsgen`を再実行:
  `Outer.Name`は`--nrt-unknown-policy`のどちらの設定でも正しく
  `string | null`として返ってきた(Unknownポリシーのフォールバックの
  偶然の一致ではなく、明示的な注釈が生き残っていることの証明)。
  この手動確認の後で初めて`tools/run-tests.ps1 -UpdateSnapshots`で
  `expected/*.d.ts`スナップショットとしてロックした。

フルスイート: `tools/run-tests.ps1` — 4つのフィクスチャ全体
(`MultiTypeAndIndexer`、`NestedTypeCollision`、`SampleModel`、
`TokenizerEdgeCases`)で**8/8ケースがパス**。既存3フィクスチャの
スナップショットへの`git diff`は空(ガード追加による退行なし)。

**誇張された主張があった5箇所すべてで根拠を訂正した**:
`NullabilityScanner.pas`のヘッダーコメントは、今やガードについて
説明し、主張を「nested type由来のメンバーは出力に一切影響しない」
から「nested type由来のメンバーは、何かを汚染することなく無視
される」へと狭めた(後者の主張が成り立つのはLoader/Emitter経由の話
だけで、スキャナ自身の辞書については元々成り立っていなかった)。
`HANDOFF.md`/`HANDOFF_jp.md` §18.1には、その場で黙って書き換える
のではなく、ここを指す訂正の引用ブロックを追加した(当時実際に
そう信じられていたことをそのまま残す — §14/§9.4の「解決済み」
パターンがこの前例にあたる)。`CLAUDE.md`のnested types段落とCSV
行31(新規行34経由、§20.2)は、日付付きのログエントリではなく
現在の状態を表す生きた記述なので直接更新した。

### 20.4 観点1の軽微な言い回しの誤り2件、こちらも修正

- `CLAUDE.md`のDiagnostics段落は、未マッピング型のdedupを
  `Program.pas`が行っているかのように読める書き方だった。実際に
  CLR型名で集約しているのは`DtsEmitter.Emit`であり、`Program.pas`は
  既に重複排除された結果を出力するだけである。文言を修正した。
- CSV行32の日本語の説明で「ブレース深度」(波かっこ`{}`を指す語)と
  書いていたが、コードが実際に追跡しているのはブラケット(`[]`)の
  深さであり、「ブラケット」が正しい。また「property直後がColon」を
  「プロパティ名直後」(`property`キーワード自体の直後ではなく、
  プロパティ*名*の直後)であることを明確にするよう引き締めた —
  HANDOFF両言語版が既に正しく述べていた内容と一致させた。行32を
  直接修正した(新規行としては起こしていない — §20.2/§20.3の各行が
  「何が間違っていて何を直したか」の記録を必要としたのとは違い、
  これは既に正確な内容に対する言い回しだけの訂正のため)。

### 20.5 これによって変わらないもの

- nested typesは依然として*本当の*サポート対象外のまま(nested
  typeの自身のメンバーが独自の出力を持つこと)。§20.3が直したのは
  スキャナの辞書汚染がOUTERメンバーに及ぼす副作用だけで、
  `AssemblyLoader`が`IsNested`な型を除外するのをやめさせたり、
  `DtsEmitter`にネストした`interface`の出力経路を与えたりは
  していない。それは§18.1で述べた通り、依然として3段階にまたがる
  タスクのままである。
- `DiagnosticList`自体の設計や§19の内容は、§20.4の`CLAUDE.md`の
  言い回し訂正を除いて変更していない — レビューは§19の実質的な
  内容は健全だと判断した。

---

## 21. `INullabilityProvider`チェーン + `mark-unknown`ポリシーの実装(Windows実機検証、2026-08-02)

課題管理表の項目#9・#10を解決 — Fable5レビュー1回目からの残り2件の
先送り項目(`HANDOFF.md` §13の未着手リスト項目4)。プロバイダチェーン
の抽象化には配線(seam)自体が一切なく(`IrBuilder.Build`内の直接の
辞書検索のまま)、`--nrt-unknown-policy`の3つ目の値はそれに
ブロックされていた。ユーザーが残っていた候補の中からこれを選んだ。

### 21.1 コードを書く前に決めたスコープ

事前に(推測せず)ユーザーと確認した設計上の分岐点が2つ:

1. **Provider 3(`ValueTypeDefaultProvider`、値型は既定でnon-nullable)
   をProvider 1と併せて含めるかどうか。** これは既存のスナップショット
   出力を実際に変えてしまう(値型で無注釈のメンバーがそもそも
   `Unknown`でなくなり、`--nrt-unknown-policy`が触れなくなる)。
   **確認結果: 含める** — これは`docs/DESIGN.md` §4.2の同じ
   プロバイダチェーン設計の一部であり、スコープの逸脱ではない。
   挙動の変化自体が正しさの向上でもある(C#/.NETの実際のデフォルト
   —値型は明示的に`Nullable<T>`/`T?`にしない限りnon-nullable—
   と一致する)。
2. **`mark-unknown`をTypeScriptでどう表現するか。** 型システムには
   「non-nullable確定」と区別して「nullability未確定」を表現する
   手段がない。**確認結果: `non-null`と同じ素の型に、末尾の
   `// nrt: unknown`という行コメントを付与する** — 架空の型や、
   まだ未実装のXML doc→JSDoc変換機能(`docs/DESIGN.md` §10.2項目3)
   と衝突しかねないJSDocタグを発明することなく、目視・grepの両方で
   区別できるようにした。

Provider 2(`RoslynStyleAttributeProvider`、reflectionの属性ベース)
はあえて実装していない — `docs/DESIGN.md` §4.2の通り依然として
本当に未実装のままであり、チェーンには実在する2つのプロバイダ
だけが入っており、3つ目のためのスタブは置いていない。

### 21.2 追加したもの

**新規ファイル`src/Tsgen/Nrt/NullabilityProviders.pas`**
(`Tsgen.elements`の`Compile`リストで`NullabilityScanner.pas`の
直後に追加 — `NullabilityKind`が必要で、かつこれを使う
`IrBuilder.pas`より前に来る必要があるため): `INullabilityProvider`
(メソッド1つ、
`TryGetNullability(aTypeFullName, aMemberName, aClrTypeName):
NullabilityKind`)、`OxygeneSourceScanProvider`(既存のスキャン結果
辞書をラップ — Provider 1)、`ValueTypeDefaultProvider`(Provider 3 —
既知の値型CLR名のリスト。`Tsgen.Ir.TypeMapper`のリストとは
あえて別リストとして持たせている — `Tsgen.Ir`は既に`Tsgen.Nrt`に
一方向で依存しているため、逆方向に呼び出すと循環参照になってしまう
ためで、両リストは同期を保つ必要がある旨をコメントで明記した)、
そして`NullabilityProviderChain.Resolve`(リスト順に各プロバイダを
試し、最初にUnknown以外を返した時点で止める — `docs/DESIGN.md`
§2.2/§2.3の型マッピングチェーンと同じ「最初に一致したものが勝つ」
という考え方)。

`docs/DESIGN.md` §4.2の`IrMemberRef`/`AnalysisContext`という擬似
コードから、このツールが実際に持っている具体的な文字列(型の
フルネーム、メンバー名、生のCLR型名)に合わせて改変した —
`IrMemberRef`/`AnalysisContext`はコードベースの他のどこにも存在
しないため、あの抽象的なスケッチは*パターン*を示すためのもので
あり、逐語的に再現すべきAPIではないと判断した。

**`IrBuilder.pas`**: `Build`が
`[OxygeneSourceScanProvider(aNullability), ValueTypeDefaultProvider]`
を一度だけ構築し、各メンバーの`Nullability`を直接の辞書検索の
代わりに`NullabilityProviderChain.Resolve`経由で解決するように
なった。`IrBuilder.Build`自身のシグネチャは変更していない(引き続き
生のスキャン辞書を受け取る)— チェーンの存在は内部実装の詳細であり、
`Program.pas`からは見えない。`NrtUnknownPolicy`に3つ目の値
`MarkUnknown`を追加した。

**`DtsEmitter.pas`**: `ResolveNullable`を2つのメソッドに分割した —
`ResolveNullableSuffix`(ロジックは不変、リネームのみ)が`| null`を
付けるかどうかを決め、新規の`ShouldMarkUnknown`が`// nrt: unknown`
コメントを付けるかどうかを決める(メンバーが本当に`Unknown`で、
*かつ*ポリシーが`MarkUnknown`のときのみtrue — 明示的に注釈された
メンバーには決してコメントが付かない。ポリシーは本物の`Unknown`
にしか触れないという既存のルールと一致する)。

**`Program.pas`**: `--nrt-unknown-policy mark-unknown`を既存の
`nullable`/`non-null`と並んで認識するようにした。usage文言も更新。

### 21.3 Provider 3追加によるフィクスチャ/スナップショットへの影響

`-UpdateSnapshots`を信用する前に手動で確認する、§18/§20と同じ
規律で: まず`SampleModel`に対して`tsgen`を直接実行した。
`Age`/`IsAdmin`(`Int32`/`Boolean`、無注釈)が、デフォルトポリシー下で
`number | null`/`boolean | null`から素の`number`/`boolean`に変わった
ことを確認 — Provider 3によって確定的にnon-nullableと解決され、
そもそも`Unknown`でなくなったため、ポリシーが作用する対象が
なくなった。

**これによって見つかった副作用**: `SampleModel`の`union-nonnull`
ケースは`--nrt-unknown-policy non-null`を検証するために存在して
いたが、その唯一の`Unknown`メンバー2つ(`Age`、`IsAdmin`)はどちらも
値型だった — Provider 3導入後、`SampleModel`には本物の`Unknown`
メンバーが**一つもなくなり**、そのケースが黙ってポリシー関連の
検証を何も行わなくなっていた。`property Notes: String read write;`
(あえて無注釈、あえて参照型にしてProvider 3が解決できないように
した)を追加し、ポリシーが判別できる本物の`Unknown`メンバーを
復活させた。`SampleModel`と`TokenizerEdgeCases`の両方に`mark-unknown`
ケースを追加した(`TokenizerEdgeCases`はコメント/文字列リテラル
漏れテスト由来の本物の`Unknown`な`String`メンバーを複数既に
持っていたため、ソース側の変更は不要だった)。

「テストが通った」だけで済ませない完全な差分レビュー:
`MultiTypeAndIndexer`の`Beta.Count: Int32`(無注釈)は`default`
ケースで`number | null`から`number`に変わった(`SampleModel`と
同じ理由)。その`non-null`ケースは元々`number`だったため差分なし。
`NestedTypeCollision`と`TokenizerEdgeCases`の`default`/`non-null`
ケースは**差分なし** — `NestedTypeCollision`唯一のメンバーは
明示的に`nullable`(Provider 3の影響を受けない)であり、
`TokenizerEdgeCases`にはそもそも値型のメンバーが一つもない。

### 21.4 検証

- `tools/dev-build.ps1`: クリーンビルド。
- `-UpdateSnapshots`を実行する前に、`SampleModel`(`Notes: string;
  // nrt: unknown`、`Age`/`IsAdmin`/明示的に注釈されたメンバーは
  すべて無影響)と`TokenizerEdgeCases`(本物の`Unknown`な4メンバーに
  正しくコメントが付き、`WithKeywordDefault`/`ExplicitlyNotNullable`
  等には正しく付かない)の両方で`mark-unknown`の出力を手動確認した。
- `tools/run-tests.ps1 -UpdateSnapshots`、続けて通常モードの
  `tools/run-tests.ps1`: 4つのフィクスチャ全体で**10/10ケースが
  パス**(新規`mark-unknown`ケース2つを追加、これまでの8から10に)。
- すべてのスナップショット差分を手動でレビューし(§21.3)、事前の
  手動確認の予測と一致することを確認した — 手動での`tsgen`実行と
  スナップショットスイートの間に驚きはなかった。

### 21.5 これによって変わらないもの

- Provider 2(C#/VB製の依存アセンブリ向け、reflectionの属性ベース
  のNRT)は未実装のまま — `docs/DESIGN.md` §4.2の通り、引き続き
  post-MVPとして正しい状態。
- `MetadataFxProvider`の空きスロット(`docs/DESIGN.md` §4.1)は
  依然としてただのスロットのまま — §14で既にNRTに関してはこの
  手がかりが行き止まりだと結論づけているため、このツールにとって
  ここに実装すべきものは何もない。
- `AssemblyLoader.pas`、`NullabilityScanner.pas`、Diagnosticsコン
  ポーネントへの変更はなし — 今回は完全にStage 2/4(IRビルダー/
  Emitter)側の変更と、それに付随する新規ユニット1つだけである。

---

## 22. §3.5技術スパイク: エントリーポイント駆動の`Inertia.Render`検出は実現可能か?(Windows実機検証 + Web調査、2026-08-02)

`docs/DESIGN.md` §11項目8が、Inertia.jsピボット(§6)に着手するセッション
向けに挙げていた「最優先の技術検証項目」を解決。ユーザーは§6を、
このセッション冒頭で議論した順序(generics/循環参照検出への投資の
前に、その投資がどんな形になるべきかを決めるエントリーポイント検出の
不確定要素をまず解消する)通り、まさにこのスパイクから開始することを
選んだ。手法: InertiaNetCoreの実際のAPI(想定・汎用的な形ではなく)
をWeb調査で確認した上で、DESIGN.mdの元の記述が未検証のままにしていた
点をセッションのscratchpad上のOxygene実機プローブ(§14.1/§16.2/
§18.2/§21と同じ使い捨てプローブの流儀)で検証した。**結論: 実現
可能 — ただしIL解析でもRoslyn風のフルASTでもない、ソースレベルの
トークンスキャンによって(`docs/DESIGN.md` §3.5が元々挙げていた
2つの選択肢のどちらでもない)。ただし、これまで知られていなかった
Oxygene固有の言語仕様上の落とし穴が1つ見つかり、スキャナが処理すべき
対象を変えている。**

### 22.1 InertiaNetCoreの実際の`Render` API(Web調査)

`docs/DESIGN.md` §3.5の「`data`引数の静的型を解決する」という
枠組みは、C#の汎用的な`Inertia.Render(name, new { ... })`のような
形を想定していた。実際のAPI(`mergehez/InertiaNetCore` —
`HANDOFF.md` §6.4で既に採用を決めているアダプタ)はもっと狭い:

```csharp
public static Response Render(string component);
public static Response Render(string component, InertiaProps? props);
public static Response Render(string component, Dictionary<string, object?>? props);
// InertiaProps : Dictionary<string, object?>
```

**任意のPOCOやanonymous objectを直接受け取るオーバーロードは存在
しない。** このプロジェクト自身のREADMEにある実際の使用例は全て、
`InertiaProps`/`Dictionary`をC#のオブジェクト初期化子構文で構築して
いる: `new InertiaProps { ["Name"] = "InertiaNetCore", ["Version"] =
... }`。遅延読み込み用のprops値を`Inertia.Defer(async () => ...)`/
`Inertia.Merge(async () => ...)`でラップするケースも含む。

**帰結: `data`引数の*静的*型は常に`InertiaProps`/`Dictionary<string,
object?>`であり、単体では何の情報にもならない。** §3.5が本来
解くべき問題は「1つの式の型を解決すること」ではなく、「propsの
辞書に追加される文字列キー1つ1つについて、割り当てられる値の式の
型を決定すること」である。これは設計書が元々提示していたものとは
狭さも形も異なる問題であり、このスパイクの残りが実際に検証したのは
こちらである。

### 22.2 Oxygeneのanonymous class: 存在は確認済み、reflectionで見えることも確認済み、ただしここでインラインには使えないことも確認済み

Oxygeneにはanonymous class/record/interfaceリテラルがある:
`new class(Name := 'Peter', Age := 35)`。実機確認(使い捨てプローブ)
の結果: コンパイルは通り、`docs/DESIGN.md` §3.5がC#のanonymous
typeについて挙げていた「ILレベルで不透明」という懸念とは異なり、
reflectionからは本物の、完全にreflectableな合成ジェネリック型が
見える: `<>f__AnonymousType0\`2[System.String,System.Int32]`、
プロパティアクセスも正常に動作した(`a1.Name`は正しく`'Peter'`を
返した)。C#の`<>f__AnonymousType0`と同じく合成された名前は不安定
だが、*形状*(プロパティ名+型)は、その特定のインスタンスの`Type`さえ
手に入れられれば、reflectionから本当に取得可能である — 実務上の
ボトルネックは「*このソース位置*のanonymousリテラル」と「*その*
reflectされた型」をどう対応付けるかであって、anonymous typeが
一般にreflectableかどうかではない。§22.1の発見により`InertiaProps`
の値はキーごとに1つずつ追加されるので、インラインの`new class(...)`
が1つのpropsの*値*として現れることは依然としてありうる(例:
`props['Meta'] := new class(Total := 10, Page := 1);`)— これは
他の値の式と同じ扱いになる(§22.4)。reflectionではなくソース
レベルでの解析による。

### 22.3 新規発見: Oxygeneにはオブジェクト/コレクション初期化子構文が存在せず、それっぽく見える構文は黙って無効化される

DESIGN.mdにもHANDOFF.mdにもこれまで指摘がなかった点。
InertiaNetCore自身のC#のREADME例を模して、`Dictionary<String,
Object>`を埋めるための候補構文を3つ、実機で検証した:

1. `new Dictionary<String, Object> { ['Name'] := 'Foo', ['Age'] := 30 }`
   — **コンパイルは正常に通るが、実際には何もしない。** `{ }`は
   Oxygeneのブロックコメントの区切り文字(NRTスキャナ作業で既知 —
   `HANDOFF.md` §16.3のコメント漏れテストケース参照)であり、
   `{ ['Name'] := 'Foo', ['Age'] := 30 }`ブロック全体が1つの
   コメントフラグメントとしてトークナイズされ、破棄される。残るのは
   `new Dictionary<String, Object>` — 空の辞書 — という実際の式のみ。
   **トークンを調べただけでなく、実行時に確認済み**: このまさに
   その行の後で`d1.Count`は`0`と表示された。InertiaNetCore自身の
   公式なC#スタイルの例をそのままOxygeneに移植しようとした人にとって、
   これは本物の、無言の失敗の罠である — コンパイラの警告もエラーも
   なく、本番環境でPage Propsが黙って空になるだけである。
2. `new Dictionary<String, Object>(['Name'] := 'Foo', ['Age'] := 30)`
   (波かっこの代わりに丸かっこ) — 実コンパイルエラー: `comma (,) or
   close parenthesis expected, got assignment (:=)`。
3. `new Dictionary<String, Object>(('Name', 'Foo'), ('Age', 30))`
   (タプルペアのAdd形式) — 実コンパイルエラー: 一致するコンストラクタ
   オーバーロードがない(タプルリテラルは`capacity`/`comparer`ペアに
   強制変換されない)。

**結論: Oxygeneで`InertiaProps`/`Dictionary`を埋める唯一の方法は、
構築後の連続したインデクサ代入文である**(`var props := new
InertiaProps; props['User'] := aUser; props['IsAdmin'] := true;`)—
実際に動作する唯一のパターンであり(§22.1の通り)、他に意味のある
ものにコンパイルされるインライン代替が存在しない以上、実際の
Oxygene Inertiaコードが使いうる唯一のパターンでもあると確認した。

**このプロジェクトとは別にRemObjectsへ報告する価値がある**(まだ
していない — `HANDOFF.md` §17の`deps.json`バグと同様、ユーザーの
判断に委ねる): もっともらしいオブジェクト初期化子に見える波かっこの
ブロックが、動作するかエラーになるかのどちらでもなく黙ってコメント
扱いのno-opにコンパイルされてしまうのは、これまでRemObjectsが
反応してくれた種類の問題と一致する鋭い落とし穴である。

### 22.4 検出の実現可能性、`TokenStream`による実機確認

§22.3により実際のコードは*常に*連続文パターンになると分かったので、
以下の現実的なプローブメソッドを`RemObjects.Elements.Code.
TokenStream`(`NullabilityScanner`と同じツール、同じ手法、§16)で
トークナイズし、生のトークン列を確認した:

```pascal
method Profile(aUser: UserDto): InertiaResponse;
begin
  var props := new InertiaProps;
  props['User'] := aUser;
  props['IsAdmin'] := true;
  result := Inertia.Render('pages/Profile', props);
end;
```

トークン列は曖昧さがなく、綺麗に構造化されている — `method Profile
( aUser : UserDto )`からパラメータの宣言型が、`var props := new
InertiaProps`からローカル変数の型が得られ、`props [ '<key>' ] :=
<value> ;`はそれぞれ平坦で区切りやすい文であり、呼び出し箇所自体は
`Inertia . Render ( '<component>' , props ) ;`である。これは
`NullabilityScanner`が既に解決している問題と機構的に同じクラスの
もの(丸かっこ/角かっこの深さを追跡するトークン走査。§18.2の
indexerスキップロジックは、ここでのインデクサ代入検出が必要とする
ものと構造的に同じ形をしている)— **IL解析もRoslyn風のフルASTも
不要**であり、`docs/DESIGN.md` §3.5が挙げていた「どちらの手法も
プロトタイプされていない」というギャップを解消する。第3の選択肢 —
既に実証済みの`NullabilityScanner`基盤を拡張したソースレベルの
トークンスキャン — が答えであり、Oxygeneのコンパイラが標準的な
メタデータを通じて公開していないものについては、IL/reflectionより
ソースレベル解析を優先するというこのプロジェクト自身の既存の傾向
(§2.9、§8.3)と一致する。

### 22.5 Reflectionの役割: propsの形状自体には無力、名前付き型が解決された後は既存機構をそのまま再利用可能

メタデータのみのreflection(`MetadataLoadContext`、このツールの
Loader設計全体)はメソッドの*本体*を一切見ることができない —
propsのキーから型へのマッピングはreflectionからは100%不可視であり、
これはreflectionの問題ではなく純粋にソースレベルの問題であることを
裏付ける(NRTについて既に得ていた結論(`HANDOFF.md` §8.3)の、
より鋭いバージョンである)。しかし、ソーススキャンによって値の式が
*名前付き*型への参照(パラメータ/ローカル変数の宣言型、または
`new NamedType(...)`式)に解決された時点で、**既存の**
`AssemblyLoader`/`IrBuilder`のreflectionパイプラインが、新規コード
一切なしにその型自身のメンバー形状を処理してくれる — `docs/DESIGN.md`
§3.5自身の図(ステップ③「その型のメンバーを推移的に辿る。§3.2の
辺収集ロジックを再利用」)と一致する綺麗な役割分担である。インライン
の`new class(...)`によるanonymousリテラルの値(§22.2)は、この
引き継ぎの後でも完全にソースレベルのままとなる唯一のケースである
— その形状は、結果として得られる`<>f__AnonymousTypeN`をreflectする
のではなく、リテラル自身の`Name := expr`ペアを解析することから
得なければならない。

### 22.6 スコープの正直な評価: NRTのスキャナより大きい

実現可能であることは確認できたが、安いとは確認していない。v1の
エントリーポイントスキャナが、`NullabilityScanner`が既に行っている
こと以外に必要とするもの:

- メソッド単位のローカル変数の型追跡(パラメータの宣言型 +
  `var x := new T`のローカル宣言)— `NullabilityScanner`は今のところ
  「メソッド本体のローカル状態」という概念を一切持たず、型/メンバー
  レベルの宣言のみを扱う。
- `identifier['key'] := expr;`という文を、追跡している変数へ
  対応付けること。
- あえて小さく絞った式の形に対する型推論: リテラル、単純な識別子
  (追跡している宣言型を引く)、`new NamedType(...)`、そして
  `new class(...)`(自身のペアへ再帰する)。

**v1では意図的にスコープ外とする**(未解決の各キーごとに手作りの
式評価器を書くのではなく、`Tsgen.Diagnostics`の警告付きで`unknown`
にフォールバックするか、解決不能な部分が多すぎる場合はページ全体を
`docs/DESIGN.md` §3.5の明示的アノテーションの逃げ道にフォール
バックする): 条件分岐/ブランチ依存のキー設定、ヘルパーメソッド
呼び出し経由で設定されるキー、`Inertia.Defer(...)`/`Inertia.Merge
(...)`でラップされた値(実際の型はasyncラムダの戻り値の型 —
着手するなら、それ自体もう1つの小さなスパイクが必要)、動的に
計算される文字列キー、そして`Render`が実際に呼ばれるのとは別の
メソッド/クラスで構築されるpropsオブジェクト。

### 22.7 推奨

**エントリーポイント駆動の自動検出は技術的に実現可能であり、主軸の
仕組みとすべきである** — `docs/DESIGN.md` §3.5のフォールバック
(型ごとの明示的アノテーション)ではなく。実際のOxygeneコードが
とにかく生成しうる唯一のパターンと確認済みの、同一メソッド内での
連続したインデクサ代入パターンにスコープを絞る(§22.3)。上記の
明示的にスコープ外としたケースについて`unknown`/診断警告に
フォールバックする(controllerの何か1つでも認識できない箇所が
あった瞬間に完全な手動アノテーションを要求するのではなく)ことで、
よくあるケースでは「自動で、手動アノテーション不要」という価値を
保ちつつ、稀なケースでは破局的にではなく段階的に劣化させられる。

まだ行っていない、これに着手するセッションに残す作業: 実際の
スキャナの実装(`Tsgen.Nrt`隣接、または新規の`Tsgen.Inertia`的な
ユニット)、確認済みの連続パターンと明示的にスコープ外としたケース
(unknown+警告へ段階的に劣化することをロックインするため。クラッシュ
したり誤検出したりしないことを確認するため)の両方をカバーする
フィクスチャの構築、そして — §6.2でまだ開いたままの項目として —
`Inertia.Defer`/`Inertia.Merge`ラッパーケースを最終的にどう扱うかの
決定。

### 22.8 `docs/DESIGN.md`への影響

§3.5には改訂パスが必要: 「(a) IL解析 / (b) Roslyn構文木解析、
どちらもプロトタイプされていない」という枠組みを、このスパイクの
答え(`NullabilityScanner`の実証済みアプローチを拡張したソース
レベルの`TokenStream`スキャン)に置き換える。§22.1の
`InertiaProps`/`Dictionary`限定というAPI形状(任意のPOCOを受け取る
オーバーロードはない)を記載する。そして§22.3のOxygeneオブジェクト
初期化子の落とし穴を、検出設計が前提とする、成否を左右する事実として
記録する。ここでは全面的な書き直しはしていない — 次のパスに向けて
フラグを立てるのみ(`docs/DESIGN.md` §4の改訂が、実際に行われる前に
追跡されていたのと同様、`HANDOFF.md` §8.3 → §13)。
