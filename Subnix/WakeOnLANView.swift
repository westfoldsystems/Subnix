//
//  WakeOnLANView.swift
//  Thin shell over WakeOnLAN. Type a MAC (optionally a broadcast/IP target),
//  tap Wake, and the magic packet goes out on the local network.
//

import SwiftUI

struct WakeOnLANView: View {
    @State private var mac = ""
    @State private var target = ""
    @State private var waker = WakeOnLAN()

    var body: some View {
        Form {
            Section {
                TextField("MAC address, e.g. a4:2b:1c:00:11:22", text: $mac)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
                TextField("Broadcast or IP (optional)", text: $target)
                    .font(.system(.body, design: .monospaced))
                    #if os(iOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    #endif
            } header: {
                Text("Device")
            } footer: {
                Text("Leave the target blank to send to your subnet broadcast and 255.255.255.255 on UDP port 9. Grab the MAC from the LAN Scanner.")
            }

            switch waker.state {
            case .sent(let mac, let targets):
                Section("Sent") {
                    ResultRow("Magic packet", "→ \(mac)", valueColor: .statusOnline)
                    ForEach(targets, id: \.self) { ResultRow("Target", $0) }
                }
            case .failed(let message):
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.statusTimeout)
                }
            default:
                EmptyView()
            }
        }
        .formStyle(.grouped)
        .subnixScreen()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Wake", systemImage: "power") {
                    waker.wake(macText: mac, targetOverride: target)
                }
                .disabled(mac.trimmingCharacters(in: .whitespaces).isEmpty || waker.isSending)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Sends a Wake-on-LAN magic packet on your local network only. The target’s firmware/OS must have WoL enabled.")
                .font(.caption2).foregroundStyle(.subnixMuted)
                .frame(maxWidth: .infinity).padding(8).background(.bar)
        }
    }
}

#Preview {
    NavigationStack { WakeOnLANView() }
}
