#!/usr/bin/env python3
"""Fail packaging if the signed macOS app carries App Sandbox entitlement."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit("usage: test-unsandboxed-app.py CODE_SIGN_TARGET")

    app = Path(sys.argv[1])
    if not app.exists():
        raise SystemExit(f"Code-sign target does not exist: {app}")

    result = subprocess.run(
        ["/usr/bin/codesign", "-d", "--entitlements", ":-", str(app)],
        capture_output=True,
        check=False,
    )
    output = (result.stdout + result.stderr).decode("utf-8", errors="replace")
    if result.returncode != 0:
        raise SystemExit(f"Could not inspect code-sign entitlements for {app}: {output.strip()}")
    if "com.apple.security.app-sandbox" in output:
        raise SystemExit(f"App Sandbox entitlement is still present in {app}")

    print(f"Verified App Sandbox entitlement is absent: {app}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
