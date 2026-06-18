//
//  ResultRow.swift
//  A label/value row with selectable, monospaced value text and a copy action.
//  Used by every calculator/lookup screen so results are consistently
//  copy-pasteable into a ticket or note — locally, via the system pasteboard.
//

import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct ResultRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        // Reference wiring of the Octet color tokens (see Color+Octet.swift).
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.octetMuted)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.octetInk)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .contextMenu {
            Button {
                copyToPasteboard(value)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .tint(.octetAccent)
        }
    }

    private func copyToPasteboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
