import AppKit
import ApplicationServices
import CoreFoundation
import Foundation

private let bundleIdentifier = "com.captiongrab.app"
private let expectedPlaceholder = "Paste or drag a YouTube link here"
private let startupReadinessTimeout: TimeInterval = 20
private let startupPollInterval: TimeInterval = 0.25

private struct AccessibilityFieldDescriptor {
    let role: String
    let placeholder: String?
    let valueIsSettable: Bool
}

private func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}

private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
        return nil
    }
    return value
}

private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}

private func isAttributeSettable(_ element: AXUIElement, _ name: String) -> Bool {
    var settable = DarwinBoolean(false)
    return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success
        && settable.boolValue
}

private func isYouTubeLinkField(_ field: AccessibilityFieldDescriptor) -> Bool {
    field.role == kAXTextFieldRole
        && field.placeholder == expectedPlaceholder
        && field.valueIsSettable
}

private func uniqueMatch<T>(_ candidates: [T]) -> T? {
    guard candidates.count == 1 else { return nil }
    return candidates[0]
}

private enum StartupReadinessError: Error, Equatable, CustomStringConvertible {
    case timedOut(timeout: TimeInterval)
    case ambiguousMatches(count: Int)
    case ambiguousApplications(count: Int)

    var description: String {
        switch self {
        case .timedOut(let timeout):
            return "CaptionGrab did not expose one editable YouTube link field within \(timeout) seconds."
        case .ambiguousMatches(let count):
            return "Expected one accessible CaptionGrab YouTube link field; found \(count)."
        case .ambiguousApplications(let count):
            return "Expected one running CaptionGrab app; found \(count)."
        }
    }
}

private func waitForUniqueMatch<Value>(
    timeout: TimeInterval = startupReadinessTimeout,
    pollInterval: TimeInterval = startupPollInterval,
    now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
    candidates: () throws -> [Value]
) throws -> Value {
    let deadline = now() + timeout

    while true {
        let currentCandidates = try candidates()
        guard currentCandidates.count <= 1 else {
            throw StartupReadinessError.ambiguousMatches(count: currentCandidates.count)
        }
        guard now() <= deadline else {
            throw StartupReadinessError.timedOut(timeout: timeout)
        }

        if currentCandidates.count == 1 {
            return currentCandidates[0]
        }

        let remaining = deadline - now()
        guard remaining > 0 else {
            throw StartupReadinessError.timedOut(timeout: timeout)
        }
        sleep(min(pollInterval, remaining))
    }
}

private let maximumAccessibilityTraversalDepth = 32
private let maximumVisitedAccessibilityNodes = 2_000

private enum AccessibilityTraversalError: Error, Equatable, CustomStringConvertible {
    case depthLimitExceeded(depth: Int)
    case nodeLimitExceeded(limit: Int)
    case childEnumerationFailed
    case windowEnumerationFailed(status: Int)

    var description: String {
        switch self {
        case .depthLimitExceeded(let depth):
            return "depth limit exceeded at depth \(depth)"
        case .nodeLimitExceeded(let limit):
            return "node limit of \(limit) exceeded"
        case .childEnumerationFailed:
            return "a node's children could not be enumerated"
        case .windowEnumerationFailed(let status):
            return "CaptionGrab's windows could not be enumerated (AX status \(status))"
        }
    }
}

private func traverseAccessibilityTree<Node>(
    root: Node,
    depthLimit: Int = maximumAccessibilityTraversalDepth,
    nodeLimit: Int = maximumVisitedAccessibilityNodes,
    children: (Node) throws -> [Node],
    matches isMatch: (Node) -> Bool
) throws -> [Node] {
    var matches: [Node] = []
    var pending: [(node: Node, depth: Int)] = [(root, 0)]
    var visitedCount = 0

    while let current = pending.popLast() {
        guard current.depth <= depthLimit else {
            throw AccessibilityTraversalError.depthLimitExceeded(depth: current.depth)
        }
        visitedCount += 1
        guard visitedCount <= nodeLimit else {
            throw AccessibilityTraversalError.nodeLimitExceeded(limit: nodeLimit)
        }

        if isMatch(current.node) {
            matches.append(current.node)
        }
        for child in try children(current.node) {
            pending.append((child, current.depth + 1))
        }
    }

    return matches
}

