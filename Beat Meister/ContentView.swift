//
//  ContentView.swift
//  Beat Meister
//
//  Created by John Aldrich on 10/20/26.
//

import SwiftUI

struct ContentView: View {
    @State private var mixer = MixEngine()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            DeckView(deck: mixer.deckA, color: Theme.deckA)
            MixerView(deckA: mixer.deckA, deckB: mixer.deckB, crossfader: $mixer.crossfader)
            DeckView(deck: mixer.deckB, color: Theme.deckB)
        }
        // Size the row to its tallest panel so all three panels match.
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(minWidth: 1620, minHeight: 820)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
