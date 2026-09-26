import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "Scripts"))

from verify_transcript_accessibility import has_visible_transcript  # noqa: E402


class VisibleTranscriptTests(unittest.TestCase):
    video_id = "abcDEF_123-"

    def test_accepts_requested_video_with_title_and_nonempty_cues(self):
        accessible_text = "\n".join(
            (
                "CaptionGrab",
                "Transcript",
                "Creator-made English captions",
                "A Synthetic Demo",
                f"YouTube Video url: https://www.youtube.com/watch?v={self.video_id}",
                "0:00",
                "Welcome to the synthetic demo.",
                "0:04",
                "This is a second visible caption cue.",
            )
        )
        self.assertTrue(has_visible_transcript(accessible_text, self.video_id))

    def test_rejects_empty_or_placeholder_transcript(self):
        placeholder = "\n".join(
            (
                "CaptionGrab",
                "Transcript",
                "No transcript yet",
                "Paste a YouTube link above to get started.",
            )
        )
        self.assertFalse(has_visible_transcript(placeholder, self.video_id))

    def test_rejects_transcript_for_a_different_video(self):
        wrong_video = "\n".join(
            (
                "CaptionGrab",
                "Transcript",
                "A Synthetic Demo",
                "YouTube Video url: https://www.youtube.com/watch?v=wrongID_1234",
                "0:00",
                "First cue is visible.",
                "0:02",
                "Second cue is visible.",
            )
        )
        self.assertFalse(has_visible_transcript(wrong_video, self.video_id))

    def test_rejects_title_and_url_without_nonempty_cue_text(self):
        empty_cues = "\n".join(
            (
                "CaptionGrab",
                "Transcript",
                "A Synthetic Demo",
                f"YouTube Video url: https://www.youtube.com/watch?v={self.video_id}",
                "0:00",
                "0:04",
            )
        )
        self.assertFalse(has_visible_transcript(empty_cues, self.video_id))


if __name__ == "__main__":
    unittest.main()