private func accessibilityChildren(of element: AXUIElement) throws -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
          let value,
          let children = value as? [AXUIElement] else {
        throw AccessibilityTraversalError.childEnumerationFailed
    }
    return children
}

private func findLinkFields(in root: AXUIElement) throws -> [AXUIElement] {
    try traverseAccessibilityTree(
        root: root,
        children: { try accessibilityChildren(of: $0) },
        matches: { element in
            let role = stringAttribute(element, kAXRoleAttribute) ?? ""
            let placeholder = stringAttribute(element, kAXPlaceholderValueAttribute)
            return isYouTubeLinkField(AccessibilityFieldDescriptor(
                role: role,
                placeholder: placeholder,
                valueIsSettable: role == kAXTextFieldRole
                    && placeholder == expectedPlaceholder
                    && isAttributeSettable(element, kAXValueAttribute)
            ))
        }
    )
}

private struct LocatedLinkField {
    let appElement: AXUIElement
    let field: AXUIElement
}

private func accessibilityWindows(of appElement: AXUIElement) throws -> [AXUIElement] {
    var value: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
    if status == .noValue {
        return []
    }
    guard status == .success, let value else {
        throw AccessibilityTraversalError.windowEnumerationFailed(status: Int(status.rawValue))
    }
    guard let windows = value as? [AXUIElement] else {
        throw AccessibilityTraversalError.windowEnumerationFailed(status: Int(status.rawValue))
    }
    return windows
}

private func accessibleLinkFieldCandidates() throws -> [LocatedLinkField] {
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { !$0.isTerminated }
    guard !runningApps.isEmpty else { return [] }
    guard runningApps.count == 1 else {
        throw StartupReadinessError.ambiguousApplications(count: runningApps.count)
    }

    let app = runningApps[0]
    _ = app.activate(options: [.activateAllWindows])
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    _ = AXUIElementSetMessagingTimeout(appElement, 1.0)
    let windows = try accessibilityWindows(of: appElement)

    return try windows.flatMap { window in
        _ = AXUIElementSetMessagingTimeout(window, 1.0)
        return try findLinkFields(in: window).map { LocatedLinkField(appElement: appElement, field: $0) }
    }
}

private final class AccessibilityTraversalFixtureNode {
    let name: String
    let isMatch: Bool
    var children: [AccessibilityTraversalFixtureNode]? = []

    init(_ name: String, isMatch: Bool = false) {
        self.name = name
        self.isMatch = isMatch
    }
}

private func fixtureMatches(
    from root: AccessibilityTraversalFixtureNode,
    depthLimit: Int = maximumAccessibilityTraversalDepth
) throws -> [AccessibilityTraversalFixtureNode] {
    try traverseAccessibilityTree(
        root: root,
        depthLimit: depthLimit,
        children: { node in
            guard let children = node.children else {
                throw AccessibilityTraversalError.childEnumerationFailed
            }
            return children
        },
        matches: { $0.isMatch }
    )
}

