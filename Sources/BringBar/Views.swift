import SwiftUI
import ServiceManagement

// Plain ObservableObjects instead of @State: the Command Line Tools ship without the SwiftUI macro plugin.
final class LoginForm: ObservableObject {
    @Published var email = UserDefaults.standard.string(forKey: "email") ?? ""
    @Published var password = ""
}
final class MainForm: ObservableObject {
    @Published var text = ""
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
}
final class HoverState: ObservableObject { @Published var hover = false }

struct RootView: View {
    @ObservedObject var store: Store
    @ObservedObject private var language = Language.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BringBar").font(.headline)
                if store.loggedIn { ListHeader(store: store) }
                Spacer()
                Picker("", selection: $language.code) {
                    Text("EN").tag("en")
                    Text("NL").tag("nl")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 84)
            }
            if store.loggedIn { MainView(store: store) } else { LoginView(store: store) }
        }
        .padding(14)
        .frame(width: 360)
        .id(language.code) // rebuild all text when the language changes
    }
}

// MARK: - Sign in

struct LoginView: View {
    @ObservedObject var store: Store
    @StateObject private var form = LoginForm()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox(L("Sign in to Bring!")) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(L("Email"), text: $form.email).textFieldStyle(.roundedBorder)
                        .textContentType(.username)
                    SecureField(L("Password"), text: $form.password).textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .onSubmit(submit)
                    Text(L("Signed up with Google or Apple? Set a password first in the Bring! app (Profile → Account)."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        if store.busy { ProgressView().controlSize(.small) }
                        Button(L("Sign in"), action: submit).keyboardShortcut(.defaultAction)
                            .disabled(form.email.isEmpty || form.password.isEmpty || store.busy)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Footer(store: store, showAccount: false)
        }
    }

    private func submit() {
        guard !form.email.isEmpty, !form.password.isEmpty else { return }
        Task { await store.login(email: form.email.trimmingCharacters(in: .whitespaces), password: form.password) }
    }
}

// MARK: - Main

struct MainView: View {
    @ObservedObject var store: Store
    @StateObject private var form = MainForm()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Add: one field, Enter adds.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    TextField(L("Milk, eggs: 12, bread"), text: $form.text)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .focused($focused)
                        .onSubmit(submit)
                    Button(action: submit) { Image(systemName: "plus.circle.fill").font(.title2) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.green)
                        .help(L("Add"))
                        .disabled(form.text.trimmingCharacters(in: .whitespaces).isEmpty || store.busy)
                }
                let sugg = store.suggestions(for: form.text)
                if !sugg.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(sugg, id: \.self) { s in
                            Button(s) { complete(with: s) }.buttonStyle(.link).font(.callout)
                        }
                    }
                }
            }

            // 2. What is on the list; the trash can removes an item.
            GroupBox {
                ScrollView {
                    VStack(spacing: 0) {
                        if store.purchase.isEmpty {
                            Text(L("Nothing left to buy")).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                        }
                        ForEach(Array(store.purchase.enumerated()), id: \.element.id) { i, item in
                            if i > 0 { Divider() }
                            ItemRow(title: store.displayName(item.name), spec: item.spec) {
                                Task { await store.remove(item) }
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .fixedSize(horizontal: false, vertical: true)
            } label: {
                HStack {
                    Text(L("On the list"))
                    if !store.purchase.isEmpty {
                        Text("\(store.purchase.count)").foregroundStyle(.secondary)
                    }
                }
            }

            // 3. Settings.
            Toggle(L("Launch at login"), isOn: $form.launchAtLogin)
                .onChange(of: form.launchAtLogin) { _, on in
                    do { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
                    catch { store.show(L("Login setting failed: %@", error.localizedDescription), error: true) }
                }

            Footer(store: store, showAccount: true)
        }
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .popoverDidOpen)) { _ in
            focused = true
            Task { await store.reloadListContent() }
        }
    }

    private func complete(with suggestion: String) {
        var parts = form.text.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        if !parts.isEmpty { parts.removeLast() }
        parts.append((parts.isEmpty ? "" : " ") + suggestion)
        form.text = parts.joined(separator: ",")
        focused = true
    }

    private func submit() {
        let t = form.text
        guard !t.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        form.text = ""
        Task { if !(await store.add(t)) { form.text = t } }
    }
}

/// List picker in the header when there is more than one list, otherwise just the list name.
struct ListHeader: View {
    @ObservedObject var store: Store
    var body: some View {
        if store.lists.count > 1 {
            Picker("", selection: $store.selectedListID) {
                ForEach(store.lists) { Text($0.name).tag(Optional($0.id)) }
            }
            .labelsHidden().fixedSize()
        } else if let name = store.lists.first?.name {
            Text(name).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared pieces

struct Footer: View {
    @ObservedObject var store: Store
    let showAccount: Bool

    var body: some View {
        HStack {
            Group {
                if store.busy { ProgressView().controlSize(.small) }
                if let m = store.message {
                    Text(m).foregroundStyle(store.isError ? Color.red : Color.secondary)
                } else {
                    Text(L("Shortcut: ⌥⌘B")).foregroundStyle(.secondary)
                }
            }
            .font(.caption).lineLimit(2)
            Spacer()
            if showAccount {
                Button(L("Sign out")) { store.logout() }
            }
            Button(L("Quit BringBar")) { NSApp.terminate(nil) }
        }
    }
}

struct ItemRow: View {
    let title: String
    let spec: String
    let onDelete: () -> Void
    @StateObject private var h = HoverState()

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            if !spec.isEmpty { Text(spec).font(.callout).foregroundStyle(.secondary) }
            Spacer()
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .foregroundStyle(h.hover ? Color.red : Color.secondary)
                .help(L("Remove from the list"))
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { h.hover = $0 }
    }
}

extension Notification.Name {
    static let popoverDidOpen = Notification.Name("BringBarPopoverDidOpen")
}
