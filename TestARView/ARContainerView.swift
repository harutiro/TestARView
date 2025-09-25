//
//  ARContainerView.swift
//  TestARView
//
//  Created by Assistant on R 7/09/26.
//

import SwiftUI
import RealityKit
import ARKit

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

            // 簡単なサンプルオブジェクトを作成
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

            // テーブル
            let tableMesh = MeshResource.generateBox(width: 1, height: 0.1, depth: 0.6)
            let tableEntity = ModelEntity(mesh: tableMesh)
            tableEntity.name = "Table"
            tableEntity.position = [0, 0.3, 0]
            anchor.addChild(tableEntity)

            // 椅子
            let chairMesh = MeshResource.generateBox(width: 0.4, height: 0.4, depth: 0.4)
            let chairEntity = ModelEntity(mesh: chairMesh)
            chairEntity.name = "Chair"
            chairEntity.position = [0, 0.2, 0.8]
            anchor.addChild(chairEntity)

            arView.scene.addAnchor(anchor)
            self.rootEntity = anchor
            
            // エンティティの強い参照を保持
            self.entityReferences = [floorEntity, wallEntity, tableEntity, chairEntity]
            
            print("loadModel: 3Dオブジェクト作成完了")

            // エンティティ情報を作成
            let entities = [
                EntityInfo(name: "Floor", category: "床", level: 0, entity: floorEntity),
                EntityInfo(name: "Wall", category: "壁", level: 0, entity: wallEntity),
                EntityInfo(name: "Table", category: "家具", level: 0, entity: tableEntity),
                EntityInfo(name: "Chair", category: "家具", level: 0, entity: chairEntity)
            ]
            
            self.allEntities = entities
            print("loadModel: allEntities設定完了 - 数: \(entities.count)")
            print("loadModel: エンティティ詳細:")
            for entity in entities {
                print("  - \(entity.name): \(entity.category)")
                print("    entity is nil: \(entity.entity == nil)")
            }

            // UIを更新（メインスレッドで実行）
            await MainActor.run {
                print("loadModel: UI更新開始 - parent.entityHierarchy更新予定")
                self.parent.entityHierarchy = entities
                print("loadModel: parent.entityHierarchy更新完了 - 数: \(self.parent.entityHierarchy.count)")
                print("loadModel: 最終確認 - parent.entityHierarchy内容:")
                for entity in self.parent.entityHierarchy {
                    print("  - \(entity.name): \(entity.category)")
                    print("    entity is nil: \(entity.entity == nil)")
                }
            }
            
            print("loadModel: 全処理完了")
        }

        func updateVisibility(selectedCategories: Set<String>) {
            for entityInfo in allEntities {
                entityInfo.entity?.isEnabled = selectedCategories.contains(entityInfo.category)
            }
        }
    }
}