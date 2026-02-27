#!/usr/bin/env swift

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum AXScriptError: Error, CustomStringConvertible {
    case usage(String)
    case notTrusted
    case appNotRunning(String)
    case elementNotFound(String)
    case missingFrame(String)
    case actionFailed(String)

    var description: String {
        switch self {
        case let .usage(message):
            return message
        case .notTrusted:
            return "Accessibility permission is required for Terminal. Grant permission in System Settings > Privacy & Security > Accessibility."
        case let .appNotRunning(bundleID):
            return "No running app found for bundle id: \(bundleID)"
        case let .elementNotFound(selector):
            return "Element not found: \(selector)"
        case let .missingFrame(selector):
            return "Element found but frame is unavailable: \(selector)"
        case let .actionFailed(reason):
            return "Action failed: \(reason)"
        }
    }
}

struct ParsedArguments {
    let command: String
    let options: [String: String]
}

private func parseArguments() throws -> ParsedArguments {
    var args = CommandLine.arguments
    guard args.count >= 2 else {
        throw AXScriptError.usage(usageText())
    }
    args.removeFirst()
    let command = args.removeFirst()

    var options: [String: String] = [:]
    var index = 0
    while index < args.count {
        let token = args[index]
        if token.hasPrefix("--") {
            let key = String(token.dropFirst(2))
            let nextIndex = index + 1
            if nextIndex < args.count, !args[nextIndex].hasPrefix("--") {
                options[key] = args[nextIndex]
                index += 2
            } else {
                options[key] = "true"
                index += 1
            }
        } else {
            index += 1
        }
    }
    return ParsedArguments(command: command, options: options)
}

private func usageText() -> String {
    """
    Usage:
      macos_ax.swift tap-id --bundle-id <id> --id <axIdentifier> [--timeout <seconds>]
      macos_ax.swift tap-prefix --bundle-id <id> --prefix <idPrefix> [--suffix <idSuffix>] [--contains-id <substring>] [--timeout <seconds>]
      macos_ax.swift tap-text --bundle-id <id> --contains <text> [--field any|label|title|value|description|identifier] [--role <AXRole>] [--timeout <seconds>]
      macos_ax.swift wait-id --bundle-id <id> --id <axIdentifier> [--timeout <seconds>]
      macos_ax.swift find-text --bundle-id <id> --contains <text> [--field any|label|title|value|description|identifier] [--role <AXRole>] [--timeout <seconds>]
      macos_ax.swift get-id --bundle-id <id> --id <axIdentifier> [--timeout <seconds>]
      macos_ax.swift wiggle-id --bundle-id <id> --id <axIdentifier> [--seconds <seconds>] [--interval-ms <ms>] [--amplitude <px>]
      macos_ax.swift wiggle-text --bundle-id <id> --contains <text> [--field any|label|title|value|description|identifier] [--role <AXRole>] [--seconds <seconds>] [--interval-ms <ms>] [--amplitude <px>] [--timeout <seconds>]
      macos_ax.swift list-ids --bundle-id <id> [--contains <text>] [--timeout <seconds>]
      macos_ax.swift list-text --bundle-id <id> [--contains <text>] [--limit <n>] [--timeout <seconds>]
      macos_ax.swift window-count --bundle-id <id> [--timeout <seconds>]
    """
}

private func requireOption(_ key: String, in options: [String: String]) throws -> String {
    guard let value = options[key], !value.isEmpty else {
        throw AXScriptError.usage("Missing required option --\(key)\n\n\(usageText())")
    }
    return value
}

private func optionDouble(_ key: String, options: [String: String], fallback: Double) -> Double {
    guard let raw = options[key], let value = Double(raw) else { return fallback }
    return value
}

private func optionInt(_ key: String, options: [String: String], fallback: Int) -> Int {
    guard let raw = options[key], let value = Int(raw) else { return fallback }
    return value
}

private func ensureAccessibilityTrust(prompt: Bool = true) throws {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let options: CFDictionary = [promptKey: prompt] as CFDictionary
    guard AXIsProcessTrustedWithOptions(options) else {
        throw AXScriptError.notTrusted
    }
}

private func runningApplication(bundleID: String, timeout: TimeInterval) -> NSRunningApplication? {
    let deadline = Date().addingTimeInterval(max(0.1, timeout))
    repeat {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app
        }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return nil
}

