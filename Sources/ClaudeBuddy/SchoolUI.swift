import AppKit
import SwiftUI

// MARK: - Windows

/// Opens (or re-focuses) the Canvas Settings window. (Today is the pixel billboard the buddies hold.)
final class SchoolWindows {
    private let store: SchoolStore
    private var settings: NSWindow?

    init(store: SchoolStore) { self.store = store }

    func showSettings() {
        settings = show(settings, title: "Canvas", size: NSSize(width: 460, height: 420), resizable: false) {
            CanvasSettingsView(store: store, form: CanvasForm())
        }
    }

    private func show<V: View>(_ existing: NSWindow?, title: String, size: NSSize, resizable: Bool,
                               @ViewBuilder content: () -> V) -> NSWindow {
        NSApp.activate(ignoringOtherApps: true)
        if let existing {
            existing.makeKeyAndOrderFront(nil)
            return existing
        }
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style, backing: .buffered, defer: false)
        window.title = title
        window.contentViewController = NSHostingController(rootView: content())
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        return window
    }
}

// MARK: - Canvas settings

/// Form state for the settings window. (A plain ObservableObject rather than @State, which
/// needs a SwiftUI macro plugin that only ships with the full Xcode app.)
final class CanvasForm: ObservableObject {
    @Published var address = ""
    @Published var token = ""
    @Published var working = false
    @Published var message: String?
    @Published var failed = false
}

struct CanvasSettingsView: View {
    @ObservedObject var store: SchoolStore
    @ObservedObject var form: CanvasForm

    var body: some View {
        Form {
            if store.isConnected {
                Section {
                    LabeledContent("Connected to", value: store.canvasHost?.host ?? "")
                    if let name = store.snapshot?.userName { LabeledContent("Signed in as", value: name) }
                    Button("Disconnect", role: .destructive) { store.disconnect() }
                }
            } else {
                Section {
                    TextField("Canvas address", text: $form.address, prompt: Text("yourschool.instructure.com"))
                        .textContentType(.URL)
                    SecureField("Access token", text: $form.token, prompt: Text("Paste your token"))
                } header: {
                    Text("Connect your school's Canvas")
                } footer: {
                    Text("To get a token, open Canvas in your browser, go to **Account → Settings**, and click **+ New Access Token**. Name it “Claude Buddy”, generate it, and copy the token shown. It's stored in your Mac's Keychain and only ever sent to your school's Canvas.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    HStack {
                        Button("Connect") { connect() }
                            .keyboardShortcut(.defaultAction)
                            .disabled(form.working || form.address.isEmpty || form.token.isEmpty)
                        if form.working { ProgressView().controlSize(.small) }
                        if let message = form.message {
                            Text(message)
                                .foregroundStyle(form.failed ? .red : .green)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Section {
                Toggle("Buddy reminds me before things are due", isOn: Binding(
                    get: { store.remindersEnabled }, set: { store.remindersEnabled = $0 }))
            } footer: {
                Text("A day, 3 hours, and 1 hour before each due date, plus a daily heads-up about missing work.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }

    private func connect() {
        form.working = true
        form.message = nil
        Task { @MainActor in
            let result = await store.connect(address: form.address, token: form.token)
            form.working = false
            switch result {
            case .success(let name):
                form.failed = false
                form.message = "Connected — hi, \(name)!"
            case .failure(let error):
                form.failed = true
                form.message = error.localizedDescription
            }
            form.token = ""  // Don't keep the token around in memory longer than needed.
        }
    }
}
