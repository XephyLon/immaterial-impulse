<div align="center">
    <img src="assets/immaterial-impulse.png" alt="Immaterial Impulse logo" width="180">
    <h1>【 Immaterial Impulse 】</h1>
    <h3><a href="https://github.com/end-4/dots-hyprland">illogical-impulse</a> の邪悪な双子。</h3>
    <p><em>illogical-impulse は「本当にそれ、必要？」と問う ―― Immaterial Impulse は「でも、<b>欲しい</b>でしょ？」と問う。</em></p>
    <p><a href="README.md">English</a> | <a href="README.zh-CN.md">简体中文</a> | 日本語</p>
</div>

---

## 前提

[illogical-impulse](https://github.com/end-4/dots-hyprland) は実用第一：
規律正しく、美しく、ミニマルな Material 3 シェルで、すべてのウィジェットが
その存在価値を証明しています。

**Immaterial Impulse は、その同じ美しい土台を受け継ぎつつ、真逆を行きます。**
実用第一のシェルが「肥大化」と呼ぶもの ―― Wallpaper Engine のライブ壁紙、
本格的なプラグインプラットフォーム、Docker コントロール、Discord ボイス、
周期表チートシート ―― に全力で振り切り、それをプラグアンドプレイの
単一スイートとして届けます。同じ DNA。自制心ゼロ。すべて確信犯です。

これは [@end-4](https://github.com/end-4) の illogical-impulse のフォークで、
リブランドして一つのリポジトリに統合したものです：[Quickshell](https://quickshell.outfoxxed.me/)
シェル、[Hyprland](https://github.com/hyprwm/hyprland) の完全な設定、そして
ガイド付きインストーラーを丸ごと。既存の illogical-impulse 環境を**置き換え**、
初回起動時に旧設定とシークレットを移行します ―― 何も失われません。

> **これは：** グラフィカルシェル + Hyprland 設定 + インストーラー。
> **これではない：** フルシステムのブートストラッパー ―― ドライバも zram も
> ブートローダーも扱いません。

---

## 愛を込めて厳選された「肥大化」

### 🧩 本物のプラグインプラットフォーム
目玉機能。設定ファイルではなく、拡張可能なウィジェットプラットフォームです。
プラグインを `~/.config/immaterial-impulse/plugins/` に放り込めば、そのまま
現れます。形式は 2 つ：`manifest.json` で承認済みコンポーネントを記述する
**宣言型**プラグインと、ネイティブのシェルコンポーネントとトークンを使った
独自 QML を同梱する**パッケージ型**プラグイン。エントリポイントは
**バーウィジェット、デスクトップウィジェット、コントロールセンター
ウィジェット、ランチャープロバイダー、パネル丸ごと、設定 UI** をカバーし、
宣言式の**パーミッション**モデル（`process`、`network`、`filesystem`、
`settings`）の管理下に置かれます。作者クレジット付きのプラグイン**カタログ**、
**リモートインストール**、作者向けデザインシステムライブラリ
（`ExpressiveTokens`、コンポーネントレジストリ）も完備。同梱例：
**Docker** コントロール、**Discord ボイス**、システムモニター、天気、
為替レート、時計ウィジェット。

### 🌊 ライブ壁紙 ―― ただの画像じゃない
**ローカル**と**オンライン**の壁紙ブラウザーに加え、ファーストクラスの
**Wallpaper Engine** サポート：WE のアニメーションシーンがシェル内で
ライブレンダリングされ、切り替え時には**シェーダートランジション**が
かかります。**frost（フロスト）**コントロールは、ウィジェットが壁紙の上に
どう載るかを決めます：背後の領域を本物のシェル内**ブラー**にするか、
軽量なパレット**ティント**にするか。

### 🎨 Material You を、あらゆる場所へ一斉に
壁紙を選ぶと、システム全体が塗り替わります。matugen が一つのパレットを
GTK、Hyprland、ターミナル、**cava**、**tmux**、そしてシェル自体へ伝播します。

### 🖥️ バーではなく、デスクトップ丸ごと
全編 Material 3 Expressive：水平/垂直の**バー**、**ドック**、左右の
**サイドバー**、ライブウィンドウプレビュー付きの**オーバービュー**、
**通知**、**OSD** と**オンスクリーンキーボード**、**歌詞同期付きメディア
コントロール**、**セッション/ロック**画面、**polkit** エージェント、
そしてそのすべてを設定できるシェル内**設定アプリ** ―― ワンクリックの
Hyprland アニメーションプリセット付き。

### 🤖 AI + 快適装備
サイドバーから任意の OpenAI 互換エンドポイント、Gemini、ローカルの Ollama と
チャット。画面上の**翻訳**、スクリーンショットと Google Lens 用の
**領域セレクター**、アンチフラッシュバン、そして ―― そう ――
`Super`+`/` で開く、周期表入りのキーボードショートカット**チートシート**。
だって、あってもいいでしょ？

---

## インストール

> シェルは `~/.config/quickshell/ii` に、その設定は
> `~/.config/immaterial-impulse` にインストールされます。
> **illogical-impulse から乗り換えますか？** インストーラーは既存環境を検出し
> ―― `illogical-impulse-*` パッケージ、または（手動インストールの場合）残された
> `~/.config/illogical-impulse` 設定から ―― 移行を実施します：
> `immaterial-impulse-*` パッケージが旧パッケージを置き換え、上書き前に
> `~/.config/quickshell` をバックアップし、設定ディレクトリとキーリングの
> エントリは初回起動時に新しい名前へ移行されます。

```sh
# Quick install — fetches the suite, then runs the installer (bash/zsh/fish)
curl -fsSL https://raw.githubusercontent.com/XephyLon/immaterial-impulse/main/get.sh -o /tmp/imi-get.sh && bash /tmp/imi-get.sh

# Or clone and run it yourself
git clone https://github.com/XephyLon/immaterial-impulse.git
cd immaterial-impulse
./setup
```

> ダウンロードしてから実行する方式は、移植性と正しさの両方を保ちます：
> `curl … | bash` は stdin を占有してインストーラーの対話メニューを壊し、
> `bash <(curl …)` は bash 専用です（fish では失敗します）。bash 上で
> ワンライナーがお好みなら、`bash <(curl -fsSL …/get.sh)` でも動きます。

引数なしで `./setup` を実行すると **whiptail メニュー**が開きます：

- **Components（コンポーネント）** ―― コア設定と依存関係。
- **Wallpaper Engine**（オプション）―― Wallpaper Engine モジュールを組み込んだ
  カスタム Quickshell を、`PATH` 上で純正バイナリより前に配置します。
  x86_64 では**検証済みビルド済み版**（チェックサム検証付き）を数秒で
  インストール。一致しない場合（他アーキテクチャ、古い Qt、チェックサム/
  スモークテスト失敗）はソースからのコンパイルにフォールバックします。
  長いコンパイルは Ctrl-C でキャンセル可能。デフォルトはオフ。未導入の場合、
  WE 壁紙は静止画にフォールバックします。
- **SDDM ログインテーマ**（オプション、Arch のみ）――
  [ii-sddm-theme](https://github.com/3d3f/ii-sddm-theme) を専用インストーラー
  経由で導入し、ログイン画面をロック画面の美学に揃えます。デフォルトはオフ。
- **Extras（エクストラ）** ―― フォントセット、fcitx5 IME、その他状況に応じた
  オーバーレイ。

すべてのコマンドは実行前に表示されます。スクリプト用途には、
`./setup install` が同じパイプラインを非対話で実行します。

**キーバインド**は Windows/GNOME の身体感覚に従います：

| キーバインド | 動作 |
| --- | --- |
| `Super`+`/` | キーバインド一覧チートシート |
| `Super`+`Enter` | ターミナル |

---

## ソフトウェア概要

| ソフトウェア | 役割 |
| --- | --- |
| [Hyprland](https://github.com/hyprwm/hyprland) | Wayland コンポジター ―― ウィンドウの管理と描画 |
| [Quickshell](https://quickshell.outfoxxed.me/) | QtQuick ウィジェットシステム ―― バー、サイドバー、ドック、プラグイン、全部これ |
| matugen | 壁紙からの Material You カラー生成 |
| その他 | [deps-info.md](../sdata/deps-info.md) を参照 |

---

## スクリーンショット

### 一つの土台、どんな気分にも

同じシェル、三つのパレット ―― Material You が壁紙からすべてを塗り替えます。

<table>
  <tr><td colspan="2" align="center"><img src="../dots/.config/quickshell/ii/screenshots/green.png" alt="Green"><br><em>Green</em></td></tr>
  <tr><td colspan="2" align="center"><img src="../dots/.config/quickshell/ii/screenshots/study.png" alt="Study"><br><em>Study</em></td></tr>
  <tr><td colspan="2" align="center"><img src="../dots/.config/quickshell/ii/screenshots/red.png" alt="Red"><br><em>Red</em></td></tr>
</table>

---

## クレジット

善良な方の双子と、その源となったコミュニティ：

- [@end-4](https://github.com/end-4) ―― illogical-impulse。このフォークの根。
- [pctrade](https://github.com/pctrade/end4-pC) ―― 本スイートが直接基盤とする
  `end4-pC` フォーク。
- [na-ive](https://github.com/na-ive/nandoroid-shell) ―― nandoroid-shell。
  同梱の Nandoroid ウィジェットプラグインと expressive デザイントークンの
  出典（AGPL-3.0）。
- [caelestia-dots](https://github.com/caelestia-dots/caelestia) ――「Caelestia」
  アニメーションプリセット。
- [@clsty](https://github.com/clsty) ―― オリジナルのインストールスクリプト、
  その他多数。
- [@midn8hustlr](https://github.com/midn8hustlr) ―― カラー生成システム。
- [@outfoxxed](https://github.com/outfoxxed/) ―― Quickshell。
- Quickshell dotfiles：[Soramane](https://github.com/caelestia-dots/shell/)、
  [FridayFaerie](https://github.com/FridayFaerie/quickshell)、
  [nydragon](https://github.com/nydragon/nysh)。

## ライセンス

リポジトリのライセンスを参照してください。条件を守る限り、自由にコピー・
改変してかまいません。
