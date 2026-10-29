// 윈도우경로열기 — 메뉴바에서 윈도우 공유 경로(\\서버\공유\...)를 파인더로 연다.
// 실제 열기·마운트는 번들 안의 winopen 스크립트가 한다(CLI 와 같은 동작).
import AppKit
import ServiceManagement

let favoritesURL: URL = {
    let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("WinOpen", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("favorites.tsv")
}()

let favoritesHeader = "# 즐겨찾기 — 한 줄에 「이름<탭>경로」. # 으로 시작하면 주석, 빈 줄이면 메뉴 구분선.\n"

struct Favorite: Equatable { let name: String; let path: String }

enum FavError: Error { case read(String), write(String) }

// 파일이 없으면 헤더만 있는 새 파일을 만든다. 있는데 못 읽으면 오류(덮어쓰지 않는다).
func readFavoritesText() throws -> String {
    if !FileManager.default.fileExists(atPath: favoritesURL.path) {
        do { try favoritesHeader.write(to: favoritesURL, atomically: true, encoding: .utf8) }
        catch { throw FavError.write(error.localizedDescription) }
        return favoritesHeader
    }
    do { return try String(contentsOf: favoritesURL, encoding: .utf8) }
    catch { throw FavError.read(error.localizedDescription) }
}

func parseFavorites(_ text: String) -> [Favorite?] {  // nil = 구분선
    var out: [Favorite?] = []
    for line in text.components(separatedBy: .newlines) {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { continue }
        if t.isEmpty { if let last = out.last, last != nil { out.append(nil) }; continue }
        let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            out.append(Favorite(name: parts[0].trimmingCharacters(in: .whitespaces),
                                path: parts[1].trimmingCharacters(in: .whitespaces)))
        } else {
            out.append(Favorite(name: t, path: t))
        }
    }
    while let last = out.last, last == nil { out.removeLast() }
    return out
}

func loadFavorites() throws -> [Favorite?] { parseFavorites(try readFavoritesText()) }

// 이름·경로에 들어가면 파일 형식이 깨지는 문자를 정리한다(탭·줄바꿈 → 공백, 맨 앞 # 은 주석이 되므로 막는다)
func cleanField(_ s: String) -> String {
    s.replacingOccurrences(of: "\t", with: " ")
        .components(separatedBy: .newlines).joined(separator: " ")
        .trimmingCharacters(in: .whitespaces)
}
func validateName(_ name: String) -> String? {
    let n = cleanField(name)
    if n.isEmpty { return nil }
    if n.hasPrefix("#") { alert("이름은 # 으로 시작할 수 없어", "파일에서 주석으로 읽혀 사라져."); return nil }
    return n
}

// 경로는 바꾸지 않는다 — 파일 형식을 깨는 문자가 있으면 거부
func validatePath(_ path: String) -> String? {
    let p = path.trimmingCharacters(in: .whitespaces)
    if p.isEmpty { return nil }
    if p.rangeOfCharacter(from: CharacterSet(charactersIn: "\t\r\n")) != nil {
        alert("탭·줄바꿈이 들어간 경로는 즐겨찾기에 넣을 수 없어", p); return nil
    }
    return p
}

func saveFavorites(_ favs: [Favorite?]) throws {
    var text = favoritesHeader
    for f in favs { text += f.map { "\($0.name)\t\($0.path)\n" } ?? "\n" }   // 입력 단계에서 검증한다
    do { try text.write(to: favoritesURL, atomically: true, encoding: .utf8) }
    catch { throw FavError.write(error.localizedDescription) }
}

func showFavError(_ e: Error) {
    switch e {
    case FavError.read(let m): alert("즐겨찾기 파일을 못 읽었어 — 저장하지 않았어", m)
    case FavError.write(let m): alert("즐겨찾기 파일 저장 실패", m)
    default: alert("즐겨찾기 오류", e.localizedDescription)
    }
}

// 파일을 다시 읽어서 고친다. 메뉴를 연 뒤 파일이 바뀌었어도 원래 고른 항목(이름+경로)을 찾아서 고친다.
func mutateFavorites(_ change: (inout [Favorite?]) -> Bool) {
    do {
        var favs = try loadFavorites()
        guard change(&favs) else { return }
        try saveFavorites(favs)
    } catch { showFavError(error) }
}

