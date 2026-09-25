"""Source-level contract for the SwiftUI link-row affordance.

macOS CI compiles and launches the app; this check does not simulate a click.
"""

import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = (ROOT / "Sources/CaptionGrab/MainView.swift").read_text()
LINK_ROW = SOURCE.split("private var linkEntry: some View {", 1)[1].split(
    "private var feedback: some View {", 1
)[0]


class ClearLinkUITests(unittest.TestCase):
    def test_clear_button_is_next_to_link_field_only_when_filled(self):
        self.assertRegex(
            LINK_ROW,
            r'(?s)TextField\("Paste or drag a YouTube link here".*?'
            r'if !model\.inputURL\.isEmpty\s*\{\s*Button\s*\{',
            msg="A clear control should follow the URL field and appear only when filled.",
        )
        self.assertIn('Image(systemName: "xmark.circle.fill")', LINK_ROW)
        self.assertIn('.accessibilityLabel("Clear YouTube link")', LINK_ROW)
        self.assertIn('.help("Clear YouTube link")', LINK_ROW)

    def test_clear_button_changes_only_the_link_and_returns_focus(self):
        action = re.search(r'if !model\.inputURL\.isEmpty\s*\{\s*Button\s*\{([^}]+)\}', LINK_ROW)
        if action is None:
            self.fail("Clear button action missing from the URL row")
        statements = [part.strip() for part in action.group(1).splitlines() if part.strip()]
        self.assertEqual(statements, ['model.inputURL = ""', 'inputFocused = true'])
        self.assertIn('.disabled(model.isLoading)', LINK_ROW[action.end():])


if __name__ == "__main__":
    unittest.main()
