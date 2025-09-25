//
//  ARContainerView.swift
//  TestARView
//
//  Created by Assistant on R 7/09/26.
//

import SwiftUI
import RealityKit
import ARKit
import SceneKit

struct ARContainerView: UIViewRepresentable {
    @Binding var selectedCategories: Set<String>
    @Binding var entityHierarchy: [EntityInfo]

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Coordinatorでの参照のためにARViewを保存
        context.coordinator.arView = arView

        print("makeUIView: ARView作成完了")

        // 非同期でモデルを読み込み
        Task {
            print("makeUIView: loadModel呼び出し開始")
            await context.coordinator.loadModel()
            print("makeUIView: loadModel呼び出し完了")
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // 必要に応じて更新処理
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    class Coordinator: NSObject {
        var parent: ARContainerView
        var arView: ARView?
        var rootEntity: AnchorEntity?
        var allEntities: [EntityInfo] = []

        // エンティティの強参照を保持
        var entityReferences: [Entity] = []

        init(_ parent: ARContainerView) {
            self.parent = parent
        }

        func loadModel() async {
            guard let arView = arView else {
                print("loadModel: arView is nil")
                return
            }

            print("loadModel: 開始")

            do {
                // room.usdzファイルを読み込み
                guard let modelURL = Bundle.main.url(forResource: "room", withExtension: "usdz") else {
                    print("loadModel: room.usdzファイルが見つかりません")
                    return
                }

                print("loadModel: SceneKitでroom.usdz解析開始")

                // SceneKitでUSDZファイルの階層構造を解析
                let grpObjects = await analyzeUSDZForGrpObjects(url: modelURL)

                print("loadModel: _grpオブジェクト数: \(grpObjects.count)")
                for (grpName, children) in grpObjects {
                    print("  - \(grpName): 子要素\(children.count)個")
                    for child in children {
                        print("    -> \(child)")
                    }
                }

                print("loadModel: RealityKitでroom.usdz読み込み開始")
                let roomEntity = try await ModelEntity(contentsOf: modelURL)

                // アンカーを作成してシーンに追加
                let anchor = AnchorEntity(world: [0, 0, -1])
                anchor.addChild(roomEntity)
                arView.scene.addAnchor(anchor)

                self.rootEntity = anchor
                self.entityReferences = [roomEntity]

                print("loadModel: room.usdz読み込み完了")

                // _grpオブジェクトからEntityInfoを作成
                let entities = await createEntitiesFromGrpObjects(grpObjects: grpObjects, roomEntity: roomEntity)
                self.allEntities = entities

                print("loadModel: エンティティ作成完了 - 数: \(entities.count)")
                for (index, entity) in entities.enumerated() {
                    print("  [\(index)] \(entity.name): \(entity.category) (level: \(entity.level))")
                }

                // UIを更新
                self.parent.entityHierarchy = entities
                print("loadModel: UI更新完了 - 数: \(self.parent.entityHierarchy.count)")

                print("loadModel: 全処理完了")

            } catch {
                print("loadModel: エラー - \(error.localizedDescription)")
            }
        }

        // SceneKitで_grpオブジェクトとその子要素のみを抽出
        private func analyzeUSDZForGrpObjects(url: URL) async -> [String: [String]] {
            return await withCheckedContinuation { continuation in
                Task.detached {
                    do {
                        print("analyzeUSDZForGrpObjects: SceneKitでUSDZ読み込み開始")
                        let scene = try SCNScene(url: url, options: nil)
                        var grpObjects: [String: [String]] = [:]

                        // ルートノードから_grpオブジェクトを探索
                        findGrpObjectsStatic(scene.rootNode, grpObjects: &grpObjects)

                        print("analyzeUSDZForGrpObjects: 完了 - _grpオブジェクト数: \(grpObjects.count)")
                        continuation.resume(returning: grpObjects)

                    } catch {
                        print("analyzeUSDZForGrpObjects: エラー - \(error.localizedDescription)")
                        continuation.resume(returning: [:])
                    }
                }
            }
        }

        // _grpオブジェクトからEntityInfoを作成
        private func createEntitiesFromGrpObjects(grpObjects: [String: [String]], roomEntity: ModelEntity) async -> [EntityInfo] {
            print("createEntitiesFromGrpObjects: 開始 - _grpオブジェクト数: \(grpObjects.count)")

            // ルートエンティティを追加
            let rootInfo = EntityInfo(
                name: "room",
                category: "Root",
                level: 0,
                entity: roomEntity
            )
            var entities = [rootInfo]
            self.entityReferences.append(roomEntity)

            // _grpオブジェクトとその子要素を追加
            for (grpName, children) in grpObjects {
                // _grpオブジェクト自体を追加
                let grpInfo = EntityInfo(
                    name: grpName,
                    category: categorizeGrpObject(name: grpName),
                    level: 1,
                    entity: roomEntity
                )
                entities.append(grpInfo)
                print("  - _grp追加: \(grpName) (\(grpInfo.category))")

                // その子要素を追加
                for childName in children {
                    let childInfo = EntityInfo(
                        name: childName,
                        category: categorizeChildObject(name: childName),
                        level: 2,
                        entity: roomEntity
                    )
                    entities.append(childInfo)
                    print("    -> 子要素追加: \(childName) (\(childInfo.category))")
                }
            }

            print("createEntitiesFromGrpObjects: 完了 - 総エンティティ数: \(entities.count)")
            return entities
        }

        // _grpオブジェクトのカテゴリ分け
        private func categorizeGrpObject(name: String) -> String {
            let lowercaseName = name.lowercased()

            if lowercaseName.contains("storage") {
                return "Storage"
            } else if lowercaseName.contains("wall") {
                return "Wall"
            } else if lowercaseName.contains("floor") {
                return "Floor"
            } else if lowercaseName.contains("television") {
                return "Television"
            } else if lowercaseName.contains("section") {
                return "Section"
            } else if lowercaseName.contains("object") {
                return "Object"
            } else if lowercaseName.contains("arch") {
                return "Architecture"
            }

            return "Group"
        }

        // 子オブジェクトのカテゴリ分け
        private func categorizeChildObject(name: String) -> String {
            let lowercaseName = name.lowercased()

            if lowercaseName.contains("storage") {
                return "Storage Item"
            } else if lowercaseName.contains("wall") {
                return "Wall Element"
            } else if lowercaseName.contains("floor") {
                return "Floor Element"
            } else if lowercaseName.contains("door") {
                return "Door"
            } else if lowercaseName.contains("television") {
                return "TV"
            } else if lowercaseName.contains("livingroom") {
                return "Room"
            }

            return "Element"
        }

        func updateVisibility(selectedCategories: Set<String>) {
            // カテゴリに基づく表示/非表示の制御
        }
    }
}

// 静的関数として分離してactor分離の問題を解決
private func findGrpObjectsStatic(_ node: SCNNode, grpObjects: inout [String: [String]]) {
    for child in node.childNodes {
        if let nodeName = child.name {
            if nodeName.hasSuffix("_grp") {
                // _grpオブジェクト発見
                print("  - _grpオブジェクト発見: \(nodeName)")
                var children: [String] = []

                // その子要素を収集
                collectChildrenStatic(child, children: &children)
                grpObjects[nodeName] = children

                print("    -> 子要素: \(children)")
            } else {
                // _grpではない場合はさらに深く探索
                findGrpObjectsStatic(child, grpObjects: &grpObjects)
            }
        }
    }
}

// 静的関数として分離してactor分離の問題を解決
private func collectChildrenStatic(_ node: SCNNode, children: inout [String]) {
    for child in node.childNodes {
        if let childName = child.name {
            children.append(childName)
            // さらに子要素がある場合は再帰的に収集
            collectChildrenStatic(child, children: &children)
        }
    }
}