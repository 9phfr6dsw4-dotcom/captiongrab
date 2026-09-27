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

private func checkedAttributeValue<Value>(
    status: AXError,
    value: Value?,
    attribute: String
) throws -> Value? {
    switch status {
    case .success:
        guard let value else {
            throw AccessibilityTraversalError.attributeValueMissing(attribute: attribute)
        }
        return value
    case .noValue:
        return nil
    default:
        throw AccessibilityTraversalError.attributeQueryFailed(
            attribute: attribute,
            status: Int(status.rawValue)
        )
    }
}

private func attribute(
    _ element: AXUIElement,
    _ name: String,
    deadline: AccessibilityQueryDeadline? = nil
) throws -> CFTypeRef? {
    var value: CFTypeRef?
    let status = try performBoundedAccessibilityMessage(
        on: element,
        deadline: deadline,
        setMessagingTimeout: { AXUIElementSetMessagingTimeout($0, $1) },
        operation: { _ in
            AXUIElementCopyAttributeValue(element, name as CFString, &value)
        }
    )
    return try checkedAttributeValue(status: status, value: value, attribute: name)
}

private func stringAttribute(
    _ element: AXUIElement,
    _ name: String,
    deadline: AccessibilityQueryDeadline? = nil
) throws -> String? {
    guard let value = try attribute(element, name, deadline: deadline) else {
        return nil
    }
    guard let string = value as? String else {
        throw AccessibilityTraversalError.attributeValueTypeMismatch(attribute: name)
    }
    return string
}

private func isAttributeSettable(
    _ element: AXUIElement,
    _ name: String,
    deadline: AccessibilityQueryDeadline? = nil
) throws -> Bool {
    var settable = DarwinBoolean(false)
    let status = try performBoundedAccessibilityMessage(
        on: element,
        deadline: deadline,
        setMessagingTimeout: { AXUIElementSetMessagingTimeout($0, $1) },
        operation: { _ in
            AXUIElementIsAttributeSettable(element, name as CFString, &settable)
        }
    )
    guard status == .success else {
        throw AccessibilityTraversalError.attributeQueryFailed(
            attribute: name,
            status: Int(status.rawValue)
        )
    }
    return settable.boolValue
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
    now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
    candidates: (AccessibilityQueryDeadline) throws -> [Value]
) throws -> Value {
    let deadline = AccessibilityQueryDeadline(timeout: timeout, now: now)

    while true {
        try deadline.check()
        let currentCandidates = try candidates(deadline)
        try deadline.check()
        guard currentCandidates.count <= 1 else {
            throw StartupReadinessError.ambiguousMatches(count: currentCandidates.count)
        }

        if currentCandidates.count == 1 {
            return currentCandidates[0]
        }

        let remaining = try deadline.remaining()
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
    case attributeQueryFailed(attribute: String, status: Int)
    case attributeValueMissing(attribute: String)
    case attributeValueTypeMismatch(attribute: String)
    case messagingTimeoutFailed(status: Int)

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
        case .attributeQueryFailed(let attribute, let status):
            return "AX attribute \(attribute) could not be queried (AX status \(status))"
        case .attributeValueMissing(let attribute):
            return "AX attribute \(attribute) query succeeded without a value"
        case .attributeValueTypeMismatch(let attribute):
            return "AX attribute \(attribute) returned a value of the wrong type"
        case .messagingTimeoutFailed(let status):
            return "AX messaging timeout could not be set (AX status \(status))"
        }
    }
}

private struct AccessibilityQueryDeadline {
    let timeout: TimeInterval
    let deadline: TimeInterval
    private let now: () -> TimeInterval

    init(timeout: TimeInterval, now: @escaping () -> TimeInterval) {
        self.timeout = timeout
        self.deadline = now() + timeout
        self.now = now
    }

    func remaining() throws -> TimeInterval {
        let remaining = deadline - now()
        guard remaining > 0 else {
            throw StartupReadinessError.timedOut(timeout: timeout)
        }
        return remaining
    }

    func check() throws {
        _ = try remaining()
    }
}

private let maximumAccessibilityMessageTimeout: TimeInterval = 1.0

// AX messaging timeouts are per element; set a bound before every synchronous call.
private func performBoundedAccessibilityMessage<Element, Value>(
    on element: Element,
    deadline: AccessibilityQueryDeadline?,
    setMessagingTimeout: (Element, Float) -> AXError,
    operation: (TimeInterval) throws -> Value
) throws -> Value {
    let allowedDuration = try deadline.map {
        min(maximumAccessibilityMessageTimeout, try $0.remaining())
    } ?? maximumAccessibilityMessageTimeout
    let timeout = Float(allowedDuration)
    let timeoutStatus = setMessagingTimeout(element, timeout)
    guard timeoutStatus == .success else {
        throw AccessibilityTraversalError.messagingTimeoutFailed(
            status: Int(timeoutStatus.rawValue)
        )
    }
    try deadline?.check()
    let value = try operation(TimeInterval(timeout))
    try deadline?.check()
    return value
}