private func runLocatorSelfTests() throws {
    let expected = AccessibilityFieldDescriptor(
        role: kAXTextFieldRole,
        placeholder: expectedPlaceholder,
        valueIsSettable: true
    )
    precondition(isYouTubeLinkField(expected), "The expected editable placeholder must match.")
    precondition(
        !isYouTubeLinkField(AccessibilityFieldDescriptor(
            role: kAXTextFieldRole,
            placeholder: expectedPlaceholder,
            valueIsSettable: false
        )),
        "A non-editable text field must not match."
    )
    precondition(
        !isYouTubeLinkField(AccessibilityFieldDescriptor(
            role: "AXTextArea",
            placeholder: expectedPlaceholder,
            valueIsSettable: true
        )),
        "A non-text-field element must not match."
    )
    precondition(
        !isYouTubeLinkField(AccessibilityFieldDescriptor(
            role: kAXTextFieldRole,
            placeholder: "Other field",
            valueIsSettable: true
        )),
        "A text field with a different placeholder must not match."
    )
    precondition(uniqueMatch([expected]) != nil, "A single semantic match must be accepted.")
    precondition(uniqueMatch([AccessibilityFieldDescriptor]()) == nil, "Zero matches must fail closed.")
    precondition(uniqueMatch([expected, expected]) == nil, "Multiple matches must fail closed.")

    let uniqueRoot = AccessibilityTraversalFixtureNode("root")
    let uniqueNode = AccessibilityTraversalFixtureNode("unique", isMatch: true)
    uniqueRoot.children = [uniqueNode]
    let uniqueTraversalMatches = try fixtureMatches(from: uniqueRoot)
    precondition(
        uniqueTraversalMatches.count == 1 && uniqueTraversalMatches.first === uniqueNode,
        "A complete traversal with one semantic match must be accepted."
    )

    let ambiguousRoot = AccessibilityTraversalFixtureNode("root")
    let firstMatch = AccessibilityTraversalFixtureNode("first", isMatch: true)
    let secondMatch = AccessibilityTraversalFixtureNode("second", isMatch: true)
    ambiguousRoot.children = [firstMatch, secondMatch]
    let ambiguousTraversalMatches = try fixtureMatches(from: ambiguousRoot)
    precondition(
        uniqueMatch(ambiguousTraversalMatches) == nil,
        "A complete traversal with multiple semantic matches must fail closed."
    )

    let deepRoot = AccessibilityTraversalFixtureNode("depth-0")
    var deepestNode = deepRoot
    for _ in 1...(maximumAccessibilityTraversalDepth + 1) {
        let child = AccessibilityTraversalFixtureNode("deep-child")
        deepestNode.children = [child]
        deepestNode = child
    }
    do {
        _ = try fixtureMatches(from: deepRoot)
        preconditionFailure("Depth-limit traversal must fail closed.")
    } catch let error as AccessibilityTraversalError {
        precondition(
            error == .depthLimitExceeded(depth: maximumAccessibilityTraversalDepth + 1),
            "Depth-limit traversal must fail closed."
        )
    } catch {
        preconditionFailure("Depth-limit traversal must fail closed: \\(error).")
    }

    let incompleteRoot = AccessibilityTraversalFixtureNode("root")
    let unreadableChildren = AccessibilityTraversalFixtureNode("unreadable-children")
    unreadableChildren.children = nil
    let matchBeforeFailure = AccessibilityTraversalFixtureNode("match-before-failure", isMatch: true)
    incompleteRoot.children = [unreadableChildren, matchBeforeFailure]
    do {
        _ = try fixtureMatches(from: incompleteRoot)
        preconditionFailure("Unreadable child enumeration must fail the whole traversal.")
    } catch let error as AccessibilityTraversalError {
        precondition(
            error == .childEnumerationFailed,
            "Unreadable child enumeration must fail the whole traversal."
        )
    } catch {
        preconditionFailure("Unreadable child enumeration must fail the whole traversal: \\(error).")
    }

    var delayedClock: TimeInterval = 0
    var delayedAttempts = 0
    let delayedField = try waitForUniqueMatch(
        timeout: 1,
        pollInterval: 0.2,
        now: { delayedClock },
        sleep: { delayedClock += $0 },
        candidates: {
            delayedAttempts += 1
            return delayedAttempts >= 3 ? [expected] : []
        }
    )
    precondition(
        isYouTubeLinkField(delayedField),
        "Readiness fixture accepts one delayed exact field."
    )

    var timeoutClock: TimeInterval = 0
    var timeoutAttempts = 0
    do {
        _ = try waitForUniqueMatch(
            timeout: 0.5,
            pollInterval: 0.2,
            now: { timeoutClock },
            sleep: { timeoutClock += $0 },
            candidates: {
                timeoutAttempts += 1
                return [AccessibilityFieldDescriptor]()
            }
        )
        preconditionFailure("Readiness fixture times out when no exact field appears.")
    } catch let error as StartupReadinessError {
        precondition(
            error == .timedOut(timeout: 0.5) && timeoutAttempts > 0,
            "Readiness fixture times out when no exact field appears."
        )
    }

    var ambiguityAttempts = 0
    do {
        _ = try waitForUniqueMatch(
            timeout: 1,
            pollInterval: 0.2,
            now: { 0 },
            sleep: { _ in preconditionFailure("Ambiguous readiness must not sleep.") },
            candidates: {
                ambiguityAttempts += 1
                return [expected, expected]
            }
        )
        preconditionFailure("Ambiguous readiness must fail without retrying.")
    } catch let error as StartupReadinessError {
        precondition(
            error == .ambiguousMatches(count: 2) && ambiguityAttempts == 1,
            "Ambiguous readiness must fail without retrying."
        )
    }

    var enumerationAttempts = 0
    do {
        _ = try waitForUniqueMatch(
            timeout: 1,
            pollInterval: 0.2,
            now: { 0 },
            sleep: { _ in preconditionFailure("Enumeration failure must not sleep.") },
            candidates: {
                enumerationAttempts += 1
                return try fixtureMatches(from: incompleteRoot)
            }
        )
        preconditionFailure("Enumeration failure must fail without retrying.")
    } catch let error as AccessibilityTraversalError {
        precondition(
            error == .childEnumerationFailed && enumerationAttempts == 1,
            "Enumeration failure must fail without retrying."
        )
    }

    print("Accessibility locator self-tests passed.")
}

