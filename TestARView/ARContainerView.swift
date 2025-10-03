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
import ModelIO

struct ARContainerView: UIViewRepresentable {
    @Binding var selectedCategories: Set<EntityCategory>
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
        // selectedCategoriesが変更された場合、表示/非表示を更新
        context.coordinator.updateVisibility(selectedCategories: selectedCategories)
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
        var lastSelectedCategories: Set<String> = []

        // SceneKitからRealityKitに変換された個別エンティティを保存
        var categoryEntities: [EntityCategory: [Entity]] = [:]

        // 元のTransform値を保存するディクショナリ
        var originalTransforms: [ObjectIdentifier: Transform] = [:]

        // 可視性状態を管理
        var entityVisibilityState: [ObjectIdentifier: Bool] = [:]

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

                print("loadModel: 元のUSDZモデルを読み込み開始")

                // 元のUSDZモデルを読み込んでリファレンスとして使用（表示はしない）
                let originalModelEntity = try await ModelEntity(contentsOf: modelURL)

                print("loadModel: 元のモデル読み込み完了（リファレンス用）")

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

                print("loadModel: SceneKitから個別エンティティを作成中...")

                // SceneKitの個別ノードをRealityKitエンティティに変換
                let (individualAnchor, categoryMap) = await createIndividualEntitiesFromSceneKit(url: modelURL, grpObjects: grpObjects, referenceEntity: originalModelEntity)

                // 個別エンティティのアンカーをシーンに追加（元の位置に表示）
                arView.scene.addAnchor(individualAnchor)

                self.rootEntity = individualAnchor
                self.categoryEntities = categoryMap

                print("loadModel: カテゴリ別エンティティ作成完了")
                for (category, entities) in categoryMap {
                    print("  - \(category): \(entities.count)個のエンティティ")
                }

                // EntityInfoを作成
                let entities = createEntityInfoFromCategoryMap(categoryMap: categoryMap)
                self.allEntities = entities

