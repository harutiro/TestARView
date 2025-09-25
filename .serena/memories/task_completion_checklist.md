# タスク完了チェックリスト

タスクを完了する前に、以下の項目を必ず確認してください：

## 1. コードの品質確認
- [ ] コードが既存のスタイルに準拠している
- [ ] 不要なコメントや print 文を削除した
- [ ] 適切なエラーハンドリングが実装されている

## 2. ビルド確認
```bash
xcodebuild -project TestARView.xcodeproj -scheme TestARView -configuration Debug build
```
- [ ] ビルドが成功する
- [ ] 警告がない、または最小限

## 3. フォーマット確認（利用可能な場合）
```bash
swift-format lint TestARView/*.swift
```
- [ ] フォーマットエラーがない

## 4. テスト実行（テストがある場合）
```bash
xcodebuild test -project TestARView.xcodeproj -scheme TestARView -destination 'platform=iOS Simulator,name=iPhone 15'
```
- [ ] 既存のテストが通る
- [ ] 新機能にテストを追加（必要に応じて）

## 5. Git確認
```bash
git status
git diff
```
- [ ] 意図した変更のみがステージングされている
- [ ] 不要なファイルが含まれていない

## 6. 実機・シミュレータ動作確認
- [ ] iOS シミュレータで動作確認
- [ ] UI が正しく表示される
- [ ] 機能が期待通り動作する

## 注意事項
- **必ずビルドを通してエラーがないことを確認してから終了する**
- コミットは明示的に要求された場合のみ実行する