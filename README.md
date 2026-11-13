# AutoMute for Mac

BluetoothイヤホンからMacの内蔵スピーカーへ音声出力が変わったとき、自動でミュートするメニューバーアプリです。イヤホンの切断時などに、スピーカーから音が出るのを減らします。

Bluetooth／Bluetooth LEから内蔵スピーカーへの変更が対象です。手動で出力先を切り替えた場合も動作します。音量設定は変更せず、イヤホンを再接続しても自動でミュートを解除しません。

**出力が切り替わった後の通知でミュートするため、一瞬の音声漏れを完全には防げません。**

## 対応環境

- Apple Silicon搭載のMac
- macOS 27.0以降
- ビルドにはXcode 27以降が必要

Swift・AppKit・Core Audioを使用しています。外部ライブラリや実行時のネットワーク接続は不要です。現時点ではソースからビルドして利用します。Developer ID署名・公証済みの配布版は提供していません。

実機で確認している組み合わせは、macOS 27.2のMacBook AirとAirPods 4です。Bluetooth LEやその他の機種・イヤホンでの実機動作は未確認です。Bluetooth LEの判定は自動テストで確認しています。Intel MacとmacOS 26以前は現在のビルド設定では対象外です。

## ビルドして使う

Xcodeをインストールし、初回起動時の設定を済ませてから、ターミナルで実行します。

```sh
git clone https://github.com/sg45000/mac-audio-stop.git
cd mac-audio-stop
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project AutoMute.xcodeproj -scheme AutoMute \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build build
mkdir -p "$HOME/Applications"
ditto ./build/Build/Products/Release/AutoMute.app "$HOME/Applications/AutoMute.app"
open "$HOME/Applications/AutoMute.app"
```

`DEVELOPER_DIR`はXcodeの配置先に合わせて変更してください。Mac全体の開発ツール設定を変更する必要はありません。ローカル実行用のアドホック署名を使うため、有料のApple Developer Program契約は不要です。

起動すると、メニューバーに斜線付きスピーカーのアイコンが表示されます。通常のウィンドウやDockアイコンはありません。更新時は、起動中のAutoMuteをメニューから終了してから、再ビルドして同じ場所へコピーします。

Xcodeから試す場合は`AutoMute.xcodeproj`を開き、`AutoMute`スキームと`My Mac`を選んで実行できます。配置した版と同時には起動しないでください。

## 操作

メニューバーのアイコンをクリックします。右上のチェック付きの丸がON、空の丸がOFFです。この表示は自動ミュート機能の状態を表します。Macの現在のミュート状態はmacOS側で確認してください。

- **自動ミュートをOFFにする**：監視を停止します。すでに実行したミュートは解除しません。
- **自動ミュートをONにする**：現在の出力先を初期状態として監視を再開します。ONにしただけではミュートしません。
- **AutoMuteを終了**：監視を停止し、アプリを終了します。終了時にもミュートは解除しません。

初回はONです。ON/OFFの選択は次回起動時にも引き継ぎます。起動時に内蔵スピーカーが選ばれていても、それだけではミュートしません。音を戻すときは、macOSのサウンド設定やキーボードでミュートを解除してください。

監視を開始できない場合はOFFで常駐し、メニューに失敗を表示します。メニューから再度ONにできます。

## ログイン時に起動する

macOSの「システム設定」→「一般」→「ログイン項目と機能拡張」の「ログイン時に開く」に、配置した`~/Applications/AutoMute.app`を追加します。次回ログイン時には前回のON/OFFで起動します。自動起動を止める場合は、この項目から削除します。

## 動作の範囲と制約

- Mac全体のデフォルト音声出力の変更を監視します。アプリが独自に指定した出力先や仮想オーディオデバイスは対象外です。
- USB・有線ヘッドホンなどから内蔵スピーカーへの変更は対象外です。外部スピーカーやマイクも操作しません。
- 内蔵スピーカーを識別できない場合や、ミュートの書き込みに対応しない機種では操作せず、ログに失敗を記録します。音量を0にする代替処理は行いません。
- 同じ変更の重複通知では再ミュートしません。手動でミュートを解除した後は、次の対象となる出力変更まで操作しません。
- ミュートに失敗しても監視は続けます。同じ変更に対する自動再試行は行いません。

外部へのデータ送信はありません。ON/OFFはMac内のUserDefaultsに保存し、診断情報はmacOSのログに記録します。独自のログファイルは作成しません。

## 開発・不具合報告

ビルド、音声設定を変更しない自動テスト、ログ確認、実機検証の手順は[開発・検証ガイド](docs/development.md)にまとめています。判定条件や責務の分け方は[設計方針](docs/design.md)を参照してください。

不具合は[Issues](https://github.com/sg45000/mac-audio-stop/issues)で報告できます。macOSのバージョン、Macと音声機器の種類、切り替え前後の出力先、期待した動作と実際の動作を記載してください。ログを添える場合は、機器名などに含まれる個人情報を取り除いてください。

## ライセンス

[MIT License](LICENSE)。著作権表記は`Copyright (c) 2026 sg45000`です。