private func bringToFront(_ app: NSRunningApplication) {
    _ = app.activate(options: [.activateAllWindows])
    Thread.sleep(forTimeInterval: 0.2)
}

private func copyAttribute(_ element: AXUIElement, name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    guard result == .success else { return nil }
    return value
}

private func stringAttribute(_ element: AXUIElement, name: String) -> String? {
    guard let value = copyAttribute(element, name: name) else { return nil }
    if let string = value as? String {
        return string
    }
    if let attributed = value as? NSAttributedString {
        return attributed.string
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    return String(describing: value)
}

private func boolAttribute(_ element: AXUIElement, name: String) -> Bool? {
    if let number = copyAttribute(element, name: name) as? NSNumber {
        return number.boolValue
    }
    return nil
}

private func frameAttribute(_ element: AXUIElement) -> CGRect? {
    guard let value = copyAttribute(element, name: "AXFrame") else { return nil }
    guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    let axValue = unsafeBitCast(value, to: AXValue.self)
    guard AXValueGetType(axValue) == .cgRect else { return nil }
    var rect = CGRect.zero
    guard AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
    return rect
}

private func elementAddress(_ element: AXUIElement) -> String {
    String(describing: Unmanaged.passUnretained(element).toOpaque())
}

private let childAttributeNames: [String] = [
    kAXChildrenAttribute as String,
    "AXVisibleChildren",
    "AXContents",
    "AXRows",
    "AXTabs",
    "AXGroups",
    "AXWindows",
    "AXSheet",
    "AXSheets",
    "AXToolbar",
    "AXMenuBar",
]

private func childElements(of element: AXUIElement) -> [AXUIElement] {
    var results: [AXUIElement] = []

    for attribute in childAttributeNames {
        guard let value = copyAttribute(element, name: attribute) else { continue }
        let valueType = CFGetTypeID(value)
        if valueType == AXUIElementGetTypeID() {
            results.append(unsafeBitCast(value, to: AXUIElement.self))
            continue
        }
        if valueType == CFArrayGetTypeID() {
            let children = unsafeBitCast(value, to: CFArray.self) as NSArray
            for child in children {
                let cfChild = child as CFTypeRef
                guard CFGetTypeID(cfChild) == AXUIElementGetTypeID() else { continue }
                results.append(unsafeBitCast(cfChild, to: AXUIElement.self))
            }
        }
    }

    var deduplicated: [AXUIElement] = []
    var seen: Set<String> = []
    for element in results {
        let key = elementAddress(element)
        if seen.insert(key).inserted {
            deduplicated.append(element)
        }
    }
    return deduplicated
}

private func windowCount(for appElement: AXUIElement) -> Int {
    guard let value = copyAttribute(appElement, name: "AXWindows") else { return 0 }
    guard CFGetTypeID(value) == CFArrayGetTypeID() else { return 0 }
    let windows = unsafeBitCast(value, to: CFArray.self) as NSArray
    var count = 0
    for child in windows {
        let cfChild = child as CFTypeRef
        if CFGetTypeID(cfChild) == AXUIElementGetTypeID() {
            count += 1
        }
    }
    return count
}

struct AXNodeSnapshot {
    let element: AXUIElement
    let identifier: String?
    let role: String?
    let label: String?
    let title: String?
    let value: String?
    let description: String?
    let enabled: Bool?
    let frame: CGRect?
}

private func snapshot(of element: AXUIElement) -> AXNodeSnapshot {
    AXNodeSnapshot(
        element: element,
        identifier: stringAttribute(element, name: kAXIdentifierAttribute as String),
        role: stringAttribute(element, name: kAXRoleAttribute as String),
        label: stringAttribute(element, name: "AXLabel"),
        title: stringAttribute(element, name: kAXTitleAttribute as String),
        value: stringAttribute(element, name: kAXValueAttribute as String),
        description: stringAttribute(element, name: kAXDescriptionAttribute as String),
        enabled: boolAttribute(element, name: kAXEnabledAttribute as String),
        frame: frameAttribute(element)
    )
}

private func walkTree(root: AXUIElement, maxDepth: Int = 20, maxNodes: Int = 20_000) -> [AXNodeSnapshot] {
    var queue: [(AXUIElement, Int)] = [(root, 0)]
    var visited: Set<String> = [elementAddress(root)]
    var snapshots: [AXNodeSnapshot] = []

    while !queue.isEmpty, snapshots.count < maxNodes {
        let (current, depth) = queue.removeFirst()
        snapshots.append(snapshot(of: current))

        guard depth < maxDepth else { continue }
        let children = childElements(of: current)
        for child in children {
            let key = elementAddress(child)
            if visited.insert(key).inserted {
                queue.append((child, depth + 1))
            }
        }
    }
    return snapshots
}

private func findNode(
    in snapshots: [AXNodeSnapshot],
    matching: (AXNodeSnapshot) -> Bool
) -> AXNodeSnapshot? {
    snapshots.first(where: matching)
}

private func textMatches(
    _ node: AXNodeSnapshot,
    contains needle: String,
    field: String,
    role: String?
) -> Bool {
    if let role, node.role != role {
        return false
    }

    let lowerNeedle = needle.lowercased()

    switch field {
    case "label":
        return (node.label ?? "").lowercased().contains(lowerNeedle)
    case "title":
        return (node.title ?? "").lowercased().contains(lowerNeedle)
    case "value":
        return (node.value ?? "").lowercased().contains(lowerNeedle)
    case "description":
        return (node.description ?? "").lowercased().contains(lowerNeedle)
    case "identifier":
        return (node.identifier ?? "").lowercased().contains(lowerNeedle)
    default:
        let haystack = [
            node.label ?? "",
            node.title ?? "",
            node.value ?? "",
            node.description ?? "",
            node.identifier ?? "",
        ].joined(separator: "\n").lowercased()
        return haystack.contains(lowerNeedle)
    }
}

private func findNodeByText(
    appElement: AXUIElement,
    contains needle: String,
    field: String,
    role: String?,
    timeout: TimeInterval
) -> AXNodeSnapshot? {
    let deadline = Date().addingTimeInterval(max(0.1, timeout))
    repeat {
        let nodes = walkTree(root: appElement)
        if let node = nodes.first(where: { textMatches($0, contains: needle, field: field, role: role) }) {
            return node
        }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return nil
}

private func findNodeByID(
    appElement: AXUIElement,
    id: String,
    timeout: TimeInterval
) -> AXNodeSnapshot? {
    let deadline = Date().addingTimeInterval(max(0.1, timeout))
    repeat {
        let nodes = walkTree(root: appElement)
        if let node = findNode(in: nodes, matching: { $0.identifier == id }) {
            return node
        }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return nil
}

private func findNodeByPrefix(
    appElement: AXUIElement,
    prefix: String,
    suffix: String?,
    idContains: String?,
    timeout: TimeInterval
) -> AXNodeSnapshot? {
    let deadline = Date().addingTimeInterval(max(0.1, timeout))
    repeat {
        let nodes = walkTree(root: appElement)
        if let node = nodes
            .filter({ snapshot in
                guard let identifier = snapshot.identifier else { return false }
                guard identifier.hasPrefix(prefix) else { return false }
                if let suffix, !identifier.hasSuffix(suffix) {
                    return false
                }
                if let idContains, !identifier.contains(idContains) {
                    return false
                }
                return true
            })
            .sorted(by: { ($0.identifier ?? "") < ($1.identifier ?? "") })
            .first {
            return node
        }
        Thread.sleep(forTimeInterval: 0.2)
    } while Date() < deadline
    return nil
}

private func performTap(on node: AXNodeSnapshot) throws {
    let pressResult = AXUIElementPerformAction(node.element, kAXPressAction as CFString)
    if pressResult == .success {
        return
    }

    guard let frame = node.frame else {
        throw AXScriptError.missingFrame(node.identifier ?? "(unknown)")
    }

    let center = CGPoint(x: frame.midX, y: frame.midY)
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
        throw AXScriptError.actionFailed("Failed to create event source")
    }

    let moved = CGEvent(
        mouseEventSource: source,
        mouseType: .mouseMoved,
        mouseCursorPosition: center,
        mouseButton: .left
    )
    let down = CGEvent(
        mouseEventSource: source,
        mouseType: .leftMouseDown,
        mouseCursorPosition: center,
        mouseButton: .left
    )
    let up = CGEvent(
        mouseEventSource: source,
        mouseType: .leftMouseUp,
        mouseCursorPosition: center,
        mouseButton: .left
    )

    moved?.post(tap: .cghidEventTap)
    usleep(10_000)
    down?.post(tap: .cghidEventTap)
    usleep(10_000)
    up?.post(tap: .cghidEventTap)
}

private func performWiggle(
    center: CGPoint,
    seconds: TimeInterval,
    intervalMS: Int,
    amplitude: CGFloat
) throws {
    guard let source = CGEventSource(stateID: .combinedSessionState) else {
        throw AXScriptError.actionFailed("Failed to create event source")
    }
    let boundedIntervalMS = max(8, intervalMS)
    let stepCount = max(1, Int((seconds * 1000.0) / Double(boundedIntervalMS)))

    for step in 0..<stepCount {
        let theta = Double(step) * 0.35
        let point = CGPoint(
            x: center.x + amplitude * CGFloat(cos(theta)),
            y: center.y + amplitude * CGFloat(sin(theta * 1.13))
        )
        let event = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
        usleep(useconds_t(boundedIntervalMS * 1_000))
    }
}

private func run() throws {
    let parsed = try parseArguments()
    let timeout = optionDouble("timeout", options: parsed.options, fallback: 8.0)
    let bundleID = try requireOption("bundle-id", in: parsed.options)

    try ensureAccessibilityTrust()
    guard let app = runningApplication(bundleID: bundleID, timeout: timeout) else {
        throw AXScriptError.appNotRunning(bundleID)
    }
    bringToFront(app)
    let appElement = AXUIElementCreateApplication(app.processIdentifier)

    switch parsed.command {
    case "tap-id":
        let id = try requireOption("id", in: parsed.options)
        guard let node = findNodeByID(appElement: appElement, id: id, timeout: timeout) else {
            throw AXScriptError.elementNotFound("id=\(id)")
        }
        try performTap(on: node)
        print("tapped-id \(id)")

    case "tap-prefix":
        let prefix = try requireOption("prefix", in: parsed.options)
        let suffix = parsed.options["suffix"]
        let idContains = parsed.options["contains-id"]
        guard let node = findNodeByPrefix(
            appElement: appElement,
            prefix: prefix,
            suffix: suffix,
            idContains: idContains,
            timeout: timeout
        ) else {
            throw AXScriptError.elementNotFound("prefix=\(prefix)")
        }
        try performTap(on: node)
        print("tapped-prefix \(node.identifier ?? prefix)")

    case "wait-id":
        let id = try requireOption("id", in: parsed.options)
        guard let node = findNodeByID(appElement: appElement, id: id, timeout: timeout) else {
            throw AXScriptError.elementNotFound("id=\(id)")
        }
        let role = node.role ?? "unknown"
        print("found-id \(id) role=\(role)")

    case "tap-text":
        let needle = try requireOption("contains", in: parsed.options)
        let field = parsed.options["field"] ?? "any"
        let role = parsed.options["role"]
        guard let node = findNodeByText(
            appElement: appElement,
            contains: needle,
            field: field,
            role: role,
            timeout: timeout
        ) else {
            throw AXScriptError.elementNotFound("contains=\(needle), field=\(field), role=\(role ?? "any")")
        }
        try performTap(on: node)
        print("tapped-text contains=\(needle) role=\(node.role ?? "unknown") title=\(node.title ?? "")")

    case "find-text":
        let needle = try requireOption("contains", in: parsed.options)
        let field = parsed.options["field"] ?? "any"
        let role = parsed.options["role"]
        guard let node = findNodeByText(
            appElement: appElement,
            contains: needle,
            field: field,
            role: role,
            timeout: timeout
        ) else {
            throw AXScriptError.elementNotFound("contains=\(needle), field=\(field), role=\(role ?? "any")")
        }
        print("identifier=\(node.identifier ?? "")")
        print("role=\(node.role ?? "")")
        print("label=\(node.label ?? "")")
        print("title=\(node.title ?? "")")
        print("value=\(node.value ?? "")")
        print("description=\(node.description ?? "")")

    case "get-id":
        let id = try requireOption("id", in: parsed.options)
        guard let node = findNodeByID(appElement: appElement, id: id, timeout: timeout) else {
            throw AXScriptError.elementNotFound("id=\(id)")
        }
        let title = node.title ?? ""
        let value = node.value ?? ""
        let role = node.role ?? ""
        let desc = node.description ?? ""
        print("id=\(id)")
        print("role=\(role)")
        print("title=\(title)")
        print("value=\(value)")
        print("description=\(desc)")

    case "wiggle-id":
        let id = try requireOption("id", in: parsed.options)
        let seconds = optionDouble("seconds", options: parsed.options, fallback: 20)
        let intervalMS = optionInt("interval-ms", options: parsed.options, fallback: 28)
        let amplitude = CGFloat(optionDouble("amplitude", options: parsed.options, fallback: 24))
        guard let node = findNodeByID(appElement: appElement, id: id, timeout: timeout) else {
            throw AXScriptError.elementNotFound("id=\(id)")
        }
        guard let frame = node.frame else {
            throw AXScriptError.missingFrame("id=\(id)")
        }
        try performWiggle(
            center: CGPoint(x: frame.midX, y: frame.midY),
            seconds: seconds,
            intervalMS: intervalMS,
            amplitude: amplitude
        )
        print("wiggle-complete id=\(id) seconds=\(seconds)")

    case "wiggle-text":
        let needle = try requireOption("contains", in: parsed.options)
        let field = parsed.options["field"] ?? "any"
        let role = parsed.options["role"]
        let seconds = optionDouble("seconds", options: parsed.options, fallback: 20)
        let intervalMS = optionInt("interval-ms", options: parsed.options, fallback: 28)
        let amplitude = CGFloat(optionDouble("amplitude", options: parsed.options, fallback: 24))
        guard let node = findNodeByText(
            appElement: appElement,
            contains: needle,
            field: field,
            role: role,
            timeout: timeout
        ) else {
            throw AXScriptError.elementNotFound("contains=\(needle), field=\(field), role=\(role ?? "any")")
        }
        guard let frame = node.frame else {
            throw AXScriptError.missingFrame("contains=\(needle)")
        }
        try performWiggle(
            center: CGPoint(x: frame.midX, y: frame.midY),
            seconds: seconds,
            intervalMS: intervalMS,
            amplitude: amplitude
        )
        print("wiggle-complete contains=\(needle) seconds=\(seconds)")

    case "list-ids":
        let contains = parsed.options["contains"] ?? ""
        let nodes = walkTree(root: appElement)
            .filter { snapshot in
                guard let id = snapshot.identifier, !id.isEmpty else { return false }
                return contains.isEmpty ? true : id.contains(contains)
            }
            .sorted { ($0.identifier ?? "") < ($1.identifier ?? "") }

        for node in nodes {
            print(node.identifier ?? "")
        }
        print("total=\(nodes.count)")

    case "list-text":
        let contains = (parsed.options["contains"] ?? "").lowercased()
        let limit = max(1, optionInt("limit", options: parsed.options, fallback: 200))
        let nodes = walkTree(root: appElement)
        var emitted = 0
        for node in nodes {
            let title = node.title ?? ""
            let label = node.label ?? ""
            let value = node.value ?? ""
            let description = node.description ?? ""
            let identifier = node.identifier ?? ""
            let merged = [label, title, value, description, identifier].joined(separator: " ").lowercased()
            if !contains.isEmpty && !merged.contains(contains) {
                continue
            }
            if label.isEmpty && title.isEmpty && value.isEmpty && description.isEmpty && identifier.isEmpty {
                continue
            }
            print("role=\(node.role ?? "") | id=\(identifier) | label=\(label) | title=\(title) | value=\(value) | description=\(description)")
            emitted += 1
            if emitted >= limit {
                break
            }
        }
        print("total=\(emitted)")

    case "window-count":
        print(windowCount(for: appElement))

    default:
        throw AXScriptError.usage(usageText())
    }
}

do {
    try run()
} catch {
    let message: String
    if let axError = error as? AXScriptError {
        message = axError.description
    } else {
        message = error.localizedDescription
    }
    fputs("error: \(message)\n", stderr)
    exit(1)
}
