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

private func findLinkFields(in root: AXUIElement) -> [AXUIElement] {
    var matches: [AXUIElement] = []
    var pending: [(element: AXUIElement, depth: Int)] = [(root, 0)]
    var visitedCount = 0

    while let current = pending.popLast() {
        visitedCount += 1
        guard visitedCount <= 2_000 else {
            fail("CaptionGrab's accessibility tree exceeded the safe search limit.")
        }
        guard current.depth <= 32 else { continue }

        let role = stringAttribute(current.element, kAXRoleAttribute) ?? ""
        let placeholder = stringAttribute(current.element, kAXPlaceholderValueAttribute)
        let descriptor = AccessibilityFieldDescriptor(
            role: role,
            placeholder: placeholder,
            valueIsSettable: role == kAXTextFieldRole
                && placeholder == expectedPlaceholder
                && isAttributeSettable(current.element, kAXValueAttribute)
        )
        if isYouTubeLinkField(descriptor) {
            matches.append(current.element)
        }

        guard let children = attribute(current.element, kAXChildrenAttribute) as? [AXUIElement] else {
            continue
        }
        for child in children {
            pending.append((child, current.depth + 1))
        }
    }

    return matches
}

private func runLocatorSelfTests() {
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

    let matchingFields = windows.flatMap { findLinkFields(in: $0) }
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
    runLocatorSelfTests()
} else {
    guard arguments.count == 1 else {
        fail("Exactly one public video URL is required.")
    }
    focusAndSetYouTubeLinkField(to: arguments[0])
}
