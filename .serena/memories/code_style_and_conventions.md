# コードスタイルとコンベンション

## Swift コーディング規約

### 命名規則
- **型名（Class, Struct, Enum, Protocol）**: PascalCase
  - 例: `TestARViewApp`, `ContentView`, `EntityInfo`
- **変数・関数名**: camelCase
  - 例: `selectedCategories`, `entityHierarchy`, `showEntityList`
- **定数**: camelCase（プライベートはアンダースコア接頭辞なし）
  - 例: `allCategories`

### SwiftUIビュー
- `View` プロトコル準拠の構造体として実装
- `@State`, `@Binding` などのプロパティラッパーを活用
- ボディは計算プロパティとして実装

### インデント・フォーマット
- インデント: スペース4つ
- 中括弧: K&R スタイル（同じ行に開き中括弧）
- 行の最大長: 特に制限なし（ただし読みやすさ重視）

### SwiftData モデル
- `@Model` マクロを使用
- `final class` として定義
- イニシャライザーを明示的に定義

### アクセス修飾子
- デフォルトは internal（省略）
- プライベートメンバーには `private` を明示
- パブリックAPIには `public` を明示

### エラーハンドリング
- `do-catch` でエラーをキャッチ
- fatalError は最小限に（ModelContainer初期化など必須の場合のみ）

### コメント
- 必要最小限のコメント
- コードが自己説明的であることを重視

## プロジェクト固有の規約
- 日本語文字列を直接コード内に記述（ローカライゼーションなし）
- ARKit関連のコードは専用のビューに分離
- UIはSwiftUIで統一