import SwiftUI
import Combine
import AppKit
import ServiceManagement
import Carbon                   

// MARK: -- MODEL
struct Clip: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var date: Date
    var isPinned: Bool = false
    init(id: UUID = .init(), text: String, date: Date = .init(), pinned: Bool = false) {
        self.id = id; self.text = text; self.date = date; self.isPinned = pinned
    }
}

// MARK: -- STORE
final class ClipStore: ObservableObject {
    @Published private(set) var clips: [Clip] = []
    @Published var filterText = ""
    
    @AppStorage("maxHistory") private var maxHistory = 30
    private let pb = NSPasteboard.general
    private var lastChange = NSPasteboard.general.changeCount
    
    private let saveURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipPeak/clips.json")
    }()
    
    init() { restore(); Task { await watchPasteboard() } }
    
    // MARK: computed
    var filtered: [Clip] {
        guard !filterText.isEmpty else { return combined }
        return combined.filter { $0.text.localizedCaseInsensitiveContains(filterText) }
    }
    private var combined: [Clip] { clips.filter(\.isPinned) + clips.filter { !$0.isPinned } }
    
    // MARK: pasteboard
    private func watchPasteboard() async {
        for await _ in AsyncStream<Void> { cont in
            RunLoop.main.add(Timer(timeInterval: 0.4, repeats: true) { _ in cont.yield(()) },
                             forMode: .common)
        } {
            guard pb.changeCount != lastChange else { continue }
            lastChange = pb.changeCount
            if let s = pb.string(forType: .string), !s.isEmpty, clips.first?.text != s {
                insert(.init(text: s))
            }
        }
    }
    
    // MARK: CRUD
    func copy(_ c: Clip) {
        pb.clearContents(); pb.setString(c.text, forType: .string); lastChange = pb.changeCount
    }
    func insert(_ c: Clip) { clips.removeAll { $0.text == c.text }; clips.insert(c, at: 0); trim(); persist() }
    func delete(_ c: Clip) { clips.removeAll { $0.id == c.id }; persist() }
    func togglePin(_ c: Clip) { if let i = clips.firstIndex(of: c) { clips[i].isPinned.toggle(); persist() } }
    private func trim() {
        let nonPinned = clips.filter { !$0.isPinned }
        if nonPinned.count > maxHistory {
            clips.removeAll { nonPinned.dropFirst(maxHistory).contains($0) }
        }
    }
    
    // MARK: persistence
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(clips).write(to: saveURL, options: .atomic)
        } catch { print("save:", error) }
    }
    private func restore() {
        guard let d = try? Data(contentsOf: saveURL),
              let s = try? JSONDecoder().decode([Clip].self, from: d) else { return }
        clips = s
    }
}

// MARK: -- DATE HELPER
extension Clip {
    var prettyDate: String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: date)
    }
}

// MARK: -- DETAIL VIEW (“View Text”)
struct ClipDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ClipStore
    let clip: Clip
    private var charCount: Int { clip.text.count }
    private var wordCount: Int { clip.text.split { $0.isWhitespace || $0.isNewline }.count }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Full Text").font(.headline)
            
            ScrollView {
                Text(clip.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            
            HStack(spacing: 12) {
                Text("\(wordCount) words • \(charCount) chars")
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Button("Copy") { store.copy(clip); dismiss() }
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 420, height: 300)
    }
}

// MARK: -- ROW
struct ClipRow: View {
    @EnvironmentObject private var store: ClipStore
    let clip: Clip
    let onView: () -> Void
    
    var body: some View {
        HStack {
            Text(clip.text).font(.body.monospaced())
                .lineLimit(1).truncationMode(.middle)
                .onTapGesture { store.copy(clip) }
            
            Spacer(minLength: 4)
            Text(clip.prettyDate).font(.caption2).foregroundColor(.secondary)
            
            Button(action: onView) { Image(systemName: "eye") }
                .help("View full text").buttonStyle(.plain)
            
            Button { store.togglePin(clip) } label: {
                Image(systemName: clip.isPinned ? "pin.fill" : "pin")
            }.help(clip.isPinned ? "Unpin" : "Pin").buttonStyle(.plain)
            
            Button(role: .destructive) { store.delete(clip) } label: {
                Image(systemName: "trash")
            }.help("Delete").buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        // context-menu mirrors inline actions
        .contextMenu {
            Button("View", action: onView)
            Button("Copy") { store.copy(clip) }
            Button(clip.isPinned ? "Unpin" : "Pin") { store.togglePin(clip) }
            Divider()
            Button("Delete", role: .destructive) { store.delete(clip) }
        }
    }
}

// MARK: -- LIST
struct ClipListView: View {
    @EnvironmentObject private var store: ClipStore
    @State private var viewClip: Clip?
    @FocusState private var searchFocused
    
