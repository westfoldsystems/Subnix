//
//  ResultRow.swift
//  A label/value row with selectable, monospaced value text and a copy action.
//  Used by every calculator/lookup screen so results are consistently
//  copy-pasteable into a ticket or note — locally, via the system pasteboard.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ResultRow: View {
    let label: String
    let value: String
    /// Value text color — defaults to ink; status rows pass a status token.
    var valueColor: Color

    // Drives the OS text-size (Dynamic Type) setting into the layout choice.
    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ label: String, _ value: String, valueColor: Color = .subnixInk) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
    }

    var body: some View {
        content
            .contextMenu {
                Button {
                    copyToPasteboard(value)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .tint(.subnixAccent)
            }
    }

    // Label + value share a line normally, but at accessibility text sizes that
    // can't fit without truncating — so stack them vertically instead.
    @ViewBuilder
    private var content: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .foregroundStyle(.subnixMuted)
                valueText
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(.subnixMuted)
                Spacer(minLength: 12)
                valueText
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var valueText: some View {
        Text(value)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(valueColor)
            .textSelection(.enabled)
    }

    private func copyToPasteboard(_ string: String) {
        #if os(iOS)
        // Local-only (no Universal Clipboard / Handoff to other devices) and
        // auto-expiring, so copied IPs/hostnames don't sync off-device or linger.
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: string]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(90),
            ]
        )
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
