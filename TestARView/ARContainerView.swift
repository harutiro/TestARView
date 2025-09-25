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
        let arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        context.coordinator.arView = arView

        // 背景色を設定
        arView.environment.background = .color(.systemBackground)

        print("makeUIView: ARView作成完了")
        
        Task {
            print("makeUIView: loadModel呼び出し開始")
            await context.coordinator.loadModel()
            print("makeUIView: loadModel呼び出し完了")
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.updateVisibility(selectedCategories: selectedCategories)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        var parent: ARContainerView
        var arView: ARView?
        var rootEntity: Entity?
        var allEntities: [EntityInfo] = []
        
        // エンティティの強い参照を保持するための配列
        private var entityReferences: [Entity] = []

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
                    await createFallbackEntities()
                    return
                }
                
                print("loadModel: SceneKitでroom.usdz解析開始")

                // まずSceneKitでUSDZファイルの構造を解析
                let nodeNames = await analyzeUSDZWithSceneKit(url: modelURL)

                print("loadModel: SceneKitで検出されたノード数: \(nodeNames.count)")
                for (index, nodeName) in nodeNames.enumerated() {
                    print("  [\(index)] \(nodeName)")
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
                print("loadModel: SceneKit解析結果からエンティティ情報作成開始")
                
                // SceneKit解析結果からエンティティ情報を作成
                let entities = await createEntitiesFromSceneKitNodes(nodeNames: nodeNames, roomEntity: roomEntity)
                self.allEntities = entities
                
                print("loadModel: オブジェクト階層抽出完了 - 数: \(entities.count)")
                for (index, entity) in entities.enumerated() {
                    print("  [\(index)] \(entity.name): \(entity.category) (level: \(entity.level))")
                }

                // UIを更新（メインスレッドで実行）
                await MainActor.run {
                    print("loadModel: UI更新開始 - parent.entityHierarchy更新予定")
                    self.parent.entityHierarchy = entities
                    print("loadModel: parent.entityHierarchy更新完了 - 数: \(self.parent.entityHierarchy.count)")
                }
                
                print("loadModel: 全処理完了")
                
            } catch {
                print("loadModel: エラー - \(error.localizedDescription)")
                
                // エラー時はフォールバック処理
                await createFallbackEntities()
            }
        }

        
        // 実際のオブジェクト名階層を抽出
        private func extractRealObjectHierarchy(_ modelEntity: ModelEntity) async -> [EntityInfo] {
            print("extractRealObjectHierarchy: 開始")
            var entities: [EntityInfo] = []
            
            // ルートエンティティを追加
            await MainActor.run {
                let rootInfo = EntityInfo(
                    name: modelEntity.name.isEmpty ? "RootModel" : modelEntity.name,
                    category: "Root",
                    level: 0,
                    entity: modelEntity
                )
                entities.append(rootInfo)
                self.entityReferences.append(modelEntity)
            }
            
            print("extractRealObjectHierarchy: ルートエンティティ追加完了 - 名前: \(modelEntity.name)")
            
            // 子エンティティを再帰的に探索
            await extractChildrenWithRealNames(modelEntity, entities: &entities, level: 1, parentName: modelEntity.name.isEmpty ? "RootModel" : modelEntity.name)

            // 子エンティティが少ない場合は、ModelComponentのマテリアル解析を行う
            if entities.count <= 1 {
                print("extractRealObjectHierarchy: 子エンティティが少ないため、マテリアル解析を実行")
                await extractMaterialsAsObjects(modelEntity, entities: &entities)
            }

            print("extractRealObjectHierarchy: 完了 - 総エンティティ数: \(entities.count)")
            return entities
        }
        
        // 子エンティティを実際の名前で再帰的に抽出
        private func extractChildrenWithRealNames(_ entity: Entity, entities: inout [EntityInfo], level: Int, parentName: String) async {
            print("extractChildrenWithRealNames: レベル\(level) - 親: \(parentName) - 子要素数: \(entity.children.count)")
            
            for child in entity.children {
                await MainActor.run {
                    // 実際のエンティティ名を使用（空の場合は型に基づいて名前を生成）
                    let childName: String
                    if !child.name.isEmpty {
                        childName = child.name
                    } else {
                        // 名前が空の場合は型とインデックスで識別
                        let entityType = String(describing: type(of: child))
                        childName = "\(entityType)_\(entities.count)"
                    }

                    // エンティティの種類に基づいてカテゴリを設定
                    let category: String
                    if child is ModelEntity {
                        category = "Model"
                    } else if child.children.isEmpty {
                        category = "Leaf"
                    } else {
                        category = "Container"
                    }

                    let childInfo = EntityInfo(
                        name: childName,
                        category: category,
                        level: level,
                        entity: child
                    )

                    entities.append(childInfo)
                    self.entityReferences.append(child)

                    print("  - 追加: \(childInfo.name) (category: \(childInfo.category), type: \(String(describing: type(of: child))))")
                }
                
                // さらに子エンティティがある場合は再帰的に処理
                if !child.children.isEmpty {
                    await extractChildrenWithRealNames(child, entities: &entities, level: level + 1, parentName: child.name.isEmpty ? "Entity_\(entities.count)" : child.name)
                }
            }
        }

        // マテリアルをオブジェクトとして抽出
        private func extractMaterialsAsObjects(_ modelEntity: ModelEntity, entities: inout [EntityInfo]) async {
            print("extractMaterialsAsObjects: マテリアル解析開始")

            if let modelComponent = modelEntity.components[ModelComponent.self] {
                let materials = modelComponent.materials
                print("extractMaterialsAsObjects: マテリアル数: \(materials.count)")

                for (index, material) in materials.enumerated() {
                    await MainActor.run {
                        let materialString = String(describing: material)
                        print("  - マテリアル[\(index)]: \(materialString)")

                        // マテリアルの名前を抽出
                        let objectName = "Material_\(index)"
                        let category = categorizeEntity(name: objectName)

                        let materialInfo = EntityInfo(
                            name: objectName,
                            category: category,
                            level: 1,
                            entity: modelEntity
                        )

                        entities.append(materialInfo)
                        print("    -> 追加: \(objectName) (\(category))")
                    }
                }
            } else {
                print("extractMaterialsAsObjects: ModelComponentが見つかりません")
            }
        }

        // SceneKitでUSDZファイルを解析してノード名を取得
        private func analyzeUSDZWithSceneKit(url: URL) async -> [String] {
            return await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        print("analyzeUSDZWithSceneKit: SceneKitでUSDZ読み込み開始")
                        let scene = try SCNScene(url: url, options: nil)
                        var nodeNames: [String] = []

                        // ルートノードから再帰的にすべての子ノードを探索
                        scene.rootNode.enumerateChildNodes { node, _ in
                            let nodeName = node.name ?? "unnamed_\(nodeNames.count)"
                            nodeNames.append(nodeName)
                            print("  - SceneKitノード発見: \(nodeName)")

                            // ジオメトリ情報も確認
                            if let geometry = node.geometry {
                                print("    -> ジオメトリタイプ: \(String(describing: type(of: geometry)))")
                                if let materials = geometry.materials.first {
                                    print("    -> マテリアル名: \(materials.name ?? "unnamed_material")")
                                }
                            }

                            // 全てのノードを探索し続ける
                        }

                        print("analyzeUSDZWithSceneKit: 完了 - 総ノード数: \(nodeNames.count)")
                        continuation.resume(returning: nodeNames)

                    } catch {
                        print("analyzeUSDZWithSceneKit: エラー - \(error.localizedDescription)")
                        continuation.resume(returning: [])
                    }
                }
            }
        }

        // SceneKitの解析結果からEntityInfoを作成
        private func createEntitiesFromSceneKitNodes(nodeNames: [String], roomEntity: ModelEntity) async -> [EntityInfo] {
            print("createEntitiesFromSceneKitNodes: 開始 - ノード数: \(nodeNames.count)")
            var entities: [EntityInfo] = []

            await MainActor.run {
                // ルートエンティティを追加
                let rootInfo = EntityInfo(
                    name: "room",
                    category: "Root",
                    level: 0,
                    entity: roomEntity
                )
                entities.append(rootInfo)
                self.entityReferences.append(roomEntity)

                // SceneKitで見つかったノード名をエンティティとして追加
                for nodeName in nodeNames {
                    let nodeInfo = EntityInfo(
                        name: nodeName,
                        category: categorizeEntity(name: nodeName),
                        level: 1,
                        entity: roomEntity  // 実際のEntityと関連付け
                    )
                    entities.append(nodeInfo)
                    print("  - 追加: \(nodeName) (\(nodeInfo.category))")
                }
            }

            print("createEntitiesFromSceneKitNodes: 完了 - 総エンティティ数: \(entities.count)")
            return entities
        }
        
        
        
        
        // エンティティ名からカテゴリを推定する関数
        private func categorizeEntity(name: String) -> String {
            let lowercaseName = name.lowercased()
            
            if lowercaseName.contains("wall") || lowercaseName.contains("壁") {
                return "壁"
            } else if lowercaseName.contains("floor") || lowercaseName.contains("床") {
                return "床"
            } else if lowercaseName.contains("ceiling") || lowercaseName.contains("天井") {
                return "天井"
            } else if lowercaseName.contains("door") || lowercaseName.contains("ドア") {
                return "ドア"
            } else if lowercaseName.contains("window") || lowercaseName.contains("窓") {
                return "窓"
            } else if lowercaseName.contains("furniture") || lowercaseName.contains("chair") || lowercaseName.contains("table") || lowercaseName.contains("家具") {
                return "家具"
            } else if lowercaseName.contains("stair") || lowercaseName.contains("階段") {
                return "階段"
            } else if lowercaseName.contains("storage") || lowercaseName.contains("収納") {
                return "収納"
            } else {
                return "その他"
            }
        }
        
        // フォールバック用のエンティティ作成
        private func createFallbackEntities() async {
            print("loadModel: フォールバック処理開始")
            
            // 簡単なサンプルオブジェクトを作成（以前のコード）
            let anchor = AnchorEntity(world: [0, 0, -1])

            // 床
            let floorMesh = MeshResource.generatePlane(width: 3, depth: 3)
            let floorEntity = ModelEntity(mesh: floorMesh)
            floorEntity.name = "Floor"
            floorEntity.position = [0, -0.5, 0]
            anchor.addChild(floorEntity)

            // 壁
            let wallMesh = MeshResource.generateBox(width: 3, height: 2, depth: 0.1)
            let wallEntity = ModelEntity(mesh: wallMesh)
            wallEntity.name = "Wall"
            wallEntity.position = [0, 0.5, -1.5]
            anchor.addChild(wallEntity)

            guard let arView = arView else { return }
            arView.scene.addAnchor(anchor)
            self.rootEntity = anchor
            
            // エンティティの強い参照を保持
            self.entityReferences = [floorEntity, wallEntity]
            
            // エンティティ情報を作成
            let entities = [
                EntityInfo(name: "Floor", category: "床", level: 0, entity: floorEntity),
                EntityInfo(name: "Wall", category: "壁", level: 0, entity: wallEntity)
            ]
            
            self.allEntities = entities
            print("loadModel: フォールバック処理完了 - 数: \(entities.count)")

            // UIを更新
            await MainActor.run {
                self.parent.entityHierarchy = entities
                print("loadModel: フォールバック用parent.entityHierarchy更新完了 - 数: \(self.parent.entityHierarchy.count)")
            }
        }

        func updateVisibility(selectedCategories: Set<String>) {
            for entityInfo in allEntities {
                entityInfo.entity?.isEnabled = selectedCategories.contains(entityInfo.category)
            }
        }
    }
}