private func traverseAccessibilityTree<Node>(
    root: Node,
    depthLimit: Int = maximumAccessibilityTraversalDepth,
    nodeLimit: Int = maximumVisitedAccessibilityNodes,
    children: (Node) throws -> [Node],
    matches isMatch: (Node) throws -> Bool
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

        if try isMatch(current.node) {
            matches.append(current.node)
        }
        for child in try children(current.node) {
            pending.append((child, current.depth + 1))
        }
    }

    return matches
}

private func accessibilityChildren(
    of element: AXUIElement,
    deadline: AccessibilityQueryDeadline
) throws -> [AXUIElement] {
    guard let value = try attribute(
        element,
        kAXChildrenAttribute as String,
        deadline: deadline
    ), let children = value as? [AXUIElement] else {
        throw AccessibilityTraversalError.childEnumerationFailed
    }
    return children
}

private func findLinkFields(
    in root: AXUIElement,
    deadline: AccessibilityQueryDeadline
) throws -> [AXUIElement] {
    try traverseAccessibilityTree(
        root: root,
        children: { try accessibilityChildren(of: $0, deadline: deadline) },
        matches: { element in
            let role = try stringAttribute(element, kAXRoleAttribute as String, deadline: deadline) ?? ""
            let placeholder = try stringAttribute(
                element,
                kAXPlaceholderValueAttribute as String,
                deadline: deadline
            )
            let valueIsSettable: Bool
            if role == kAXTextFieldRole && placeholder == expectedPlaceholder {
                valueIsSettable = try isAttributeSettable(
                    element,
                    kAXValueAttribute as String,
                    deadline: deadline
                )
            } else {
                valueIsSettable = false
            }
            return isYouTubeLinkField(AccessibilityFieldDescriptor(
                role: role,
                placeholder: placeholder,
                valueIsSettable: valueIsSettable
            ))
        }
    )
}

private struct LocatedLinkField {
    let appElement: AXUIElement
    let field: AXUIElement
}

private func accessibilityWindows(
    of appElement: AXUIElement,
    deadline: AccessibilityQueryDeadline
) throws -> [AXUIElement] {
    guard let value = try attribute(
        appElement,
        kAXWindowsAttribute as String,
        deadline: deadline
    ) else {
        return []
    }
    guard let windows = value as? [AXUIElement] else {
        throw AccessibilityTraversalError.windowEnumerationFailed(
            status: Int(AXError.success.rawValue)
        )
    }
    return windows
}

private func accessibleLinkFieldCandidates(
    deadline: AccessibilityQueryDeadline
) throws -> [LocatedLinkField] {
    let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { !$0.isTerminated }
    guard !runningApps.isEmpty else { return [] }
    guard runningApps.count == 1 else {
        throw StartupReadinessError.ambiguousApplications(count: runningApps.count)
    }

    let app = runningApps[0]
    _ = app.activate(options: [.activateAllWindows])
    let appElement = AXUIElementCreateApplication(app.processIdentifier)
    let windows = try accessibilityWindows(of: appElement, deadline: deadline)

    return try windows.flatMap { window in
        try findLinkFields(in: window, deadline: deadline).map {
            LocatedLinkField(appElement: appElement, field: $0)
        }
    }
}

private final class AccessibilityTraversalFixtureNode {
    let name: String
    let isMatch: Bool
    var children: [AccessibilityTraversalFixtureNode]? = []
    var simulatedMessageDuration: TimeInterval = 0
    var lastMessageTimeout: TimeInterval?
    var messageQueryCount = 0

    init(_ name: String, isMatch: Bool = false) {
        self.name = name
        self.isMatch = isMatch
    }
}

private final class AccessibilityFixtureClock {
    var value: TimeInterval = 0
}

