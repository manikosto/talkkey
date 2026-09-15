"""Desktop notifications — the stand-in for the macOS toasts."""

from __future__ import annotations

import shutil
import subprocess

APP_NAME = "TalkKey"


def notify(title: str, body: str = "", *, urgency: str = "normal", timeout_ms: int = 4000) -> None:
    if not shutil.which("notify-send"):
        print(f"talkkey: {title}" + (f" — {body}" if body else ""))
        return
    subprocess.run(
        [
            "notify-send",
            "--app-name", APP_NAME,
            "--urgency", urgency,
            "--expire-time", str(timeout_ms),
            title,
            body,
        ],
        check=False,
        timeout=5,
    )


def error(title: str, body: str = "") -> None:
    notify(title, body, urgency="critical", timeout_ms=10_000)