func appendFavorite(name: String, path: String) {
    guard let path = validatePath(path) else { return }
    let f = Favorite(name: name, path: path)
    mutateFavorites { favs in
        // 같은 이름+경로가 두 개면 관리 메뉴에서 구분할 수 없으므로 막는다
        if favs.contains(f) { alert("이미 같은 즐겨찾기가 있어", "\(name)\n\(path)"); return false }
        favs.append(f); return true
    }
}

// 바깥을 감싼 같은 따옴표 한 쌍만 벗긴다(경로 안의 따옴표는 남긴다)
func stripWrapping(_ s: String) -> String {
    var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    for q in ["\"", "'"] where t.count >= 2 && t.hasPrefix(q) && t.hasSuffix(q) {
        t = String(t.dropFirst().dropLast()); break
    }
    return t
}

func looksLikeSharePath(_ s: String) -> Bool {
    let t = stripWrapping(s)
    return t.hasPrefix("\\\\") || t.hasPrefix("//") || t.lowercased().hasPrefix("smb://")
}

func clipboardText() -> String? {
    guard let s = NSPasteboard.general.string(forType: .string) else { return nil }
    let first = s.components(separatedBy: .newlines).first ?? ""
    let t = stripWrapping(first)
    return t.isEmpty ? nil : t
}

// /Volumes/<마운트>/하위 → \\호스트\공유\하위 (mount 표에서 원본을 찾는다)
func uncPath(forLocal local: String) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/sbin/mount")
    let pipe = Pipe(); p.standardOutput = pipe
    guard (try? p.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()   // 파이프가 차서 멈추지 않게 먼저 다 읽는다
    p.waitUntilExit()
    let out = String(data: data, encoding: .utf8) ?? ""
    var best: (mp: String, host: String, share: String)?
    for line in out.components(separatedBy: "\n") where line.contains("(smbfs") {
        guard let onR = line.range(of: " on "), let parR = line.range(of: " (smbfs") else { continue }
        let src = String(line[..<onR.lowerBound])            // //user@host/share
        let mp = String(line[onR.upperBound..<parR.lowerBound])
        guard local == mp || local.hasPrefix(mp + "/") else { continue }
        var s = src.hasPrefix("//") ? String(src.dropFirst(2)) : src
        if let at = s.firstIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        let comps = s.split(separator: "/", maxSplits: 1).map(String.init)
        guard comps.count == 2 else { continue }
        let share = comps[1].removingPercentEncoding ?? comps[1]
        if best == nil || mp.count > best!.mp.count { best = (mp, comps[0], share) }
    }
    guard let b = best else { return nil }
    var sub = String(local.dropFirst(b.mp.count))
    if sub.hasPrefix("/") { sub.removeFirst() }
    if sub.hasSuffix("/") { sub.removeLast() }
    var unc = "\\\\\(b.host)\\\(b.share)"
    if !sub.isEmpty { unc += "\\" + sub.replacingOccurrences(of: "/", with: "\\") }
    return unc
}

func frontFinderFolder() -> String? {
    let src = """
    tell application "Finder"
      if (count of Finder windows) is 0 then return ""
      return POSIX path of (target of front Finder window as alias)
    end tell
    """
    return runOsascript(src)
}

// 파인더에 묻는 AppleScript. 권한 창이 떠 있어도 메뉴가 멈추지 않게 메인 스레드 밖에서만 부른다.
func runOsascript(_ src: String, timeout: TimeInterval = 10) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", src]
    let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
    guard (try? p.run()) != nil else { return nil }
    let deadline = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    if p.isRunning { p.terminate(); return nil }
    let r = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return r.isEmpty ? nil : r
}

func finderSelection() -> String? {
    let src = """
    tell application "Finder"
      set s to selection
      if (count of s) is 0 then return ""
      return POSIX path of (item 1 of s as alias)
    end tell
    """
    return runOsascript(src)
}

func onBackground(_ work: @escaping () -> Void) { DispatchQueue.global(qos: .userInitiated).async(execute: work) }
func onMain(_ work: @escaping () -> Void) { DispatchQueue.main.async(execute: work) }

func alert(_ title: String, _ msg: String = "") {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert(); a.messageText = title; a.informativeText = msg; a.runModal()
}