private func fixtureMatches(
    from root: AccessibilityTraversalFixtureNode,
    depthLimit: Int = maximumAccessibilityTraversalDepth,
    deadline: AccessibilityQueryDeadline? = nil,
    clock: AccessibilityFixtureClock? = nil
) throws -> [AccessibilityTraversalFixtureNode] {
    try traverseAccessibilityTree(
        root: root,
        depthLimit: depthLimit,
        children: { node in
            guard let children = node.children else {
                throw AccessibilityTraversalError.childEnumerationFailed
            }
            guard let deadline else { return children }
            return try performBoundedAccessibilityMessage(
                on: node,
                deadline: deadline,
                setMessagingTimeout: { fixtureNode, timeout in
                    fixtureNode.lastMessageTimeout = TimeInterval(timeout)
                    return .success
                },
                operation: { timeout in
                    node.messageQueryCount += 1
                    if let clock {
                        if node.simulatedMessageDuration >= timeout {
                            clock.value = deadline.deadline
                        } else {
                            clock.value += node.simulatedMessageDuration
                        }
                    }
                    return children
                }
            )
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
        candidates: { _ in
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
            candidates: { _ in
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
            candidates: { _ in
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
            candidates: { _ in
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

    var queryErrorAttempts = 0
    do {
        _ = try waitForUniqueMatch(
            timeout: 1,
            pollInterval: 0.2,
            now: { 0 },
            sleep: { _ in preconditionFailure("AX query errors must not be retried as missing attributes.") },
            candidates: { _ in
                queryErrorAttempts += 1
                var candidates = [expected]
                let placeholder: String? = try checkedAttributeValue(
                    status: .cannotComplete,
                    value: nil as String?,
                    attribute: "AXPlaceholderValue"
                )
                if let placeholder {
                    candidates.append(AccessibilityFieldDescriptor(
                        role: kAXTextFieldRole,
                        placeholder: placeholder,
                        valueIsSettable: true
                    ))
                }
                return candidates
            }
        )
        preconditionFailure("AX attribute query failures must not count as non-matches.")
    } catch let error as AccessibilityTraversalError {
        precondition(
            error == .attributeQueryFailed(
                attribute: "AXPlaceholderValue",
                status: Int(AXError.cannotComplete.rawValue)
            ) && queryErrorAttempts == 1,
            "AX attribute query failures must not count as non-matches."
        )
    }

    let slowRoot = AccessibilityTraversalFixtureNode("slow-root")
    let slowDescendant = AccessibilityTraversalFixtureNode("slow-matching-descendant", isMatch: true)
    slowRoot.children = [slowDescendant]
    slowRoot.simulatedMessageDuration = 0.8
    slowDescendant.simulatedMessageDuration = 1.0
    let slowClock = AccessibilityFixtureClock()
    do {
        _ = try waitForUniqueMatch(
            timeout: 1,
            pollInterval: 0.2,
            now: { slowClock.value },
            sleep: { slowClock.value += $0 },
            candidates: { deadline in
                try fixtureMatches(from: slowRoot, deadline: deadline, clock: slowClock)
            }
        )
        preconditionFailure("A slow descendant AX call must be bounded by the remaining startup deadline.")
    } catch let error as StartupReadinessError {
        let descendantTimeout = slowDescendant.lastMessageTimeout ?? 0
        precondition(
            error == .timedOut(timeout: 1)
                && slowDescendant.messageQueryCount == 1
                && descendantTimeout > 0.19
                && descendantTimeout < 0.21,
            "A slow descendant AX call must be bounded by the remaining startup deadline."
        )
    }

    print("Accessibility locator self-tests passed.")
}

private func focusAndSetYouTubeLinkField(to videoURL: String) throws {
    let locatedField: LocatedLinkField
    do {
        locatedField = try waitForUniqueMatch(candidates: { deadline in
            try accessibleLinkFieldCandidates(deadline: deadline)
        })
    } catch let error as AccessibilityTraversalError {
        fail("CaptionGrab's accessibility tree was incomplete; refusing to accept a possibly non-unique match (\(error)).")
    } catch {
        fail("CaptionGrab readiness failed; refusing to submit without one exact accessible YouTube link field (\(error)).")
    }

    let appElement = locatedField.appElement
    let linkField = locatedField.field

    let valueStatus = try performBoundedAccessibilityMessage(
        on: linkField,
        deadline: nil,
        setMessagingTimeout: { AXUIElementSetMessagingTimeout($0, $1) },
        operation: { _ in
            AXUIElementSetAttributeValue(
                linkField,
                kAXValueAttribute as CFString,
                videoURL as CFString
            )
        }
    )
    guard valueStatus == .success else {
        fail("CaptionGrab's accessible YouTube link field rejected the video URL.")
    }

    var hasExpectedValue = false
    for _ in 0..<10 {
        if try stringAttribute(linkField, kAXValueAttribute as String) == videoURL {
            hasExpectedValue = true
            break
        }
        usleep(100_000)
    }
    guard hasExpectedValue else {
        fail("CaptionGrab's accessible YouTube link field did not retain the submitted video URL.")
    }

    let focusStatus = try performBoundedAccessibilityMessage(
        on: linkField,
        deadline: nil,
        setMessagingTimeout: { AXUIElementSetMessagingTimeout($0, $1) },
        operation: { _ in
            AXUIElementSetAttributeValue(
                linkField,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
        }
    )
    guard focusStatus == .success else {
        fail("CaptionGrab's accessible YouTube link field did not accept keyboard focus.")
    }

    var hasKeyboardFocus = false
    for _ in 0..<10 {
        if let focusedElement = try attribute(appElement, kAXFocusedUIElementAttribute as String),
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
    do {
        try focusAndSetYouTubeLinkField(to: arguments[0])
    } catch {
        fail("CaptionGrab accessibility operation failed; refusing to submit (\(error)).")
    }
}
