# TestARView 推奨コマンド

## ビルドコマンド
```bash
# Xcodeでプロジェクトを開く
open TestARView.xcodeproj

# コマンドラインビルド (Debug)
xcodebuild -project TestARView.xcodeproj -scheme TestARView -configuration Debug build

# コマンドラインビルド (Release)
xcodebuild -project TestARView.xcodeproj -scheme TestARView -configuration Release build

# クリーンビルド
xcodebuild -project TestARView.xcodeproj -scheme TestARView clean build
```

## テストコマンド
```bash
# ユニットテスト実行
xcodebuild test -project TestARView.xcodeproj -scheme TestARView -destination 'platform=iOS Simulator,name=iPhone 15'

# UIテスト実行
xcodebuild test -project TestARView.xcodeproj -scheme TestARViewUITests -destination 'platform=iOS Simulator,name=iPhone 15'
```

## フォーマット・リンティング
```bash
# Swift Format (利用可能)
swift-format format -i TestARView/*.swift
swift-format lint TestARView/*.swift
```

## Git操作
```bash
# ステータス確認
git status

# 変更をステージング
git add .

# コミット
git commit -m "commit message"

# プッシュ
git push origin main
```

## その他のユーティリティ
```bash
# ファイル一覧
ls -la

# ディレクトリ移動
cd TestARView

# ファイル検索
find . -name "*.swift"

# コード内検索
grep -r "検索文字列" TestARView/
```