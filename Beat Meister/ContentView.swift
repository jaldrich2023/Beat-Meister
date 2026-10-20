//
//  ContentView.swift
//  Beat Meister
//
//  Created by John Aldrich on 10/20/26.
//

import SwiftUI

struct ContentView: View {
    @State private var deckA = DeckModel(name: "A")
    @State private var deckB = DeckModel(name: "B")
    @State private var crossfader: Double = 0

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            DeckView(deck: deckA, color: Theme.deckA)
            MixerView(deckA: deckA, deckB: deckB, crossfader: $crossfader)
            DeckView(deck: deckB, color: Theme.deckB)
        }
        // Size the row to its tallest panel so all three panels match.
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(minWidth: 1180, minHeight: 720)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
