import SwiftUI
import Combine
import AppKit

struct C: Identifiable {
    let id = UUID()
    let t: String
    let d: Date
}

final class M: ObservableObject {
    @Published private(set) var h: [C] = []

    private let p = NSPasteboard.general
    private var c: Int
    private var tm: Timer?

    init() {
        self.c = p.changeCount
    }

    func sM() {
        sT()
        tm = Timer(timeInterval: 0.5,
                   target: self,
                   selector: #selector(ch),
                   userInfo: nil,
                   repeats: true)
        RunLoop.main.add(tm!, forMode: .common)
    }

    func sT() {
        tm?.invalidate()
        tm = nil
    }

    @objc private func ch() {
        let n = p.changeCount
        guard n != c else { return }
        c = n

        if let x = p.string(forType: .string),
           !x.isEmpty,
           h.first?.t != x {
            let i = C(t: x, d: Date())
            h.insert(i, at: 0)
            if h.count > 15 {
                h.removeLast(h.count - 15)
            }
        }
    }

    func cT(_ i: C) {
        p.clearContents()
        p.setString(i.t, forType: .string)
        c = p.changeCount
    }
}

private let f: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .short
    return f
}()

struct V: View {
    @Environment(\.dismiss) private var d
    @EnvironmentObject private var m: M
    let i: C

    var body: some View {
        VStack(alignment: .leading) {
            Text("Full Clipboard Text")
                .font(.headline)
                .padding(.bottom, 6)

            ScrollView {
                Text(i.t)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Button("Close") {
                    d()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Copy") {
                    m.cT(i)
                    d()
                }
                .keyboardShortcut("c", modifiers: .command)
            }
            .padding(.top, 6)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct R: View {
    @EnvironmentObject var m: M
    @State private var s: C?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Clipboard History")
                .font(.headline)
                .padding(.bottom, 4)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if m.h.isEmpty {
                        Text("No items copied yet.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(m.h) { i in
                            HStack(spacing: 8) {
                                Text(i.t)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Text(f.string(from: i.d))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Button {
                                    m.cT(i)
                                } label: {
                                    Image(systemName: "doc.on.clipboard")
                                }
                                .help("Copy this text")
                                .buttonStyle(BorderlessButtonStyle())

                                Button {
                                    s = i
                                } label: {
                                    Image(systemName: "eye")
                                }
                                .help("View full text")
                                .buttonStyle(BorderlessButtonStyle())
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(minWidth: 320, minHeight: 240)
        }
        .padding()
        .sheet(item: $s) { i in
            V(i: i).environmentObject(m)
        }
    }
}

@main
struct A: App {
    @NSApplicationDelegateAdaptor(D.self) var a

    var body: some Scene {
        Settings { EmptyView() }
    }
}

final class D: NSObject, NSApplicationDelegate {
    private var si: NSStatusItem!
    private var po: NSPopover!
    private let m = M()

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        m.sM()

        si = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = si.button {
            b.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard History")
            b.action = #selector(tP(_:))
            b.target = self
        }

        po = NSPopover()
        po.behavior = .transient
        po.contentSize = NSSize(width: 320, height: 240)
        po.contentViewController = NSHostingController(rootView: R().environmentObject(m))
    }

    @objc private func tP(_ s: Any?) {
        guard let b = si.button else { return }
        if po.isShown {
            po.performClose(s)
        } else {
            po.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            po.contentViewController?.view.window?.becomeKey()
        }
    }
}
