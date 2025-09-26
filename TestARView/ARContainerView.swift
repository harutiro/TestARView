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
                
                let icon = getIconForCategory(grpCategory)
                print("├─ \(icon) \(grpName) → \(grpCategory)")

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
                    
                    let childIcon = getIconForCategory(childCategory)
                    print("│  \(childPrefix) \(childIcon) \(childName) → \(childCategory)")
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
        private func categorizeGrpObject(name: String) -> String {
            let lowercaseName = name.lowercased()

            print("categorizeGrpObject: \(lowercaseName)")

            if lowercaseName.contains("bathtub") || lowercaseName.contains("bath") {
                return "bathtub"
            } else if lowercaseName.contains("bed") {
                return "bed"
            } else if lowercaseName.contains("chair") || lowercaseName.contains("seat") {
                return "chair"
            } else if lowercaseName.contains("dishwasher") {
                return "dishwasher"
            } else if lowercaseName.contains("fireplace") || lowercaseName.contains("fire") {
                return "fireplace"
            } else if lowercaseName.contains("oven") {
                return "oven"
            } else if lowercaseName.contains("refrigerator") || lowercaseName.contains("fridge") || lowercaseName.contains("refrig") {
                return "refrigerator"
            } else if lowercaseName.contains("sink") {
                return "sink"
            } else if lowercaseName.contains("sofa") || lowercaseName.contains("couch") {
                return "sofa"
            } else if lowercaseName.contains("stairs") || lowercaseName.contains("stair") || lowercaseName.contains("step") {
                return "stairs"
            } else if lowercaseName.contains("storage") || lowercaseName.contains("cabinet") || lowercaseName.contains("shelf") || lowercaseName.contains("closet") {
                return "storage"
            } else if lowercaseName.contains("stove") || lowercaseName.contains("cooktop") {
                return "stove"
            } else if lowercaseName.contains("table") || lowercaseName.contains("desk") {
                return "table"
            } else if lowercaseName.contains("television") || lowercaseName.contains("tv") {
                return "television"
            } else if lowercaseName.contains("toilet") {
                return "toilet"
            } else if lowercaseName.contains("washer") || lowercaseName.contains("dryer") || lowercaseName.contains("laundry") {
                return "washerDryer"
            } else if lowercaseName.contains("floor") || lowercaseName.contains("wall") || lowercaseName.contains("ceiling") {
                return "その他"
            }

            // デフォルトは「その他」
            return "その他"
        }

        private func categorizeGrpObjectByHierarchy(name: String) -> String {
            let lowercaseName = name.lowercased()
            
            // 階層構造に基づいた分類
            if lowercaseName.contains("arch") {
                return "Wall"  // Arch_grpの配下は全てWall
            } else if lowercaseName.contains("floor") {
                return "Floor"  // Floor_grpの配下は全てFloor
            } else if lowercaseName.contains("object") {
                return "その他"  // Object_grpは放置（その他扱い）
            }
            
            // Object_grp配下の具体的なオブジェクト分類
            if lowercaseName.contains("storage") {
                return "storage"
            } else if lowercaseName.contains("television") || lowercaseName.contains("tv") {
                return "television"
            } else if lowercaseName.contains("bathtub") || lowercaseName.contains("bath") {
                return "bathtub"
            } else if lowercaseName.contains("bed") {
                return "bed"
            } else if lowercaseName.contains("chair") || lowercaseName.contains("seat") {
                return "chair"
            } else if lowercaseName.contains("dishwasher") {
                return "dishwasher"
            } else if lowercaseName.contains("fireplace") || lowercaseName.contains("fire") {
                return "fireplace"
            } else if lowercaseName.contains("oven") {
                return "oven"
            } else if lowercaseName.contains("refrigerator") || lowercaseName.contains("fridge") || lowercaseName.contains("refrig") {
                return "refrigerator"
            } else if lowercaseName.contains("sink") {
                return "sink"
            } else if lowercaseName.contains("sofa") || lowercaseName.contains("couch") {
                return "sofa"
            } else if lowercaseName.contains("stairs") || lowercaseName.contains("stair") || lowercaseName.contains("step") {
                return "stairs"
            } else if lowercaseName.contains("stove") || lowercaseName.contains("cooktop") {
                return "stove"
            } else if lowercaseName.contains("table") || lowercaseName.contains("desk") {
                return "table"
            } else if lowercaseName.contains("toilet") {
                return "toilet"
            } else if lowercaseName.contains("washer") || lowercaseName.contains("dryer") || lowercaseName.contains("laundry") {
                return "washerDryer"
            }

            // デフォルトは「その他」
            return "その他"
        }

        private func categorizeChildObjectByHierarchy(childName: String, parentName: String) -> String {
            let lowercaseParentName = parentName.lowercased()
            
            // 階層構造に基づいた子要素の分類
            // Arch_grp配下（Wall_0_grp, Wall_1_grpなど）の子要素は全てWall
            if lowercaseParentName.contains("arch") || lowercaseParentName.contains("wall") {
                return "Wall"
            }
            
            // Floor_grp配下の子要素は全てFloor
            if lowercaseParentName.contains("floor") {
                return "Floor"
            }
            
            // Storage_grp配下の子要素は全てstorage
            if lowercaseParentName.contains("storage") {
                return "storage"
            }
            
            // Television_grp配下の子要素は全てtelevision
            if lowercaseParentName.contains("television") || lowercaseParentName.contains("tv") {
                return "television"
            }
            
            // その他のObject_grp配下のオブジェクト
            if lowercaseParentName.contains("bathtub") || lowercaseParentName.contains("bath") {
                return "bathtub"
            } else if lowercaseParentName.contains("bed") {
                return "bed"
            } else if lowercaseParentName.contains("chair") || lowercaseParentName.contains("seat") {
                return "chair"
            } else if lowercaseParentName.contains("dishwasher") {
                return "dishwasher"
            } else if lowercaseParentName.contains("fireplace") || lowercaseParentName.contains("fire") {
                return "fireplace"
            } else if lowercaseParentName.contains("oven") {
                return "oven"
            } else if lowercaseParentName.contains("refrigerator") || lowercaseParentName.contains("fridge") || lowercaseParentName.contains("refrig") {
                return "refrigerator"
            } else if lowercaseParentName.contains("sink") {
                return "sink"
            } else if lowercaseParentName.contains("sofa") || lowercaseParentName.contains("couch") {
                return "sofa"
            } else if lowercaseParentName.contains("stairs") || lowercaseParentName.contains("stair") || lowercaseParentName.contains("step") {
                return "stairs"
            } else if lowercaseParentName.contains("stove") || lowercaseParentName.contains("cooktop") {
                return "stove"
            } else if lowercaseParentName.contains("table") || lowercaseParentName.contains("desk") {
                return "table"
            } else if lowercaseParentName.contains("toilet") {
                return "toilet"
            } else if lowercaseParentName.contains("washer") || lowercaseParentName.contains("dryer") || lowercaseParentName.contains("laundry") {
                return "washerDryer"
            }
            
            // デフォルトは「その他」
            return "その他"
        }

        private func categorizeDirectChild(name: String) -> String {
            let lowercaseName = name.lowercased()
            
            // 子要素の名前から直接判定
            if lowercaseName.contains("television") || lowercaseName == "television0" {
                return "television"
            } else if lowercaseName.contains("storage") || lowercaseName == "storage0" || lowercaseName == "storage1" {
                return "storage"
            } else if lowercaseName.contains("wall") || lowercaseName == "wall0" || lowercaseName == "wall1" || lowercaseName == "wall2" {
                return "Wall"
            } else if lowercaseName.contains("floor") || lowercaseName == "floor0" {
                return "Floor"
            } else if lowercaseName.contains("door") || lowercaseName == "door0" {
                return "Wall"  // ドアは壁カテゴリに含める
            } else if lowercaseName.contains("bathtub") || lowercaseName.contains("bath") {
                return "bathtub"
            } else if lowercaseName.contains("bed") {
                return "bed"
            } else if lowercaseName.contains("chair") || lowercaseName.contains("seat") {
                return "chair"
            } else if lowercaseName.contains("dishwasher") {
                return "dishwasher"
            } else if lowercaseName.contains("fireplace") || lowercaseName.contains("fire") {
                return "fireplace"
            } else if lowercaseName.contains("oven") {
                return "oven"
            } else if lowercaseName.contains("refrigerator") || lowercaseName.contains("fridge") || lowercaseName.contains("refrig") {
                return "refrigerator"
            } else if lowercaseName.contains("sink") {
                return "sink"
            } else if lowercaseName.contains("sofa") || lowercaseName.contains("couch") {
                return "sofa"
            } else if lowercaseName.contains("stairs") || lowercaseName.contains("stair") || lowercaseName.contains("step") {
                return "stairs"
            } else if lowercaseName.contains("stove") || lowercaseName.contains("cooktop") {
                return "stove"
            } else if lowercaseName.contains("table") || lowercaseName.contains("desk") {
                return "table"
            } else if lowercaseName.contains("toilet") {
                return "toilet"
            } else if lowercaseName.contains("washer") || lowercaseName.contains("dryer") || lowercaseName.contains("laundry") {
                return "washerDryer"
            }
            
            // デフォルトは「その他」
            return "その他"
        }

        private func getIconForCategory(_ category: String) -> String {
            switch category {
            case "Wall": return "🏠"
            case "Floor": return "🟫"
            case "storage": return "🏪"
            case "television": return "📺"
            case "bathtub": return "🛁"
            case "bed": return "🛏️"
            case "chair": return "🪑"
            case "dishwasher": return "🍽️"
            case "fireplace": return "🔥"
            case "oven": return "🔥"
            case "refrigerator": return "❄️"
            case "sink": return "🚰"
            case "sofa": return "🛋️"
            case "stairs": return "🪜"
            case "stove": return "🔥"
            case "table": return "🪑"
            case "toilet": return "🚽"
            case "washerDryer": return "🧽"
            case "Root": return "📁"
            default: return "📦"
            }
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
            let category: String
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
                
                let icon = getIconForCategory(node.category)
                print("\(prefix)\(nodePrefix) \(icon) \(node.name) → \(node.category)")
                
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
        private func categorizeChildObject(name: String, parentCategory: String) -> String {
            // 全ての_grpオブジェクトの子要素は親のカテゴリを継承
            return parentCategory
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