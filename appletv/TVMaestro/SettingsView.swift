import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    var onClose: () -> Void

    @State private var portText: String = ""
    @State private var tokenText: String = ""
    @State private var editingField: EditField?
    @FocusState private var focused: SettingsFocus?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            RadialGradient(
                colors: [Theme.accent.opacity(0.1), .clear],
                center: .topLeading,
                startRadius: 40,
                endRadius: 900
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Text("Changes save automatically. Press Menu to close.")
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                }

                controlCard
                if showPreview {
                    HStack {
                        Spacer()
                        Button("Play preview") {
                            persist()
                            app.startPreview()
                            onClose()
                        }
                        .buttonStyle(TVSettingsButtonStyle(focused: focused == .preview))
                        .focused($focused, equals: .preview)
                    }
                }
            }
            .frame(maxWidth: 1320)
            .padding(.horizontal, 80)
            .padding(.vertical, 64)
        }
        .focusSection()
        .defaultFocus($focused, .port)
        .onExitCommand {
            persist()
            onClose()
        }
        .onAppear {
            portText = String(app.port)
            tokenText = app.authToken
            app.refreshAddresses()
            focusPort()
        }
        .onDisappear { persist() }
        .onChange(of: focused) { previous, _ in
            if previous == .port || previous == .token {
                persist()
            }
        }
        .sheet(item: $editingField) { field in
            editor(for: field)
        }
    }

    private var showPreview: Bool {
        !app.isPlaying || app.isPreview
    }

    private var controlCard: some View {
        PanelCard(title: "Control API", minHeight: 0) {
            HStack(alignment: .top, spacing: 24) {
                settingRow("Port", value: portText, focus: .port, editor: .port)
                settingRow(
                    "Auth token",
                    value: tokenText.isEmpty ? "Not set" : "••••••••",
                    focus: .token,
                    editor: .token
                )
            }
            Text("Use the same token when adding this Apple TV in the guide. Leave it blank for no token.")
                .font(.callout)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func settingRow(
        _ title: String,
        value: String,
        focus: SettingsFocus,
        editor: EditField
    ) -> some View {
        let active = focused == focus
        return Button {
            editingField = editor
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(active ? Theme.bg.opacity(0.7) : Theme.muted)
                Text(value)
                    .font(.title3.monospaced().weight(.semibold))
                    .foregroundStyle(active ? Theme.bg : Theme.text)
                    .lineLimit(1)
                Text("Select to edit")
                    .font(.caption)
                    .foregroundStyle(active ? Theme.bg.opacity(0.65) : Theme.faint)
            }
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .buttonStyle(SettingsRowButtonStyle(focused: active))
        .focused($focused, equals: focus)
    }

    @ViewBuilder
    private func editor(for field: EditField) -> some View {
        switch field {
        case .port:
            SettingsTextEditor(
                title: "Control port",
                prompt: "9093",
                text: $portText,
                onCommit: persist
            )
        case .token:
            SettingsTextEditor(
                title: "Auth token",
                prompt: "Optional",
                text: $tokenText,
                onCommit: persist
            )
        }
    }

    private func unusedFieldLabel(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.4)
                .foregroundStyle(Theme.muted)
        }
    }

    /// Writes the port and token once editing finishes. Unchanged values skip the server restart.
    private func persist() {
        let trimmedToken = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = Int(portText).map { min(max($0, 1024), 65535) } ?? app.port
        guard port != app.port || trimmedToken != app.authToken else {
            portText = String(app.port)
            return
        }
        app.saveSettings(port: port, token: trimmedToken)
        portText = String(app.port)
        tokenText = app.authToken
    }

    private func focusPort() {
        focused = .port
        Task { @MainActor in
            focused = .port
        }
    }

}

private enum SettingsFocus: Hashable {
    case port
    case token
    case preview
}

private enum EditField: String, Identifiable {
    case port
    case token

    var id: String { rawValue }
}

private struct SettingsRowButtonStyle: ButtonStyle {
    var focused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                focused ? Theme.accent : Color.black.opacity(0.35),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(focused ? Theme.accent : Theme.panelStroke, lineWidth: focused ? 3 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .focusEffectDisabled()
    }
}

private struct TVSettingsButtonStyle: ButtonStyle {
    var focused: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(focused ? Theme.bg : Theme.text)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                focused ? Theme.accent : Color.white.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(focused ? Theme.accent : Theme.panelStroke, lineWidth: focused ? 3 : 1)
            )
            .focusEffectDisabled()
    }
}

private struct SettingsTextEditor: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let prompt: String
    @Binding var text: String
    var onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.title.weight(.semibold))
            TextField(prompt, text: $text)
                .font(.title3.monospaced())
                .onSubmit {
                    onCommit()
                    dismiss()
                }
            Text("Press Menu when finished. Changes save automatically.")
                .font(.callout)
                .foregroundStyle(Theme.muted)
        }
        .frame(width: 900)
        .padding(48)
        .onDisappear(perform: onCommit)
    }
}