    var body: some View {
        VStack(spacing: 8) {
            // search
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search", text: $store.filterText)
                    .textFieldStyle(.plain).focused($searchFocused)
                if !store.filterText.isEmpty {
                    Button { store.filterText = ""; searchFocused = false }
                           label: { Image(systemName: "xmark.circle.fill") }
                           .buttonStyle(.plain)
                }
            }
            .padding(6).background(.bar)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal).padding(.top, 6)
            
            // list
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if store.filtered.isEmpty {
                        Text("No items").font(.caption).foregroundColor(.secondary)
                            .padding(.top, 40)
                    } else {
                        ForEach(store.filtered) { c in
                            ClipRow(clip: c, onView: { viewClip = c })
                                .environmentObject(store)
                        }
                    }
                }
                .padding(.horizontal, 8).padding(.bottom, 8)
            }
            .frame(width: 380, height: 320)
        }
        .padding(.bottom, 8)
        .sheet(item: $viewClip) { ClipDetailView(clip: $0).environmentObject(store) }
    }
}

// MARK: -- SETTINGS
struct SettingsView: View {
    @AppStorage("maxHistory") private var maxHistory = 30
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    var body: some View {
        Form {
            Stepper("Maximum recent clips: \(maxHistory)", value: $maxHistory, in: 5...100)
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { v in SMAppService.toggle(launchAtLogin: v) }
        }
        .padding(20).frame(width: 320)
    }
}

private extension SMAppService {
    static func toggle(launchAtLogin v: Bool) {
        do { v ? try mainApp.register() : try mainApp.unregister() }
        catch { print("Launch-at-login:", error) }
    }
}

// MARK: -- HOT-KEY (Carbon)
final class GlobalHotKey {
    private var hkID: EventHotKeyID
    private var hkRef: EventHotKeyRef?
    private let code: UInt32, mods: UInt32
    var handler: (() -> Void)?
    
    init(key: Key, mods m: NSEvent.ModifierFlags) {
        code = key.rawValue; mods = m.carbonFlags
        hkID = EventHotKeyID(signature: OSType("CLPK".fourCharCode),
                             id: UInt32.random(in: 1...UInt32.max))
    }
    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _,_,user in
            Unmanaged<GlobalHotKey>.fromOpaque(user!).takeUnretainedValue().handler?(); return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        RegisterEventHotKey(code, mods, hkID, GetEventDispatcherTarget(), 0, &hkRef)
    }
    func unregister() { if let hkRef { UnregisterEventHotKey(hkRef) } }
    enum Key: UInt32 { case v = 9 }
}

private extension NSEvent.ModifierFlags {
    var carbonFlags: UInt32 {
        var c: UInt32 = 0
        if contains(.command)  { c |= UInt32(cmdKey) }
        if contains(.option)   { c |= UInt32(optionKey) }
        if contains(.shift)    { c |= UInt32(shiftKey) }
        if contains(.control)  { c |= UInt32(controlKey) }
        return c
    }
}
private extension String { var fourCharCode: OSType {
    unicodeScalars.reduce(into: UInt32()) { $0 = ($0 << 8) + $1.value }
}}

// MARK: -- DELEGATE
final class StatusController: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem!
    private let store = ClipStore()
    private let pop = NSPopover()
    private var monitor: Any?
    private let hotKey = GlobalHotKey(key: .v, mods: [.option, .shift, .command])
    
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = item.button {
            b.image = NSImage(systemSymbolName: "doc.on.clipboard.fill",
                              accessibilityDescription: "ClipPeak")
            b.action = #selector(togglePopover(_:)); b.target = self
        }
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(rootView: ClipListView()
                                                        .environmentObject(store))
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown,.rightMouseDown]) {
            [weak self] _ in self?.pop.performClose(nil)
        }
        hotKey.handler = { [weak self] in self?.showPopover() }; hotKey.register()
    }
    func applicationWillTerminate(_ n: Notification) {
        if let m = monitor { NSEvent.removeMonitor(m) }; hotKey.unregister()
    }
    
    @objc private func togglePopover(_ s: Any?) { pop.isShown ? pop.performClose(s) : showPopover() }
    private func showPopover() {
        guard let btn = item.button else { return }
        pop.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        pop.contentViewController?.view.window?.makeKey()
    }
}

// MARK: -- APP ENTRY
@main
struct Team_Airavata_HubApp: App {
    @NSApplicationDelegateAdaptor(StatusController.self) var delegate
    var body: some Scene { Settings { SettingsView() } }
}
