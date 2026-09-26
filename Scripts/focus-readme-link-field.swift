import AppKit
import ApplicationServices
import CoreFoundation
import Foundation

private let bundleIdentifier = "com.captiongrab.app"
private let expectedPlaceholder = "Paste or drag a YouTube link here"

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

private let maximumAccessibilityTraversalDepth = 32
private let maximumVisitedAccessibilityNodes = 2_000

private enum AccessibilityTraversalError: Error, Equatable, CustomStringConvertible {
    case depthLimitExceeded(depth: Int)
    case nodeLimitExceeded(limit: Int)
    case childEnumerationFailed

    var description: String {
        switch self {
        case .depthLimitExceeded(let depth):
            return "depth limit exceeded at depth \(depth)"
        case .nodeLimitExceeded(let limit):
            return "node limit of \(limit) exceeded"
        case .childEnumerationFailed:
            return "a node's children could not be enumerated"
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

    print("Accessibility locator self-tests passed.")
}

private func focusAndSetYouTubeLinkField(to videoURL: String) {
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { !$0.isTerminated }
    guard let app = runningApps.first else {
        fail("CaptionGrab is not running; cannot locate its accessible YouTube link field.")
    }

    _ = app.activate(options: [.activateAllWindows])
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    guard let windows = attribute(appElement, kAXWindowsAttribute) as? [AXUIElement], !windows.isEmpty else {
        fail("CaptionGrab's main window is unavailable through Accessibility.")
    }

    let matchingFields: [AXUIElement]
    do {
        matchingFields = try windows.flatMap { try findLinkFields(in: $0) }
    } catch {
        fail("CaptionGrab's accessibility tree was incomplete; refusing to accept a possibly non-unique match (\(error)).")
    }
    guard let linkField = uniqueMatch(matchingFields) else {
        fail("Expected one accessible CaptionGrab YouTube link field; found \(matchingFields.count).")
    }

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
