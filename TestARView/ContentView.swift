//
//  ContentView.swift
//  TestARView
//
//  Created by はるちろ on R 7/09/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        RoomPlanARView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