private func focusAndSetYouTubeLinkField(to videoURL: String) {
    let locatedField: LocatedLinkField
    do {
        locatedField = try waitForUniqueMatch(candidates: {
            try accessibleLinkFieldCandidates()
        })
    } catch let error as AccessibilityTraversalError {
        fail("CaptionGrab's accessibility tree was incomplete; refusing to accept a possibly non-unique match (\(error)).")
    } catch {
        fail("CaptionGrab readiness failed; refusing to submit without one exact accessible YouTube link field (\(error)).")
    }

    let appElement = locatedField.appElement
    let linkField = locatedField.field

    guard AXUIElementSetAttributeValue(
        linkField,
        kAXValueAttribute as CFString,
        videoURL as CFString
    ) == .success else {
        fail("CaptionGrab's accessible YouTube link field rejected the video URL.")
    }

    var hasExpectedValue = false
    for _ in 0..<10 {
        if stringAttribute(linkField, kAXValueAttribute) == videoURL {
            hasExpectedValue = true
            break
        }
        usleep(100_000)
    }
    guard hasExpectedValue else {
        fail("CaptionGrab's accessible YouTube link field did not retain the submitted video URL.")
    }

    guard AXUIElementSetAttributeValue(
        linkField,
        kAXFocusedAttribute as CFString,
        kCFBooleanTrue
    ) == .success else {
        fail("CaptionGrab's accessible YouTube link field did not accept keyboard focus.")
    }

    var hasKeyboardFocus = false
    for _ in 0..<10 {
        if let focusedElement = attribute(appElement, kAXFocusedUIElementAttribute),
           CFEqual(focusedElement, linkField) {
            hasKeyboardFocus = true
            break
        }
        usleep(100_000)
    }
    guard hasKeyboardFocus else {
        fail("CaptionGrab's YouTube link field did not receive keyboard focus.")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--self-test"] {
    do {
        try runLocatorSelfTests()
    } catch {
        fail("Accessibility locator self-tests failed: \\(error).")
    }
} else {
    guard arguments.count == 1 else {
        fail("Exactly one public video URL is required.")
    }
    focusAndSetYouTubeLinkField(to: arguments[0])
}
