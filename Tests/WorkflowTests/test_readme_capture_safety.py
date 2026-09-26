import subprocess
import unittest
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:  # GitHub parses the workflow before this job can run.
    yaml = None


REPO_ROOT = Path(__file__).resolve().parents[2]
WORKFLOW_PATH = REPO_ROOT / ".github/workflows/readme-capture.yml"
CAPTURE_SCRIPT = REPO_ROOT / "Scripts/capture-readme-window.sh"
SUBMIT_SCRIPT = REPO_ROOT / "Scripts/submit-readme-video.applescript"
ACCESSIBILITY_SCRIPT = REPO_ROOT / "Scripts/wait-for-readme-transcript.applescript"
ACCESSIBILITY_VERIFIER = REPO_ROOT / "Scripts/verify_transcript_accessibility.py"
VERIFY_SCRIPT = REPO_ROOT / "Scripts/verify-and-capture-readme-window.swift"


class ReadmeCaptureWorkflowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workflow_text = WORKFLOW_PATH.read_text(encoding="utf-8")
        cls.capture_text = CAPTURE_SCRIPT.read_text(encoding="utf-8")
        cls.submit_text = SUBMIT_SCRIPT.read_text(encoding="utf-8")
        cls.accessibility_text = ACCESSIBILITY_SCRIPT.read_text(encoding="utf-8")
        cls.accessibility_verifier_text = ACCESSIBILITY_VERIFIER.read_text(encoding="utf-8")
        cls.verify_text = VERIFY_SCRIPT.read_text(encoding="utf-8")

    @unittest.skipIf(yaml is None, "PyYAML is optional; GitHub validates workflow syntax before dispatch")
    def test_workflow_yaml_parses_as_manual_dispatch_only(self):
        workflow = yaml.safe_load(self.workflow_text)
        self.assertEqual(set(workflow["on"]), {"workflow_dispatch"})
        self.assertEqual(set(workflow["jobs"]), {"capture"})

    def test_workflow_is_main_only_and_read_only(self):
        workflow = yaml.safe_load(self.workflow_text) if yaml else None
        if workflow:
            self.assertEqual(workflow["permissions"], {"contents": "read"})
            job = workflow["jobs"]["capture"]
            self.assertEqual(job["runs-on"], "macos-26")
            ref_guard = next(step for step in job["steps"] if step.get("name", "").startswith("Fail unless"))
            self.assertEqual(ref_guard["if"], "github.ref != 'refs/heads/main'")
            checkout = next(step for step in job["steps"] if step.get("uses", "").startswith("actions/checkout@"))
            self.assertEqual(checkout["with"], {"ref": "main", "persist-credentials": False})
        self.assertNotIn("secrets.", self.workflow_text)
        self.assertNotIn("pull_request:", self.workflow_text)
        self.assertNotIn("push:", self.workflow_text)
        self.assertNotIn("schedule:", self.workflow_text)
        self.assertIn('"${GITHUB_REF:-}" != "refs/heads/main"', self.capture_text)
        self.assertIn('CAPTURE_ROOT="$TEMP_ROOT/captiongrab-readme"', self.capture_text)
        self.assertNotIn('/Applications', self.capture_text)

    def test_capture_requires_the_canonical_repository(self):
        canonical_repo = "9phfr6dsw4-dotcom/captiongrab"
        self.assertIn(f"if: github.repository == '{canonical_repo}'", self.workflow_text)
        self.assertIn(
            f'if [[ "${{GITHUB_REPOSITORY:-}}" != "{canonical_repo}" ]]',
            self.capture_text,
        )

    def test_capture_script_exits_before_work_for_a_fork(self):
        result = subprocess.run(
            ["bash", str(CAPTURE_SCRIPT)],
            env={"GITHUB_REPOSITORY": "attacker/captiongrab", "GITHUB_REF": "refs/heads/main"},
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("canonical", result.stderr.lower())

    def test_input_is_required_public_synthetic_captioned_youtube_video(self):
        if yaml:
            workflow = yaml.safe_load(self.workflow_text)
            video_input = workflow["on"]["workflow_dispatch"]["inputs"]["video_url"]
            self.assertTrue(video_input["required"])
            self.assertEqual(video_input["type"], "string")
            description = video_input["description"].lower()
            for term in ("synthetic", "public", "english", "captions"):
                self.assertIn(term, description)
        self.assertIn("CAPTIONGRAB_VIDEO_URL", self.workflow_text)

    def test_release_is_exactly_pinned_and_checksum_checked_before_launch(self):
        for pin in (
            "v1.2.17",
            "ab7c032d26988dd249e2ae6a535eac6aa16f00f2",
            "58cf95c311c02e316e80141ad7437f300ac58f5f3fedfd7985ca694cc8efe8a7",
        ):
            self.assertIn(pin, self.capture_text)
        self.assertIn("https://github.com/9phfr6dsw4-dotcom/captiongrab/releases/download/v1.2.17", self.capture_text)
        self.assertIn("CaptionGrab.zip", self.capture_text)
        self.assertNotIn("releases/latest/", self.capture_text)
        self.assertIn("shasum -a 256 -c", self.capture_text)
        self.assertLess(self.capture_text.index("shasum -a 256 -c"), self.capture_text.index('open "$APP_PATH"'))
        self.assertLess(self.capture_text.index("swiftc Scripts/verify-and-capture-readme-window.swift"), self.capture_text.index('open "$APP_PATH"'))

    def test_app_gets_no_github_token_and_uses_text_field_return(self):
        self.assertIn("unset GH_TOKEN GITHUB_TOKEN", self.capture_text)
        self.assertLess(self.capture_text.index("unset GH_TOKEN GITHUB_TOKEN"), self.capture_text.index('open "$APP_PATH"'))
        self.assertIn("text field 1", self.submit_text.lower())
        self.assertIn("key code 36", self.submit_text.lower())
        self.assertNotIn("Get transcript", self.submit_text)
        self.assertNotIn("click button", self.submit_text.lower())

    def test_capture_fails_closed_on_missing_transcript_and_saves_window_only(self):
        self.assertIn("CaptionGrab", self.verify_text)
        self.assertIn("Transcript", self.verify_text)
        self.assertIn("YouTube Video url", self.verify_text)
        self.assertIn("screencapture", self.verify_text)
        self.assertIn('"-x", "-l"', self.verify_text)
        self.assertIn("timestamp", self.verify_text.lower())
        self.assertIn("expectedVideoID", self.verify_text)
        self.assertIn("candidate.width >= 680", self.verify_text)
        self.assertIn("candidate.height >= 620", self.verify_text)
        self.assertIn("frontmostApplication", self.verify_text)
        self.assertIn("static texts", self.accessibility_text.lower())
        self.assertIn("verify_transcript_accessibility.py", self.capture_text)
        self.assertLess(self.capture_text.index("verify_transcript_accessibility.py"), self.capture_text.rindex('"$CAPTURE_ROOT/verify-window"'))
        self.assertIn("youtube video url", self.accessibility_verifier_text.lower())
        self.assertIn("timestamp", self.accessibility_verifier_text.lower())
        self.assertIn("throw", self.verify_text)
        self.assertNotIn("probe-window", self.capture_text)
        self.assertEqual(self.verify_text.count('process.arguments = ["-x", "-l"'), 1)
        self.assertNotIn("README.md", self.capture_text)
        self.assertNotIn("composite", self.capture_text.lower())

    def test_artifact_is_only_fresh_app_window_png(self):
        if yaml:
            workflow = yaml.safe_load(self.workflow_text)
            steps = workflow["jobs"]["capture"]["steps"]
            upload = next(step for step in steps if step.get("uses", "").startswith("actions/upload-artifact@"))
            self.assertEqual(upload["with"]["path"], "${{ runner.temp }}/captiongrab-readme/captiongrab-window.png")
            self.assertEqual(upload["with"]["if-no-files-found"], "error")
        self.assertIn("captiongrab-window.png", self.capture_text)
        self.assertIn("rm -rf \"$CAPTURE_ROOT\"", self.capture_text)


if __name__ == "__main__":
    unittest.main()