                // UIを更新
                self.parent.entityHierarchy = entities
                print("loadModel: 全処理完了")

            } catch {
                print("loadModel: エラー - \(error.localizedDescription)")
            }
        }

        // SceneKitノードから個別のRealityKitエンティティを作成
        @MainActor
        private func createIndividualEntitiesFromSceneKit(url: URL, grpObjects: [String: [String]], referenceEntity: ModelEntity) async -> (AnchorEntity, [EntityCategory: [Entity]]) {
            do {
                print("createIndividualEntitiesFromSceneKit: SceneKit解析開始")
                let scene = try SCNScene(url: url, options: nil)

                // アンカーエンティティを作成（元のモデルと同じ位置・スケール）
                let anchor = AnchorEntity(world: [0, 0, -1])

                // 元のモデルのトランスフォームを取得
                let referenceTransform = referenceEntity.transform
                print("createIndividualEntitiesFromSceneKit: リファレンストランスフォーム - position: \(referenceTransform.translation), scale: \(referenceTransform.scale)")

                var categoryMap: [EntityCategory: [Entity]] = [:]

                // SceneKitのノードからRealityKitエンティティを作成
                await processSceneKitNodeStatic(scene.rootNode,
                                         anchor: anchor,
                                         categoryMap: &categoryMap,
                                         grpObjects: grpObjects,
                                         level: 0,
                                         referenceTransform: referenceTransform)

                print("createIndividualEntitiesFromSceneKit: 完了")
                return (anchor, categoryMap)

            } catch {
                print("createIndividualEntitiesFromSceneKit: エラー - \(error.localizedDescription)")
                let anchor = AnchorEntity(world: [0, 0, -1])
                return (anchor, [:])
            }
        }


        // カテゴリマップからEntityInfoを作成
        private func createEntityInfoFromCategoryMap(categoryMap: [EntityCategory: [Entity]]) -> [EntityInfo] {
            var entities: [EntityInfo] = []

            for (category, categoryEntities) in categoryMap {
                for (index, entity) in categoryEntities.enumerated() {
                    let info = EntityInfo(
                        name: "\(entity.name)_\(index)",
                        category: category,
                        level: 1,
                        entity: entity
                    )
                    entities.append(info)
                }
            }

            return entities
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
                category: .root,
                level: 0,
                entity: roomEntity
            )
            var entities = [rootInfo]

            print("📁 room (Root)")
            
            // _grpオブジェクトとその子要素を追加
            for (grpName, children) in grpObjects {
                let lowercaseGrpName = grpName.lowercased()
                
                // =====================================
                // Model_grp (スキップ、子要素のみ処理)
                // =====================================
                if lowercaseGrpName == "model_grp" {
                    print("├─ 📦 Model_grp (スキップ - 子要素\(children.count)個を処理)")
                    
                    // 階層構造を再構築
                    let hierarchy = buildHierarchy(from: children)
                    displayHierarchy(hierarchy, entities: &entities, roomEntity: roomEntity, prefix: "│  ")
                    continue
                }
                
                // =====================================
                // Section_grp (完全スキップ)
                // =====================================
                if lowercaseGrpName == "section_grp" {
                    print("└─ 🚫 Section_grp (スキップ - 子要素\(children.count)個も無視)")
                    continue
                }
                
                // =====================================
                // その他の_grpオブジェクト (通常処理)
                // =====================================
                let grpCategory = categorizeGrpObjectByHierarchy(name: grpName)
                let grpInfo = EntityInfo(
                    name: grpName,
                    category: grpCategory,
                    level: 1,
                    entity: roomEntity
                )
                entities.append(grpInfo)
                
                let icon = grpCategory.icon
                print("├─ \(icon) \(grpName) → \(grpCategory.rawValue)")

                // その子要素を追加（階層に基づいたカテゴリを決定）
                for (index, childName) in children.enumerated() {
                    let isLast = index == children.count - 1
                    let childPrefix = isLast ? "└─" : "├─"
                    
                    let childCategory = categorizeChildObjectByHierarchy(childName: childName, parentName: grpName)
                    let childInfo = EntityInfo(
                        name: childName,
                        category: childCategory,
                        level: 2,
                        entity: roomEntity
                    )
                    entities.append(childInfo)
                    
                    let childIcon = childCategory.icon
                    print("│  \(childPrefix) \(childIcon) \(childName) → \(childCategory.rawValue)")
                }
            }

            print("\n✅ 階層構造処理完了 - 総エンティティ数: \(entities.count)")
            print("📊 カテゴリ分類ルール:")
            print("   📦 Model_grp → スキップ (子要素のみ処理)")
            print("   🏠 Arch_grp → Wall (Wall_*_grp, Wall*, Door* → Wall)")
            print("   🟫 Floor_grp → Floor (Floor* → Floor)")  
            print("   🏪 Storage_grp → storage (Storage* → storage)")
            print("   📺 Television_grp → television (Television* → television)")
            print("   📦 Object_grp → その他")
            print("   🚫 Section_grp → スキップ (完全無視)")
            
            return entities
        }

        // _grpオブジェクトのカテゴリ分け
        private func categorizeGrpObject(name: String) -> EntityCategory {
            let lowercaseName = name.lowercased()

            print("categorizeGrpObject: \(lowercaseName)")

            if lowercaseName.contains("bathtub") || lowercaseName.contains("bath") {
                return .bathtub
            } else if lowercaseName.contains("bed") {
                return .bed
            } else if lowercaseName.contains("chair") || lowercaseName.contains("seat") {
                return .chair
            } else if lowercaseName.contains("dishwasher") {
                return .dishwasher
            } else if lowercaseName.contains("fireplace") || lowercaseName.contains("fire") {
                return .fireplace
            } else if lowercaseName.contains("oven") {
                return .oven
            } else if lowercaseName.contains("refrigerator") || lowercaseName.contains("fridge") || lowercaseName.contains("refrig") {
                return .refrigerator
            } else if lowercaseName.contains("sink") {
                return .sink
            } else if lowercaseName.contains("sofa") || lowercaseName.contains("couch") {
                return .sofa
            } else if lowercaseName.contains("stairs") || lowercaseName.contains("stair") || lowercaseName.contains("step") {
                return .stairs
            } else if lowercaseName.contains("storage") || lowercaseName.contains("cabinet") || lowercaseName.contains("shelf") || lowercaseName.contains("closet") {
                return .storage
            } else if lowercaseName.contains("stove") || lowercaseName.contains("cooktop") {
                return .stove
            } else if lowercaseName.contains("table") || lowercaseName.contains("desk") {
                return .table
            } else if lowercaseName.contains("television") || lowercaseName.contains("tv") {
                return .television
            } else if lowercaseName.contains("toilet") {
                return .toilet
            } else if lowercaseName.contains("washer") || lowercaseName.contains("dryer") || lowercaseName.contains("laundry") {
                return .washerDryer
            } else if lowercaseName.contains("floor") || lowercaseName.contains("wall") || lowercaseName.contains("ceiling") {
                return .other
            }

            // デフォルトは「その他」
            return .other
        }

        private func categorizeGrpObjectByHierarchy(name: String) -> EntityCategory {
            let lowercaseName = name.lowercased()
            
            // 階層構造に基づいた分類
            if lowercaseName.contains("arch") {
                return .wall  // Arch_grpの配下は全てWall
            } else if lowercaseName.contains("floor") {
                return .floor  // Floor_grpの配下は全てFloor
            } else if lowercaseName.contains("object") {
                return .other  // Object_grpは放置（その他扱い）
            }
            
            // Object_grp配下の具体的なオブジェクト分類
            if lowercaseName.contains("storage") {
                return .storage
            } else if lowercaseName.contains("television") || lowercaseName.contains("tv") {
                return .television
            } else if lowercaseName.contains("bathtub") || lowercaseName.contains("bath") {
                return .bathtub
            } else if lowercaseName.contains("bed") {
                return .bed
            } else if lowercaseName.contains("chair") || lowercaseName.contains("seat") {
                return .chair
            } else if lowercaseName.contains("dishwasher") {
                return .dishwasher
            } else if lowercaseName.contains("fireplace") || lowercaseName.contains("fire") {
                return .fireplace
            } else if lowercaseName.contains("oven") {
                return .oven
            } else if lowercaseName.contains("refrigerator") || lowercaseName.contains("fridge") || lowercaseName.contains("refrig") {
                return .refrigerator
            } else if lowercaseName.contains("sink") {
                return .sink
            } else if lowercaseName.contains("sofa") || lowercaseName.contains("couch") {
                return .sofa
            } else if lowercaseName.contains("stairs") || lowercaseName.contains("stair") || lowercaseName.contains("step") {
                return .stairs
            } else if lowercaseName.contains("stove") || lowercaseName.contains("cooktop") {
                return .stove
            } else if lowercaseName.contains("table") || lowercaseName.contains("desk") {
                return .table
            } else if lowercaseName.contains("toilet") {
                return .toilet
            } else if lowercaseName.contains("washer") || lowercaseName.contains("dryer") || lowercaseName.contains("laundry") {
                return .washerDryer
            }

            // デフォルトは「その他」
            return .other
        }

        private func categorizeChildObjectByHierarchy(childName: String, parentName: String) -> EntityCategory {
            let lowercaseParentName = parentName.lowercased()
            
            // 階層構造に基づいた子要素の分類
            // Arch_grp配下（Wall_0_grp, Wall_1_grpなど）の子要素は全てWall
            if lowercaseParentName.contains("arch") || lowercaseParentName.contains("wall") {
                return .wall
            }
            
            // Floor_grp配下の子要素は全てFloor
            if lowercaseParentName.contains("floor") {
                return .floor
            }
            
            // Storage_grp配下の子要素は全てstorage
            if lowercaseParentName.contains("storage") {
                return .storage
            }
            
            // Television_grp配下の子要素は全てtelevision
            if lowercaseParentName.contains("television") || lowercaseParentName.contains("tv") {
                return .television
            }
            
            // その他のObject_grp配下のオブジェクト
            if lowercaseParentName.contains("bathtub") || lowercaseParentName.contains("bath") {
                return .bathtub
            } else if lowercaseParentName.contains("bed") {
                return .bed
            } else if lowercaseParentName.contains("chair") || lowercaseParentName.contains("seat") {
                return .chair
            } else if lowercaseParentName.contains("dishwasher") {
                return .dishwasher
            } else if lowercaseParentName.contains("fireplace") || lowercaseParentName.contains("fire") {
                return .fireplace
            } else if lowercaseParentName.contains("oven") {
                return .oven
            } else if lowercaseParentName.contains("refrigerator") || lowercaseParentName.contains("fridge") || lowercaseParentName.contains("refrig") {
                return .refrigerator
            } else if lowercaseParentName.contains("sink") {
                return .sink
            } else if lowercaseParentName.contains("sofa") || lowercaseParentName.contains("couch") {
                return .sofa
            } else if lowercaseParentName.contains("stairs") || lowercaseParentName.contains("stair") || lowercaseParentName.contains("step") {
                return .stairs
            } else if lowercaseParentName.contains("stove") || lowercaseParentName.contains("cooktop") {
                return .stove
            } else if lowercaseParentName.contains("table") || lowercaseParentName.contains("desk") {
                return .table
            } else if lowercaseParentName.contains("toilet") {
                return .toilet
            } else if lowercaseParentName.contains("washer") || lowercaseParentName.contains("dryer") || lowercaseParentName.contains("laundry") {
                return .washerDryer
            }
            
            // デフォルトは「その他」
            return .other
        }

        private func categorizeDirectChild(name: String) -> EntityCategory {
            let lowercaseName = name.lowercased()
            
            // 子要素の名前から直接判定
            if lowercaseName.contains("television") || lowercaseName == "television0" {
                return .television
            } else if lowercaseName.contains("storage") || lowercaseName == "storage0" || lowercaseName == "storage1" {
                return .storage
            } else if lowercaseName.contains("wall") || lowercaseName == "wall0" || lowercaseName == "wall1" || lowercaseName == "wall2" {
                return .wall
            } else if lowercaseName.contains("floor") || lowercaseName == "floor0" {
                return .floor
            } else if lowercaseName.contains("door") || lowercaseName == "door0" {
                return .wall  // ドアは壁カテゴリに含める
            } else if lowercaseName.contains("bathtub") || lowercaseName.contains("bath") {
                return .bathtub
            } else if lowercaseName.contains("bed") {
                return .bed
            } else if lowercaseName.contains("chair") || lowercaseName.contains("seat") {
                return .chair
            } else if lowercaseName.contains("dishwasher") {
                return .dishwasher
            } else if lowercaseName.contains("fireplace") || lowercaseName.contains("fire") {
                return .fireplace
            } else if lowercaseName.contains("oven") {
                return .oven
            } else if lowercaseName.contains("refrigerator") || lowercaseName.contains("fridge") || lowercaseName.contains("refrig") {
                return .refrigerator
            } else if lowercaseName.contains("sink") {
                return .sink
            } else if lowercaseName.contains("sofa") || lowercaseName.contains("couch") {
                return .sofa
            } else if lowercaseName.contains("stairs") || lowercaseName.contains("stair") || lowercaseName.contains("step") {
                return .stairs
            } else if lowercaseName.contains("stove") || lowercaseName.contains("cooktop") {
                return .stove
            } else if lowercaseName.contains("table") || lowercaseName.contains("desk") {
                return .table
            } else if lowercaseName.contains("toilet") {
                return .toilet
            } else if lowercaseName.contains("washer") || lowercaseName.contains("dryer") || lowercaseName.contains("laundry") {
                return .washerDryer
            }
            
            // デフォルトは「その他」
            return .other
        }

        
        private func inferParentGroup(for childName: String) -> String {
            let lowercaseName = childName.lowercased()
            
            if lowercaseName.contains("television") || lowercaseName == "television0" {
                return "Television_grp"
            } else if lowercaseName.contains("storage") || lowercaseName == "storage0" || lowercaseName == "storage1" {
                return "Storage_grp"
            } else if lowercaseName.contains("wall") || lowercaseName.contains("door") {
                return "Arch_grp"
            } else if lowercaseName.contains("floor") {
                return "Floor_grp"
            }
            
            return ""
        }

        
        // 階層ノード構造
        struct HierarchyNode {
            let name: String
            let category: EntityCategory
            let level: Int
            var children: [HierarchyNode] = []

            var isGroup: Bool {
                return name.lowercased().hasSuffix("_grp")
            }
        }
        
        private func buildHierarchy(from children: [String]) -> [HierarchyNode] {
            var nodes: [HierarchyNode] = []
            var topLevelGroups: [String: HierarchyNode] = [:]
            var subGroups: [String: HierarchyNode] = [:]
            
            // ステップ1: トップレベルグループ（Arch_grp, Floor_grp, Object_grp, Storage_grp, Television_grp）を作成
            for child in children {
                let lowercaseName = child.lowercased()
                if lowercaseName.hasSuffix("_grp") {
                    if lowercaseName == "arch_grp" || lowercaseName == "floor_grp" || 
                       lowercaseName == "object_grp" || lowercaseName == "storage_grp" || 
                       lowercaseName == "television_grp" {
                        let category = categorizeGrpObjectByHierarchy(name: child)
                        let node = HierarchyNode(name: child, category: category, level: 1)
                        topLevelGroups[child] = node
                    } else {
                        // Wall_0_grp, Wall_1_grp などのサブグループ
                        let category = categorizeGrpObjectByHierarchy(name: child)
                        let node = HierarchyNode(name: child, category: category, level: 2)
                        subGroups[child] = node
                    }
                }
            }
            
            // ステップ2: サブグループをトップレベルグループに配置
            for (subGroupName, subGroupNode) in subGroups {
                let lowercaseSubName = subGroupName.lowercased()
                var assigned = false
                
                // Wall_*_grp は Arch_grp の下に配置
                if lowercaseSubName.contains("wall") {
                    if let archGroup = topLevelGroups.first(where: { $0.key.lowercased() == "arch_grp" }) {
                        topLevelGroups[archGroup.key]?.children.append(subGroupNode)
                        assigned = true
                    }
                }
                
                // 他の特定パターンも追加可能
                
                // 割り当てられなかった場合は直接追加
                if !assigned {
                    nodes.append(subGroupNode)
                }
            }
            
            // ステップ3: リーフノード（Wall0, Wall1, Door0, Floor0, Storage0など）を適切な位置に配置
            for child in children {
                if !child.lowercased().hasSuffix("_grp") {
                    let category = categorizeDirectChild(name: child)
                    let childNode = HierarchyNode(name: child, category: category, level: 3)
                    let lowercaseChildName = child.lowercased()
                    var assigned = false
                    
                    // Wall0, Wall1, Wall2, Door0 を Wall_*_grp に配置
                    if lowercaseChildName.contains("wall") || lowercaseChildName.contains("door") {
                        // 適切なWall_*_grpを探す
                        if let archGroup = topLevelGroups.first(where: { $0.key.lowercased() == "arch_grp" }) {
                            // Wall_*_grpの中から適切なものを探す
                            for (index, subGroup) in topLevelGroups[archGroup.key]!.children.enumerated() {
                                let subGroupLower = subGroup.name.lowercased()
                                
                                // Wall0 → Wall_0_grp, Wall1 → Wall_1_grp, Door0/Wall2 → Wall_2_grp
                                if (lowercaseChildName == "wall0" && subGroupLower == "wall_0_grp") ||
                                   (lowercaseChildName == "wall1" && subGroupLower == "wall_1_grp") ||
                                   ((lowercaseChildName == "door0" || lowercaseChildName == "wall2") && subGroupLower == "wall_2_grp") {
                                    topLevelGroups[archGroup.key]?.children[index].children.append(childNode)
                                    assigned = true
                                    break
                                }
                            }
                        }
                    }
                    // Floor0 を Floor_grp に配置
                    else if lowercaseChildName.contains("floor") {
                        if let floorGroup = topLevelGroups.first(where: { $0.key.lowercased() == "floor_grp" }) {
                            topLevelGroups[floorGroup.key]?.children.append(childNode)
                            assigned = true
                        }
                    }
                    // Storage0, Storage1 を Storage_grp に配置
                    else if lowercaseChildName.contains("storage") {
                        if let storageGroup = topLevelGroups.first(where: { $0.key.lowercased() == "storage_grp" }) {
                            topLevelGroups[storageGroup.key]?.children.append(childNode)
                            assigned = true
                        }
                    }
                    // Television0 を Television_grp に配置
                    else if lowercaseChildName.contains("television") {
                        if let tvGroup = topLevelGroups.first(where: { $0.key.lowercased() == "television_grp" }) {
                            topLevelGroups[tvGroup.key]?.children.append(childNode)
                            assigned = true
                        }
                    }
                    
                    // どこにも割り当てられなかった場合は直接追加
                    if !assigned {
                        nodes.append(childNode)
                    }
                }
            }
            
            // ステップ4: トップレベルグループを最終リストに追加（順序を保つ）
            let groupOrder = ["Arch_grp", "Floor_grp", "Object_grp", "Storage_grp", "Television_grp"]
            for groupName in groupOrder {
                if let group = topLevelGroups.first(where: { $0.key == groupName }) {
                    nodes.append(group.value)
                }
            }
            
            return nodes
        }
        
        private func displayHierarchy(_ nodes: [HierarchyNode], entities: inout [EntityInfo], roomEntity: ModelEntity, prefix: String) {
            for (index, node) in nodes.enumerated() {
                let isLastNode = index == nodes.count - 1
                let nodePrefix = isLastNode ? "└─" : "├─"
                let childPrefix = prefix + (isLastNode ? "   " : "│  ")
                
                let icon = node.category.icon
                print("\(prefix)\(nodePrefix) \(icon) \(node.name) → \(node.category.rawValue)")
                
                // エンティティに追加
                let entityInfo = EntityInfo(
                    name: node.name,
                    category: node.category,
                    level: node.level,
                    entity: roomEntity
                )
                entities.append(entityInfo)
                
                // 子ノードがある場合は再帰的に表示（真の再帰）
                if !node.children.isEmpty {
                    displayHierarchy(node.children, entities: &entities, roomEntity: roomEntity, prefix: childPrefix)
                }
            }
        }
        
        // この関数は削除 - displayHierarchyが真の再帰関数として統合処理

        // 子オブジェクトのカテゴリ分け
        private func categorizeChildObject(name: String, parentCategory: EntityCategory) -> EntityCategory {
            // 全ての_grpオブジェクトの子要素は親のカテゴリを継承
            return parentCategory
        }

        // 全エンティティの元のTransform値を保存
        private func saveOriginalTransforms(entity: Entity) {
            let identifier = ObjectIdentifier(entity)
            originalTransforms[identifier] = entity.transform
            
            for child in entity.children {
                saveOriginalTransforms(entity: child)
            }
        }

        func updateVisibility(selectedCategories: Set<EntityCategory>) {
            guard let rootEntity = self.rootEntity else {
                print("updateVisibility: rootEntity is nil")
                return
            }

            print("\n========== updateVisibility 開始 ==========")
            print("updateVisibility: 選択されたカテゴリ: \(selectedCategories)")

            // 全てのエンティティの実際の表示/非表示を制御
            updateVisibilityByCategory(rootEntity: rootEntity, selectedCategories: selectedCategories)

            print("========== updateVisibility 完了 ==========\n")
        }

        private func updateVisibilityByCategory(rootEntity: Entity, selectedCategories: Set<EntityCategory>) {
            print("=== カテゴリ別表示制御開始 ===")
            print("選択されたカテゴリ: \(selectedCategories)")

            // 各カテゴリのエンティティを制御
            for (category, entities) in categoryEntities {
                let shouldShow = selectedCategories.contains(category)
                print("カテゴリ '\(category.rawValue)': \(shouldShow ? "表示" : "非表示") (\(entities.count)個のエンティティ)")

                for entity in entities {
                    setEntityVisibilitySafe(entity, isVisible: shouldShow)
                }
            }

            print("=== カテゴリ別表示制御完了 ===")
        }

        // 実際のエンティティ階層を走査してカテゴリマップを作成
        private func createEntityCategoryMap(entity: Entity, map: inout [EntityCategory: [Entity]]) {
            createEntityCategoryMapWithPath(entity: entity, map: &map, path: [])
        }

        // パス情報を保持しながらエンティティをマッピング
        private func createEntityCategoryMapWithPath(entity: Entity, map: inout [EntityCategory: [Entity]], path: [String]) {
            let entityName = entity.name.isEmpty ? "unnamed" : entity.name
            let currentPath = path + [entityName]

            // 階層パスからカテゴリを判定
            let category = determineCategoryFromPath(currentPath)

            // エンティティがModelComponentを持つ場合のみマップに追加（実際に描画されるもの）
            if entity.components.has(ModelComponent.self) {
                if map[category] == nil {
                    map[category] = []
                }
                map[category]?.append(entity)
                print("  マッピング: \(entityName) -> \(category.rawValue) (path: \(currentPath.joined(separator: "/")))")
            }

            // 子エンティティも再帰的に処理（重要：確実に全子エンティティを走査）
            print("  エンティティ \(entityName) の子要素: \(entity.children.count)個")
            for (index, child) in entity.children.enumerated() {
                print("    [子\(index)] \(child.name.isEmpty ? "unnamed" : child.name)")
                createEntityCategoryMapWithPath(entity: child, map: &map, path: currentPath)
            }
        }

        // パス情報からカテゴリを判定（より高精度）
        private func determineCategoryFromPath(_ path: [String]) -> EntityCategory {
            let pathString = path.joined(separator: "/").lowercased()
            let currentName = path.last?.lowercased() ?? ""

            // パス全体から階層構造を解析（より具体的なものを先に判定）
            if pathString.contains("storage") {
                return .storage
            } else if pathString.contains("television") || pathString.contains("tv") {
                return .television
            } else if pathString.contains("arch") || pathString.contains("door") {
                return .wall
            } else if pathString.contains("wall") && !pathString.contains("storage") {
                return .wall
            } else if pathString.contains("floor") {
                return .floor
            }

            // 現在の名前から直接判定
            return determineEntityCategory(name: currentName)
        }

        // エンティティ名からカテゴリを判定（より堅牢な実装）
        private func determineEntityCategory(name: String) -> EntityCategory {
            let lowercaseName = name.lowercased()

            // より具体的なカテゴリを先に判定（確実性の高いもの）
            if lowercaseName.contains("storage") {
                return .storage
            } else if lowercaseName.contains("television") || lowercaseName.contains("tv") {
                return .television
            } else if lowercaseName.contains("door") || lowercaseName.contains("arch") {
                return .wall
            } else if lowercaseName.contains("wall") && !lowercaseName.contains("storage") {
                return .wall
            } else if lowercaseName.contains("floor") {
                return .floor
            }

            // 標準的な家具・設備の判定
            else if lowercaseName.contains("bathtub") || lowercaseName.contains("bath") {
                return .bathtub
            } else if lowercaseName.contains("bed") {
                return .bed
            } else if lowercaseName.contains("chair") || lowercaseName.contains("seat") {
                return .chair
            } else if lowercaseName.contains("dishwasher") {
                return .dishwasher
            } else if lowercaseName.contains("fireplace") || lowercaseName.contains("fire") {
                return .fireplace
            } else if lowercaseName.contains("oven") {
                return .oven
            } else if lowercaseName.contains("refrigerator") || lowercaseName.contains("fridge") || lowercaseName.contains("refrig") {
                return .refrigerator
            } else if lowercaseName.contains("sink") {
                return .sink
            } else if lowercaseName.contains("sofa") || lowercaseName.contains("couch") {
                return .sofa
            } else if lowercaseName.contains("stairs") || lowercaseName.contains("stair") || lowercaseName.contains("step") {
                return .stairs
            } else if lowercaseName.contains("stove") || lowercaseName.contains("cooktop") {
                return .stove
            } else if lowercaseName.contains("table") || lowercaseName.contains("desk") {
                return .table
            } else if lowercaseName.contains("toilet") {
                return .toilet
            } else if lowercaseName.contains("washer") || lowercaseName.contains("dryer") || lowercaseName.contains("laundry") {
                return .washerDryer
            }

            // 特殊なケース: 複雑な名前は親エンティティから推測
            return inferCategoryFromParentContext(entityName: name)
        }

        // 親エンティティのコンテキストからカテゴリを推測
        private func inferCategoryFromParentContext(entityName: String) -> EntityCategory {
            // allEntitiesからこのエンティティに関連する情報を探索
            for entityInfo in allEntities {
                if entityName.contains(entityInfo.name) || entityInfo.name.contains(entityName) {
                    if entityInfo.category != .other {
                        return entityInfo.category
                    }
                }
            }
            return .other
        }

        // より安全なエンティティ可視性制御（Transform scaling を避ける）
        private func setEntityVisibilitySafe(_ entity: Entity, isVisible: Bool) {
            let identifier = ObjectIdentifier(entity)
            entityVisibilityState[identifier] = isVisible
            
            // 方法1: OpacityComponentでの制御 (主要な方法)
            if isVisible {
                entity.components.remove(OpacityComponent.self)
            } else {
                entity.components.set(OpacityComponent(opacity: 0.0))
            }

            // 方法2: isEnabledでの制御 (補助)
            entity.isEnabled = isVisible

            print("    -> エンティティ制御: \(entity.name) visible=\(isVisible)")

            // 子エンティティにも適用
            for child in entity.children {
                setEntityVisibilitySafe(child, isVisible: isVisible)
            }
        }

        private func printEntityHierarchy(_ entity: Entity, level: Int) {
            let indent = String(repeating: "  ", count: level)
            let name = entity.name.isEmpty ? "unnamed" : entity.name
            let hasModel = entity.components.has(ModelComponent.self)
            let _ = entity.components.has(OpacityComponent.self)
            let opacityValue = entity.components[OpacityComponent.self]?.opacity ?? 1.0

            print("\(indent)- \(name) (enabled: \(entity.isEnabled), model: \(hasModel), opacity: \(opacityValue))")

            for child in entity.children {
                printEntityHierarchy(child, level: level + 1)
            }
        }

        private func printCompleteEntityHierarchy(_ entity: Entity, level: Int) {
            let indent = String(repeating: "  ", count: level)
            let name = entity.name.isEmpty ? "unnamed" : entity.name
            let hasModel = entity.components.has(ModelComponent.self)
            let category = determineEntityCategory(name: name)

            print("\(indent)[\(level)] \(name) -> カテゴリ: \(category) (ModelComponent: \(hasModel))")

            for child in entity.children {
                printCompleteEntityHierarchy(child, level: level + 1)
            }
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

// 静的関数：SceneKitノードを再帰的に処理してRealityKitエンティティに変換
@MainActor
private func processSceneKitNodeStatic(_ node: SCNNode,
                                     anchor: AnchorEntity,
                                     categoryMap: inout [EntityCategory: [Entity]],
                                     grpObjects: [String: [String]],
                                     level: Int,
                                     referenceTransform: Transform) async {
    let nodeName = node.name ?? "unnamed"
    let indent = String(repeating: "  ", count: level)

    // ジオメトリを持つノードのみRealityKitエンティティに変換
    if let geometry = node.geometry {
        print("\(indent)ジオメトリノード発見: \(nodeName)")

        // カテゴリを判定
        let category = determineCategoryFromSceneKitNodeStatic(node, grpObjects: grpObjects)
        print("\(indent)  -> カテゴリ: \(category)")

        // RealityKitエンティティを作成（ワールド座標系を使用）
        if let entity = createRealityKitEntityFromGeometryStatic(geometry, nodeName: nodeName, transform: node.worldTransform, referenceTransform: referenceTransform) {
            anchor.addChild(entity)

            // カテゴリマップに追加
            if categoryMap[category] == nil {
                categoryMap[category] = []
            }
            categoryMap[category]?.append(entity)
            print("\(indent)  -> エンティティ作成完了")
        } else {
            print("\(indent)  -> エンティティ作成失敗: \(nodeName)")
        }
    }

    // 子ノードを再帰的に処理
    for childNode in node.childNodes {
        await processSceneKitNodeStatic(childNode,
                                anchor: anchor,
                                categoryMap: &categoryMap,
                                grpObjects: grpObjects,
                                level: level + 1,
                                referenceTransform: referenceTransform)
    }
}

// 静的関数：SceneKitのジオメトリからRealityKitエンティティを作成
@MainActor
private func createRealityKitEntityFromGeometryStatic(_ geometry: SCNGeometry, nodeName: String, transform: SCNMatrix4, referenceTransform: Transform) -> Entity? {
    do {
        print("    -> エンティティ作成開始: \(nodeName)")

        // ModelEntityを作成
        let entity = Entity()
        entity.name = nodeName

        // SceneKitのTransformをsimd_float4x4に変換
        let sceneKitMatrix = simd_float4x4(
            simd_float4(Float(transform.m11), Float(transform.m12), Float(transform.m13), Float(transform.m14)),
            simd_float4(Float(transform.m21), Float(transform.m22), Float(transform.m23), Float(transform.m24)),
            simd_float4(Float(transform.m31), Float(transform.m32), Float(transform.m33), Float(transform.m34)),
            simd_float4(Float(transform.m41), Float(transform.m42), Float(transform.m43), Float(transform.m44))
        )

        // リファレンスのスケールを適用
        var finalTransform = Transform(matrix: sceneKitMatrix)
        finalTransform.scale = finalTransform.scale * referenceTransform.scale

        // リファレンスの位置オフセットを適用（必要に応じて）
        // finalTransform.translation += referenceTransform.translation

        entity.transform = finalTransform
        print("    -> Transform設定完了 - position: \(finalTransform.translation), scale: \(finalTransform.scale)")

        // SceneKitジオメトリをRealityKitのMeshResourceに変換
        let meshResource = try convertSCNGeometryToMeshResource(geometry)
        print("    -> SCNGeometry->MeshResource変換完了")

        // マテリアルを作成（SCNGeometryのマテリアルから変換）
        let materials = convertSCNMaterialsToRealityKitMaterials(geometry.materials)
        print("    -> マテリアル変換完了")

        let modelComponent = ModelComponent(mesh: meshResource, materials: materials)
        entity.components.set(modelComponent)

        print("    -> ModelComponent設定完了: \(nodeName)")
        return entity

    } catch {
        print("    -> エラー: エンティティ作成失敗 \(nodeName) - \(error.localizedDescription)")
        // フォールバックとして簡単な形状を作成
        return createFallbackEntity(nodeName: nodeName, transform: transform, referenceTransform: referenceTransform)
    }
}

// SceneKitジオメトリをRealityKitのMeshResourceに変換
@MainActor
private func convertSCNGeometryToMeshResource(_ geometry: SCNGeometry) throws -> MeshResource {
    // SCNGeometryの頂点データとインデックスデータを取得
    let geometrySource = geometry.sources(for: .vertex).first
    let geometryElement = geometry.elements.first

    guard let source = geometrySource,
          let element = geometryElement else {
        throw NSError(domain: "GeometryConversion", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid geometry data"])
    }

    let data = source.data

    // 頂点データの解析
    let stride = source.bytesPerComponent * source.componentsPerVector
    let vertexCount = source.vectorCount

    var positions: [SIMD3<Float>] = []

    // Float32データとして読み込み
    data.withUnsafeBytes { rawBuffer in
        for i in 0..<vertexCount {
            let offset = i * stride
            let x = rawBuffer.load(fromByteOffset: offset, as: Float.self)
            let y = rawBuffer.load(fromByteOffset: offset + 4, as: Float.self)
            let z = rawBuffer.load(fromByteOffset: offset + 8, as: Float.self)
            positions.append(SIMD3<Float>(x, y, z))
        }
    }

    // インデックスデータの解析
    var indices: [UInt32] = []
    let indexData = element.data
    let indexCount = element.primitiveCount * 3 // 三角形前提
    indexData.withUnsafeBytes { rawBuffer in
        for i in 0..<indexCount {
            let index = rawBuffer.load(fromByteOffset: i * MemoryLayout<UInt32>.size, as: UInt32.self)
            indices.append(index)
        }
    }

    // MeshResourceを作成
    var descriptor = MeshDescriptor()
    descriptor.positions = MeshBuffer(positions)
    descriptor.primitives = .triangles(indices)

    return try MeshResource.generate(from: [descriptor])
}

// SCNMaterialをRealityKitマテリアルに変換
@MainActor
private func convertSCNMaterialsToRealityKitMaterials(_ scnMaterials: [SCNMaterial]) -> [RealityKit.Material] {
    if scnMaterials.isEmpty {
        // デフォルトマテリアル
        var material = SimpleMaterial()
        material.color = .init(tint: UIColor.systemBlue)
        material.roughness = .init(floatLiteral: 0.3)
        return [material]
    }

    return scnMaterials.map { scnMaterial in
        var material = SimpleMaterial()

        // Diffuseカラーを変換
        if let diffuse = scnMaterial.diffuse.contents as? UIColor {
            material.color = .init(tint: diffuse)
        } else {
            material.color = .init(tint: UIColor.systemBlue)
        }

        // その他のプロパティも変換可能
        // material.roughness = ...
        // material.metallic = ...

        return material
    }
}

// フォールバック用のシンプルなエンティティを作成
@MainActor
private func createFallbackEntity(nodeName: String, transform: SCNMatrix4, referenceTransform: Transform) -> Entity? {
    do {
        let entity = Entity()
        entity.name = nodeName

        let sceneKitMatrix = simd_float4x4(
            simd_float4(Float(transform.m11), Float(transform.m12), Float(transform.m13), Float(transform.m14)),
            simd_float4(Float(transform.m21), Float(transform.m22), Float(transform.m23), Float(transform.m24)),
            simd_float4(Float(transform.m31), Float(transform.m32), Float(transform.m33), Float(transform.m34)),
            simd_float4(Float(transform.m41), Float(transform.m42), Float(transform.m43), Float(transform.m44))
        )
        var finalTransform = Transform(matrix: sceneKitMatrix)
        finalTransform.scale = finalTransform.scale * referenceTransform.scale
        entity.transform = finalTransform

        var material = SimpleMaterial()
        material.color = .init(tint: UIColor.systemRed) // フォールバックは赤色

        let meshResource = try MeshResource.generateBox(size: [0.1, 0.1, 0.1])
        let modelComponent = ModelComponent(mesh: meshResource, materials: [material])
        entity.components.set(modelComponent)

        return entity
    } catch {
        return nil
    }
}

// 静的関数：SceneKitノードからカテゴリを判定
private func determineCategoryFromSceneKitNodeStatic(_ node: SCNNode, grpObjects: [String: [String]]) -> EntityCategory {
    let nodeName = node.name ?? "unnamed"

    // 直接的な名前判定
    let directCategory = categorizeDirectChildStatic(name: nodeName)
    if directCategory != .other {
        return directCategory
    }

    // 親ノードから推測
    // まず全ての親階層を収集してStorage0/Storage1があるかチェック
    var allParentNames: [String] = []
    var currentNode: SCNNode? = node
    while let parentNode = currentNode?.parent {
        if let parentName = parentNode.name {
            allParentNames.append(parentName)
        }
        currentNode = parentNode
    }

    // Storage0/Storage1が親階層にあればstorageカテゴリ
    for parentName in allParentNames {
        let lowercaseName = parentName.lowercased()
        if lowercaseName == "storage0" || lowercaseName == "storage1" || lowercaseName.contains("storage_grp") {
            return .storage
        }
    }

    // 通常の親ノード判定（最も近い親から順に）
    for parentName in allParentNames {
        let parentCategory = categorizeGrpObjectByHierarchyStatic(name: parentName)
        if parentCategory != .other {
            return parentCategory
        }
    }

    return .other
}

// 静的関数：分類ロジック
private func categorizeDirectChildStatic(name: String) -> EntityCategory {
    let lowercaseName = name.lowercased()

    // 子要素の名前から直接判定（より具体的なものを先に）
    if lowercaseName.contains("storage") || lowercaseName == "storage0" || lowercaseName == "storage1" {
        return .storage
    } else if lowercaseName.contains("television") || lowercaseName == "television0" {
        return .television
    } else if lowercaseName.contains("door") || lowercaseName == "door0" {
        return .wall  // ドアは壁カテゴリに含める
    } else if lowercaseName.contains("wall") && !lowercaseName.contains("storage") {
        return .wall
    } else if lowercaseName == "wall0" || lowercaseName == "wall1" || lowercaseName == "wall2" {
        return .wall
    } else if lowercaseName.contains("floor") || lowercaseName == "floor0" {
        return .floor
    } else if lowercaseName.contains("bathtub") || lowercaseName.contains("bath") {
        return .bathtub
    } else if lowercaseName.contains("bed") {
        return .bed
    } else if lowercaseName.contains("chair") || lowercaseName.contains("seat") {
        return .chair
    } else if lowercaseName.contains("dishwasher") {
        return .dishwasher
    } else if lowercaseName.contains("fireplace") || lowercaseName.contains("fire") {
        return .fireplace
    } else if lowercaseName.contains("oven") {
        return .oven
    } else if lowercaseName.contains("refrigerator") || lowercaseName.contains("fridge") || lowercaseName.contains("refrig") {
        return .refrigerator
    } else if lowercaseName.contains("sink") {
        return .sink
    } else if lowercaseName.contains("sofa") || lowercaseName.contains("couch") {
        return .sofa
    } else if lowercaseName.contains("stairs") || lowercaseName.contains("stair") || lowercaseName.contains("step") {
        return .stairs
    } else if lowercaseName.contains("stove") || lowercaseName.contains("cooktop") {
        return .stove
    } else if lowercaseName.contains("table") || lowercaseName.contains("desk") {
        return .table
    } else if lowercaseName.contains("toilet") {
        return .toilet
    } else if lowercaseName.contains("washer") || lowercaseName.contains("dryer") || lowercaseName.contains("laundry") {
        return .washerDryer
    }

    // デフォルトは「その他」
    return .other
}

// 静的関数：階層に基づく分類
private func categorizeGrpObjectByHierarchyStatic(name: String) -> EntityCategory {
    let lowercaseName = name.lowercased()

    // より具体的なカテゴリを先に判定
    if lowercaseName.contains("storage") {
        return .storage
    } else if lowercaseName.contains("television") || lowercaseName.contains("tv") {
        return .television
    }

    // 階層構造に基づいた分類
    if lowercaseName.contains("arch") {
        return .wall  // Arch_grpの配下は全てWall
    } else if lowercaseName.contains("floor") {
        return .floor  // Floor_grpの配下は全てFloor
    } else if lowercaseName.contains("object") {
        return .other  // Object_grpは放置（その他扱い）
    }

    // Object_grp配下の具体的なオブジェクト分類（上記で判定済み）
    if lowercaseName.contains("bathtub") || lowercaseName.contains("bath") {
        return .bathtub
    } else if lowercaseName.contains("bed") {
        return .bed
    } else if lowercaseName.contains("chair") || lowercaseName.contains("seat") {
        return .chair
    } else if lowercaseName.contains("dishwasher") {
        return .dishwasher
    } else if lowercaseName.contains("fireplace") || lowercaseName.contains("fire") {
        return .fireplace
    } else if lowercaseName.contains("oven") {
        return .oven
    } else if lowercaseName.contains("refrigerator") || lowercaseName.contains("fridge") || lowercaseName.contains("refrig") {
        return .refrigerator
    } else if lowercaseName.contains("sink") {
        return .sink
    } else if lowercaseName.contains("sofa") || lowercaseName.contains("couch") {
        return .sofa
    } else if lowercaseName.contains("stairs") || lowercaseName.contains("stair") || lowercaseName.contains("step") {
        return .stairs
    } else if lowercaseName.contains("stove") || lowercaseName.contains("cooktop") {
        return .stove
    } else if lowercaseName.contains("table") || lowercaseName.contains("desk") {
        return .table
    } else if lowercaseName.contains("toilet") {
        return .toilet
    } else if lowercaseName.contains("washer") || lowercaseName.contains("dryer") || lowercaseName.contains("laundry") {
        return .washerDryer
    }

    // デフォルトは「その他」
    return .other
}