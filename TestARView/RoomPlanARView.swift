//
//  RoomPlanARView.swift
//  TestARView
//
//  Created by Assistant on R 7/09/26.
//

import SwiftUI
import RealityKit
import ARKit

struct RoomPlanARView: View {
    @State private var selectedCategories: Set<String> = [
        "壁", "床", "天井", "ドア", "窓", "開口部", "収納", "階段", "家具", "構造", "その他"
    ]
    @State private var entityHierarchy: [EntityInfo] = []
    @State private var showEntityList = false

    private let allCategories = [
        "壁", "床", "天井", "ドア", "窓", "開口部", "収納", "階段", "家具", "構造", "その他"
    ]

    var body: some View {
        ZStack {
            ARContainerView(
                selectedCategories: $selectedCategories,
                entityHierarchy: $entityHierarchy
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()

                    Button(action: { 
                        print("RoomPlanARView: ボタンタップ - entityHierarchy.count: \(entityHierarchy.count)")
                        for entity in entityHierarchy {
                            print("  - \(entity.name): \(entity.category)")
                        }
                        showEntityList.toggle() 
                    }) {
                        Image(systemName: "list.bullet")
                            .font(.title2)
                            .padding()
                            .background(.regularMaterial)
                            .clipShape(Circle())
                    }
                    .padding()
                }

                Spacer()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(allCategories, id: \.self) { category in
                            CategoryToggle(
                                category: category,
                                isSelected: selectedCategories.contains(category),
                                action: {
                                    if selectedCategories.contains(category) {
                                        selectedCategories.remove(category)
                                    } else {
                                        selectedCategories.insert(category)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding()
            }
            
            if showEntityList {
                EntityListView(
                    entities: entityHierarchy,
                    selectedCategories: $selectedCategories,
                    isPresented: $showEntityList
                )
            }
        }
    }
}

struct CategoryToggle: View {
    let category: String
    let isSelected: Bool
    let action: () -> Void

    var iconName: String {
        switch category {
        case "壁": return "rectangle.split.3x1"
        case "床": return "square.grid.3x3"
        case "天井": return "rectangle"
        case "ドア": return "door.left.hand.closed"
        case "窓": return "window.vertical.closed"
        case "開口部": return "square.split.2x1"
        case "収納": return "cabinet"
        case "階段": return "stairs"
        case "家具": return "chair"
        case "構造": return "building.2"
        default: return "cube"
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.title2)
                Text(category)
                    .font(.caption)
            }
            .frame(width: 70, height: 70)
            .foregroundColor(isSelected ? .white : .primary)
            .background(isSelected ? Color.blue : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct EntityListView: View {
    let entities: [EntityInfo]
    @Binding var selectedCategories: Set<String>
    @Binding var isPresented: Bool

    var categorizedEntities: [(String, [EntityInfo])] {
        let grouped = Dictionary(grouping: entities) { $0.category }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationView {
            List {
                Section("デバッグ情報") {
                    Text("エンティティ数: \(entities.count)")
                    Text("カテゴリ数: \(categorizedEntities.count)")
                    
                    ForEach(entities, id: \.id) { entity in
                        HStack {
                            Text(entity.name)
                            Spacer()
                            Text(entity.category)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Section("カテゴリー別表示/非表示") {
                    ForEach(categorizedEntities, id: \.0) { category, items in
                        HStack {
                            Toggle(isOn: Binding(
                                get: { selectedCategories.contains(category) },
                                set: { isOn in
                                    if isOn {
                                        selectedCategories.insert(category)
                                    } else {
                                        selectedCategories.remove(category)
                                    }
                                }
                            )) {
                                Label {
                                    HStack {
                                        Text(category)
                                        Spacer()
                                        Text("\(items.count)個")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                } icon: {
                                    Image(systemName: categoryIcon(for: category))
                                }
                            }
                        }
                    }
                }

                Section("エンティティ階層") {
                    ForEach(entities) { entity in
                        HStack {
                            Text(String(repeating: "  ", count: entity.level))
                            Text(entity.name)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(entity.category)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
            .onAppear {
                print("EntityListView: onAppear - entities.count: \(entities.count)")
                for entity in entities {
                    print("  - \(entity.name): \(entity.category)")
                }
            }
            .navigationTitle("エンティティ一覧")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") {
                        isPresented = false
                    }
                }
            }
        }
        .transition(.move(edge: .bottom))
        .animation(.easeInOut, value: isPresented)
    }

    func categoryIcon(for category: String) -> String {
        switch category {
        case "壁": return "rectangle.split.3x1"
        case "床": return "square.grid.3x3"
        case "天井": return "rectangle"
        case "ドア": return "door.left.hand.closed"
        case "窓": return "window.vertical.closed"
        case "開口部": return "square.split.2x1"
        case "収納": return "cabinet"
        case "階段": return "stairs"
        case "家具": return "chair"
        case "構造": return "building.2"
        default: return "cube"
        }
    }
}

#Preview {
    RoomPlanARView()
}