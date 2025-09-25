# TestARView プロジェクト概要

## プロジェクトの目的
ARKit と RoomPlan を使用したiOSアプリケーション。室内空間のARスキャンと可視化を行う。

## 技術スタック
- **プラットフォーム**: iOS (SwiftUI)
- **言語**: Swift
- **フレームワーク**: 
  - SwiftUI (UIフレームワーク)
  - RealityKit (AR表示)
  - ARKit/RoomPlan (室内スキャン)
  - SwiftData (データ永続化)
- **ビルドツール**: Xcode (プロジェクトファイル: TestARView.xcodeproj)
- **最小iOS**: iOS 17以降と推定

## プロジェクト構造
- `TestARView/` - メインアプリケーションコード
  - `TestARViewApp.swift` - アプリエントリポイント
  - `ContentView.swift` - メインビュー
  - `RoomPlanARView.swift` - ARビュー管理
  - `ARContainerView.swift` - ARコンテナ実装
  - `Item.swift` - データモデル
  - `room.usdz` - 3Dモデルファイル
- `TestARViewTests/` - ユニットテスト
- `TestARViewUITests/` - UIテスト

## 主な機能
- 室内空間のARスキャン
- カテゴリ別フィルタリング（壁、床、天井、ドア、窓、開口部、収納、階段、家具、構造、その他）
- エンティティリストの表示
- USDZファイルの読み込みと表示