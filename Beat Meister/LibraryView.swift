//
//  LibraryView.swift
//  Beat Meister
//

import SwiftUI

struct LibraryView: View {
    var tracks: [Track]
    var onLoad: (Track, DeckSide) -> Void

    @State private var selection: Track.ID?
    @State private var searchText = ""

    enum DeckSide {
        case a, b
    }

    private var filteredTracks: [Track] {
        guard !searchText.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedStandardContains(searchText) || $0.artist.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LIBRARY")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                Spacer()
                TextField("Search", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }

            Table(filteredTracks, selection: $selection) {
                TableColumn("Title", value: \.title)
                TableColumn("Artist", value: \.artist)
                TableColumn("BPM") { track in
                    Text(track.bpm.formatted(.number.precision(.fractionLength(0))))
                        .monospacedDigit()
                }
                .width(60)
                TableColumn("Key", value: \.key)
                    .width(50)
                TableColumn("Time") { track in
                    Text(Duration.seconds(track.duration).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                }
                .width(60)
                TableColumn("Load") { track in
                    HStack(spacing: 6) {
                        Button("A") { onLoad(track, .a) }
                            .tint(Theme.deckA)
                        Button("B") { onLoad(track, .b) }
                            .tint(Theme.deckB)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .width(80)
            }
            .scrollContentBackground(.hidden)
        }
        .neonPane(.white.opacity(0.6))
    }
}
