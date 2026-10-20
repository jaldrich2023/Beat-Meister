//
//  MixerView.swift
//  Beat Meister
//

import SwiftUI

struct MixerView: View {
    @Bindable var deckA: DeckModel
    @Bindable var deckB: DeckModel
    /// Crossfader position: -1 is full Deck A, 1 is full Deck B.
    @Binding var crossfader: Double

    var body: some View {
        VStack(spacing: 14) {
            Text("MIXER")
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundStyle(Theme.mixer)

            HStack(alignment: .top, spacing: 24) {
                ChannelStrip(deck: deckA, color: Theme.deckA)
                ChannelStrip(deck: deckB, color: Theme.deckB)
            }

            VStack(spacing: 4) {
                Slider(value: $crossfader, in: -1...1)
                    .tint(Theme.mixer)
                    .accessibilityLabel("Crossfader")
                HStack {
                    Text("A").foregroundStyle(Theme.deckA)
                    Spacer()
                    Text("B").foregroundStyle(Theme.deckB)
                }
                .font(.caption.weight(.bold))
            }
            .onTapGesture(count: 2) { crossfader = 0 }
        }
        .frame(width: 220)
        .neonPane(Theme.mixer, isLit: deckA.isPlaying || deckB.isPlaying)
    }
}

private struct ChannelStrip: View {
    @Bindable var deck: DeckModel
    var color: Color

    var body: some View {
        VStack(spacing: 10) {
            Knob(label: "HI", value: $deck.high, color: color)
            Knob(label: "MID", value: $deck.mid, color: color)
            Knob(label: "LOW", value: $deck.low, color: color)
            VerticalSlider(value: $deck.volume, range: 0...1, color: color)
                .frame(width: 28, height: 130)
                .accessibilityLabel("\(deck.name) Volume")
            Text(deck.name)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
        }
    }
}
