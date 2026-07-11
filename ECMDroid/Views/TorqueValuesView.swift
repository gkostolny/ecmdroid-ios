// ECMDroid iOS - Diagnostic Tool for Buell Motorcycles
// Copyright (C) 2012 by Michel Marti
// iOS port Copyright (C) 2025
// Licensed under GPL-3.0

import SwiftUI

/// Static reference table of Buell XB fastener torque specifications, ported from
/// the original ECMDroid. Available offline and regardless of connection state.
struct TorqueValuesView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredCategories) { category in
                    Section(category.name) {
                        ForEach(category.specs) { spec in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(spec.fastener)
                                    .font(.body)
                                Text(spec.spec)
                                    .font(.callout)
                                    .foregroundStyle(Color.buellGold)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if filteredCategories.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .navigationTitle("Torque Values")
            .searchable(text: $searchText, prompt: "Search fasteners")
            .safeAreaInset(edge: .bottom) {
                Text("\(TorqueData.modelName) — reference only; confirm against the factory service manual.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }

    private var filteredCategories: [TorqueCategory] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return TorqueData.categories }
        return TorqueData.categories.compactMap { category in
            let matches = category.specs.filter {
                $0.fastener.localizedCaseInsensitiveContains(query) ||
                $0.spec.localizedCaseInsensitiveContains(query)
            }
            return matches.isEmpty ? nil : TorqueCategory(name: category.name, specs: matches)
        }
    }
}
