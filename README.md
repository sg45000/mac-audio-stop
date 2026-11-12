# AutoMute for Mac

BluetoothイヤホンからMacの内蔵スピーカーへ出力が変わった際に、自動ミュートして音声漏れを減らすためのmacOSアプリです。

起動するとデフォルト音声出力を監視し、Bluetooth／Bluetooth LE出力から内蔵スピーカーへ変わったときにミュートをONにします。切断と手動切り替えはどちらも対象です。起動時のミュートや再接続時の解除は行わず、音量設定は変更しません。ウィンドウやメニューバー項目は表示しません。

## ビルド・テスト

Apple Silicon、macOS 27以降、Xcode 27以降が必要です。外部ライブラリ、ネットワーク接続、有料の開発者契約は不要です。ローカル実行用のアドホック署名でビルドします。

```sh
cd ~/Development/mac-audio-stop
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project AutoMute.xcodeproj -scheme AutoMute \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build build
xcodebuild -project AutoMute.xcodeproj -scheme AutoMute \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build test
```

テストはアプリを起動しないXCTestです。Core Audio操作を代替実装に差し替えるため、実機の出力先・音量・ミュートを変更しません。

Xcodeで実行する場合は`AutoMute.xcodeproj`を開き、`AutoMute`スキームと`My Mac`を選びます。Releaseは上のビルドコマンドの`Debug`を`Release`に置き換えて作成できます。

## 起動とログ確認

別のターミナルでログを表示します。

```sh
log stream --level debug --style compact --predicate 'subsystem == "local.AutoMute"'
```

アプリを起動します。

```sh
./build/Build/Products/Debug/AutoMute.app/Contents/MacOS/AutoMute
```

起動時に現在の出力が記録され、自動ミュートの監視を開始します。Bluetoothイヤホンを接続して出力先に選び、切断すると、内蔵スピーカーへの変更時に一度ミュートします。ログで変更前後のID・名前・種類・Transport Type・端子種別、ミュートの設定要求と反映確認を確認できます。変更通知の受信と重複通知はdebugレベルで記録します。

同じ出力への重複通知では再ミュートしません。ユーザーがミュートを解除した後も、次のBluetooth出力から内蔵スピーカーへの変更までは操作しません。ミュートに失敗した場合はログを残して監視を続け、同じ変更に対する自動再試行は行いません。

Ctrl+Cで終了します。Xcodeの停止操作やActivity Monitorからも終了できます。SIGINT・SIGTERMによる終了ではリスナーを解除します。強制終了時の終了ログは保証しません。常駐確認では同じアプリを複数同時に起動しないでください。

## 一度限りのミュート検証

通常の常駐プロセスを終了し、macOSの出力先に内蔵スピーカーを選んで実行します。

```sh
./build/Build/Products/Debug/AutoMute.app/Contents/MacOS/AutoMute --verify-mute-once
```

- 内蔵スピーカーを識別でき、Main要素のミュートが書き込み可能な場合だけONにします。
- 設定前に変更リスナーを登録し、通知と読み戻しで結果を確認します。通知がない場合も1秒後に一度読み戻します。再書き込みや音量0への変更は行いません。
- 成功またはミュート済みの場合は終了コード0、失敗は1で終了します。詳細はLoggerのログに出力します。
- ミュート解除は行いません。検証後に必要ならmacOS側で解除してください。
- この引数はDebug専用です。Releaseではエラーを記録して終了し、設定を書き換えません。

Xcodeでは、Product → Scheme → Edit Scheme → Run → Argumentsに`--verify-mute-once`を追加して実行できます。テストにはこの引数を引き継がない設定です。

音量維持を確認する場合は、macOS側で内蔵スピーカーの音量を50%にし、ミュート実行後も設定値が変わっていないことを確認します。ログの設定要求から確認までの時間は、実際に出力が切り替わってからの時間を示すものではありません。

## 実機での確認

まず再生を止めた状態で確認します。

1. 内蔵スピーカーを選び、音量を50%・ミュートOFFにして起動する。起動だけではミュートされないことを確認する。
2. Bluetoothイヤホンを接続して出力先に選ぶ。内蔵からBluetoothへの変更ではミュート操作が記録されないことを確認する。
3. イヤホンを切断する。内蔵スピーカーへの変更、ミュート設定要求、読み戻しによる成功の順にログが記録され、音量設定が維持されることを確認する。
4. イヤホンを再接続する。自動ミュートの解除操作が行われず、監視が続くことを確認する。
5. 内蔵スピーカーでミュートを手動解除し、再接続・切断を繰り返す。各切り替えで処理されることを確認する。

続いて小さな音量でChrome・Safariの動画を再生して切断し、実際にミュートされることと、切断直後に音声が漏れるかを確認します。ログの時刻は変更通知受信以降の処理を示し、物理的な切断や出力切り替えそのものの時刻は示しません。

## 制約

外部出力のミュートは行いません。設計上の条件は[設計方針](docs/design.md)を参照してください。

出力変更通知は切り替え後に届くため、一瞬の音声漏れは防げない場合があります。仮想デバイスやアプリ独自の出力先は対象外です。内蔵スピーカーを識別できない機種やMain要素のミュートを提供しない機種では、操作せずエラーを記録します。
