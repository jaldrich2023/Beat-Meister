//
//  MixerView.swift
//  Beat Meister
//

import SwiftUI

/// A DJM-style two-channel mixer: EQ knobs, LED meters, long-throw channel
/// faders and a crossfader.
struct MixerView: View {
    @Bindable var deckA: DeckModel
    @Bindable var deckB: DeckModel
    /// Crossfader position: -1 is full Deck A, 1 is full Deck B.
    @Binding var crossfader: Double

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 6) {
                Text("MIXER")
                    .font(.system(.headline, design: .rounded).weight(.black))
                    .tracking(3)
                    .foregroundStyle(Theme.mixer)
                    .shadow(color: Theme.mixer.opacity(0.7), radius: 4)
                NeonLine(color: Theme.mixer, isLit: deckA.isPlaying || deckB.isPlaying, thickness: 1.5)
            }

            HStack(alignment: .top, spacing: 0) {
                ChannelStrip(deck: deckA, color: Theme.deckA)
                    .frame(maxWidth: .infinity)
                PanelSeam()
                ChannelStrip(deck: deckB, color: Theme.deckB)
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                HStack {
                    Text("A").foregroundStyle(Theme.deckA)
                    Spacer()
                    Text("B").foregroundStyle(Theme.deckB)
                }
                .font(.caption.weight(.heavy))
                HorizontalFader(value: $crossfader, range: -1...1, color: Theme.mixer)
                    .accessibilityLabel("Crossfader")
                SilkLabel("Crossfader")
            }
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity)
        .neonPane(Theme.mixer, isLit: deckA.isPlaying || deckB.isPlaying)
    }
}

private struct ChannelStrip: View {
    @Bindable var deck: DeckModel
    var color: Color

    var body: some View {
        VStack(spacing: 10) {
            SilkLabel("CH \(deck.name)", size: 9)
                .padding(.bottom, 2)
            Knob(label: "Hi", value: $deck.high, color: color)
            Knob(label: "Mid", value: $deck.mid, color: color)
            Knob(label: "Low", value: $deck.low, color: color)

            HStack(alignment: .center, spacing: 6) {
                LEDMeter()
                    .frame(width: 8, height: 150)
                VerticalFader(value: $deck.volume, range: 0...1, color: color)
                    .frame(width: 44, height: 170)
                    .accessibilityLabel("Channel \(deck.name) Volume")
            }
            SilkLabel("Channel Fader")
        }
    }
}

/// A recessed seam between faceplate sections.
private struct PanelSeam: View {
    var body: some View {
        HStack(spacing: 0) {
            Color.black.opacity(0.6).frame(width: 1)
            Color.white.opacity(0.08).frame(width: 1)
        }
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}