func prompt(_ title: String, _ msg: String, initial: String) -> String? {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert(); a.messageText = title; a.informativeText = msg
    a.addButton(withTitle: "확인"); a.addButton(withTitle: "취소")
    let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
    f.stringValue = initial
    a.accessoryView = f
    a.window.initialFirstResponder = f
    guard a.runModal() == .alertFirstButtonReturn else { return nil }
    let v = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return v.isEmpty ? nil : v
}

func defaultName(for path: String) -> String {
    let parts = path.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
    return parts.last.map(String.init) ?? path
}

let tabDefaultsKey = "openInNewTab"

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var item: NSStatusItem!
    let menu = NSMenu()
    var openInNewTab: Bool {
        get { UserDefaults.standard.object(forKey: tabDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: tabDefaultsKey) }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "folder.badge.questionmark", accessibilityDescription: "윈도우경로열기") {
            img.isTemplate = true
            item.button?.image = img
        } else {
            item.button?.title = "\\\\"
        }
        item.button?.toolTip = "윈도우 경로 열기"
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        _ = try? readFavoritesText()   // 처음 실행이면 빈 즐겨찾기 파일 생성
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let clip = clipboardText()
        let clipOK = clip.map(looksLikeSharePath) ?? false
        let preview = clipOK ? "  (\(clip!.count > 50 ? String(clip!.prefix(50)) + "…" : clip!))" : ""
        add("클립보드 경로 열기" + preview, #selector(openClipboard), key: "o", enabled: clipOK)
        add("경로 입력해서 열기…", #selector(openTyped), key: "l")
        add("파인더 선택 항목의 윈도우 경로 복사", #selector(copyUNC), key: "c")
        menu.addItem(.separator())

        let header = NSMenuItem(title: "즐겨찾기", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        var favs: [Favorite?] = []
        var loadError: Error?
        do { favs = try loadFavorites() } catch { loadError = error }
        if loadError != nil || favs.isEmpty {
            let e = NSMenuItem(title: loadError == nil ? "  (비어 있음)" : "  (즐겨찾기 파일을 못 읽음)", action: nil, keyEquivalent: "")
            e.isEnabled = false
            menu.addItem(e)
        }
        var n = 0
        for f in favs {
            guard let f = f else { menu.addItem(.separator()); continue }
            n += 1
            let mi = NSMenuItem(title: f.name, action: #selector(openFavorite(_:)),
                                keyEquivalent: n <= 9 ? String(n) : "")
            mi.target = self
            mi.representedObject = f.path
            mi.toolTip = f.path
            if let img = NSImage(systemSymbolName: "folder", accessibilityDescription: nil) { mi.image = img }
            menu.addItem(mi)
        }
        menu.addItem(.separator())

        let addMenu = NSMenu()
        let a1 = NSMenuItem(title: "클립보드 경로", action: #selector(addFromClipboard), keyEquivalent: "")
        a1.target = self; a1.isEnabled = clipOK && loadError == nil; addMenu.addItem(a1)
        let a2 = NSMenuItem(title: "지금 열린 파인더 폴더", action: #selector(addFromFinder), keyEquivalent: "")
        a2.target = self; a2.isEnabled = loadError == nil; addMenu.addItem(a2)
        let addItem = NSMenuItem(title: "즐겨찾기 추가", action: nil, keyEquivalent: "")
        addItem.submenu = addMenu
        menu.addItem(addItem)
        let named = favs.compactMap { $0 }
        if !named.isEmpty {
            let manage = NSMenu()
            for (k, f) in named.enumerated() {
                let sub = NSMenu()
                let actions: [(String, Selector, Bool)] = [
                    ("이름 바꾸기…", #selector(renameFavorite(_:)), true),
                    ("경로 수정…", #selector(editFavoritePath(_:)), true),
                    ("맨 위로", #selector(moveFavoriteTop(_:)), k > 0),
                    ("위로 이동", #selector(moveFavoriteUp(_:)), k > 0),
                    ("아래로 이동", #selector(moveFavoriteDown(_:)), k < named.count - 1),
                    ("맨 아래로", #selector(moveFavoriteBottom(_:)), k < named.count - 1),
                    ("삭제…", #selector(deleteFavorite(_:)), true)]
                for (title, sel, enabled) in actions {
                    if title == "삭제…" || title == "맨 위로" { sub.addItem(.separator()) }
                    let mi = NSMenuItem(title: title, action: sel, keyEquivalent: "")
                    mi.target = self; mi.isEnabled = enabled
                    mi.representedObject = FavRef(f)   // 인덱스 대신 항목 자체로 찾는다
                    sub.addItem(mi)
                }
                let row = NSMenuItem(title: f.name, action: nil, keyEquivalent: "")
                row.submenu = sub
                manage.addItem(row)
            }
            let m = NSMenuItem(title: "즐겨찾기 관리 (이름·순서)", action: nil, keyEquivalent: "")
            m.submenu = manage
            menu.addItem(m)
        }
        add("즐겨찾기 파일 직접 편집…", #selector(editFavorites), key: ",")
        menu.addItem(.separator())

        let tab = NSMenuItem(title: "파인더 새 탭으로 열기", action: #selector(toggleTab), keyEquivalent: "")
        tab.target = self
        tab.state = openInNewTab ? .on : .off
        tab.toolTip = "처음 쓰면 손쉬운 사용 권한이 필요해(시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용)"
        menu.addItem(tab)
        let login = NSMenuItem(title: "로그인 시 자동 실행", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        add("종료", #selector(quit), key: "q")
    }

    @discardableResult
    func add(_ title: String, _ sel: Selector, key: String = "", enabled: Bool = true) -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        mi.target = self; mi.isEnabled = enabled
        menu.addItem(mi)
        return mi
    }

    func run(_ path: String) {
        guard let script = Bundle.main.path(forResource: "winopen", ofType: nil) else {
            alert("winopen 스크립트를 못 찾았어"); return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script, path]
        var env = ProcessInfo.processInfo.environment
        env["WINOPEN_TAB"] = openInNewTab && accessibilityReady() ? "1" : "0"
        p.environment = env
        let log = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/WinOpen.log")
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        if let h = try? FileHandle(forWritingTo: log) {
            h.seekToEndOfFile()
            h.write("\(Date()) 열기: \(path)\n".data(using: .utf8)!)
            p.standardOutput = h; p.standardError = h
        }
        p.terminationHandler = { proc in
            if proc.terminationStatus == 1 || proc.terminationStatus == 2 {
                DispatchQueue.main.async { NSSound.beep() }
            }
        }
        do { try p.run() } catch { alert("실행 실패", error.localizedDescription) }
    }

    @objc func openClipboard() { if let c = clipboardText() { run(c) } }

    @objc func openTyped() {
        let initial = (clipboardText().flatMap { looksLikeSharePath($0) ? $0 : nil }) ?? ""
        if let v = prompt("경로 열기", "\\\\서버\\공유\\폴더 형식으로 입력", initial: initial) { run(v) }
    }

    @objc func openFavorite(_ sender: NSMenuItem) {
        if let p = sender.representedObject as? String { run(p) }
    }

    @objc func copyUNC() {
        onBackground {
            let local = finderSelection() ?? frontFinderFolder()
            let unc = local.flatMap(uncPath(forLocal:))
            onMain {
                guard let local = local else {
                    alert("파인더에서 선택된 항목이 없어", "처음이면 파인더 제어 권한을 허용해야 해(시스템 설정 → 개인정보 보호 및 보안 → 자동화)."); return
                }
                guard let unc = unc else { alert("공유 폴더(SMB) 안의 항목이 아니야", local); return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(unc, forType: .string)
            }
        }
    }

    @objc func addFromClipboard() {
        guard let c = clipboardText(), looksLikeSharePath(c) else { return }
        if let raw = prompt("즐겨찾기 이름", c, initial: defaultName(for: c)), let name = validateName(raw) {
            appendFavorite(name: name, path: c)
        }
    }

    @objc func addFromFinder() {
        onBackground {
            let local = frontFinderFolder()
            let unc = local.flatMap(uncPath(forLocal:))
            onMain {
                guard let local = local else {
                    alert("열린 파인더 창이 없어", "처음이면 파인더 제어 권한을 허용해야 해(시스템 설정 → 개인정보 보호 및 보안 → 자동화)."); return
                }
                guard let unc = unc else { alert("공유 폴더(SMB) 안의 폴더가 아니야", local); return }
                if let raw = prompt("즐겨찾기 이름", unc, initial: defaultName(for: unc)), let name = validateName(raw) {
                    appendFavorite(name: name, path: unc)
                }
            }
        }
    }

    // 파일을 다시 읽어 고른 항목을 찾아 고친다. 그 사이 파일에서 사라졌으면 알리고 멈춘다.
    func edit(_ sender: NSMenuItem, _ change: (inout [Favorite?], Int) -> Void) {
        guard let ref = sender.representedObject as? FavRef else { return }
        mutateFavorites { favs in
            // 이름+경로가 정확히 하나일 때만 고친다(파일을 손으로 고쳐 중복이 생겼으면 멈춘다)
            let hits = favs.indices.filter { favs[$0] == ref.fav }
            guard hits.count == 1, let i = hits.first else {
                alert(hits.isEmpty ? "그 즐겨찾기를 찾을 수 없어" : "같은 즐겨찾기가 여러 개야",
                      hits.isEmpty ? "파일이 그 사이 바뀌었어. 메뉴를 다시 열어 줘." : "파일에서 직접 하나를 지워 줘.")
                return false
            }
            let before = favs
            change(&favs, i)
            let named = favs.compactMap { $0 }
            if Set(named.map { "\($0.name)\t\($0.path)" }).count != named.count && Set(before.compactMap { $0 }.map { "\($0.name)\t\($0.path)" }).count == before.compactMap({ $0 }).count {
                alert("이미 같은 즐겨찾기가 있어"); return false
            }
            return true
        }
    }

    @objc func renameFavorite(_ sender: NSMenuItem) {
        guard let f = (sender.representedObject as? FavRef)?.fav,
              let raw = prompt("즐겨찾기 이름 바꾸기", f.path, initial: f.name),
              let name = validateName(raw) else { return }
        edit(sender) { favs, i in favs[i] = Favorite(name: name, path: f.path) }
    }

    @objc func editFavoritePath(_ sender: NSMenuItem) {
        guard let f = (sender.representedObject as? FavRef)?.fav,
              let raw = prompt("경로 수정", f.name, initial: f.path),
              let path = validatePath(raw) else { return }
        edit(sender) { favs, i in favs[i] = Favorite(name: f.name, path: path) }
    }

    func move(_ sender: NSMenuItem, by d: Int) {   // d = ±1 한 칸, ±Int.max 끝까지
        edit(sender) { favs, i in
            let f = favs.remove(at: i)
            var j = i
            if abs(d) == Int.max {
                j = d < 0 ? 0 : favs.count
            } else {
                j = i + (d < 0 ? -1 : 0)
                // 구분선은 건너뛴다: 다음 이름 있는 항목 너머로 옮긴다
                if d < 0 { while j > 0, favs[j] == nil { j -= 1 } }
                else { while j < favs.count, favs[j] == nil { j += 1 }; j = min(j + 1, favs.count) }
                j = max(0, j)
            }
            favs.insert(f, at: j)
        }
    }
    @objc func moveFavoriteTop(_ sender: NSMenuItem) { move(sender, by: -Int.max) }
    @objc func moveFavoriteUp(_ sender: NSMenuItem) { move(sender, by: -1) }
    @objc func moveFavoriteDown(_ sender: NSMenuItem) { move(sender, by: 1) }
    @objc func moveFavoriteBottom(_ sender: NSMenuItem) { move(sender, by: Int.max) }

    @objc func deleteFavorite(_ sender: NSMenuItem) {
        guard let f = (sender.representedObject as? FavRef)?.fav else { return }
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = "「\(f.name)」 즐겨찾기를 지울까?"; a.informativeText = f.path
        a.addButton(withTitle: "삭제"); a.addButton(withTitle: "취소")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        edit(sender) { favs, i in favs.remove(at: i) }
    }

    @objc func editFavorites() {
        _ = try? readFavoritesText()
        NSWorkspace.shared.open([favoritesURL],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    // 새 탭은 ⌘T 를 보내야 해서 손쉬운 사용 권한이 필요하다. 없으면 한 번 요청하고 이번엔 새 창으로 연다.
    var askedAccessibility = false
    func accessibilityReady() -> Bool {
        if AXIsProcessTrusted() { return true }
        if !askedAccessibility {
            askedAccessibility = true
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        }
        return false
    }

    @objc func toggleTab() {
        openInNewTab.toggle()
        if openInNewTab { askedAccessibility = false; _ = accessibilityReady() }
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { alert("로그인 항목 설정 실패", error.localizedDescription) }
    }

    @objc func quit() { NSApp.terminate(nil) }
}

final class FavRef: NSObject { let fav: Favorite; init(_ f: Favorite) { fav = f } }

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
