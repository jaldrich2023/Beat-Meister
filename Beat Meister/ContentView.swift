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
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                DeckView(deck: deckA, color: Theme.deckA)
                MixerView(deckA: deckA, deckB: deckB, crossfader: $crossfader)
                DeckView(deck: deckB, color: Theme.deckB)
            }

            LibraryView(tracks: Track.samples) { track, side in
                switch side {
                case .a: deckA.load(track)
                case .b: deckB.load(track)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 1100, minHeight: 760)
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
