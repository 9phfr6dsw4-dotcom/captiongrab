import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "Scripts"))

from validate_youtube_video_url import normalize_youtube_url  # noqa: E402


class YouTubeVideoURLTests(unittest.TestCase):
    video_id = "abcDEF_123-"

    def test_watch_url_is_reduced_to_canonical_public_video_url(self):
        self.assertEqual(
            normalize_youtube_url(f"https://www.youtube.com/watch?v={self.video_id}"),
            f"https://www.youtube.com/watch?v={self.video_id}",
        )

    def test_short_url_is_canonicalized(self):
        self.assertEqual(
            normalize_youtube_url(f"https://youtu.be/{self.video_id}"),
            f"https://www.youtube.com/watch?v={self.video_id}",
        )

    def test_shorts_url_is_canonicalized(self):
        self.assertEqual(
            normalize_youtube_url(f"https://youtube.com/shorts/{self.video_id}"),
            f"https://www.youtube.com/watch?v={self.video_id}",
        )

    def test_rejects_non_https_and_untrusted_hosts(self):
        invalid_urls = (
            f"http://youtube.com/watch?v={self.video_id}",
            f"https://youtube.com.attacker.test/watch?v={self.video_id}",
            f"https://attacker.test/watch?v={self.video_id}",
            f"https://user@youtube.com/watch?v={self.video_id}",
        )
        for url in invalid_urls:
            with self.subTest(url=url), self.assertRaises(ValueError):
                normalize_youtube_url(url)

    def test_rejects_extra_parameters_fragments_and_non_video_paths(self):
        invalid_urls = (
            f"https://youtube.com/watch?v={self.video_id}&list=playlist",
            f"https://youtube.com/watch?v={self.video_id}#t=10",
            "https://youtube.com/playlist?list=playlist",
            "https://youtu.be/abcDEF_123",
            f"https://youtube.com/watch?v={self.video_id}&v={self.video_id}",
        )
        for url in invalid_urls:
            with self.subTest(url=url), self.assertRaises(ValueError):
                normalize_youtube_url(url)


if __name__ == "__main__":
    unittest.main()
