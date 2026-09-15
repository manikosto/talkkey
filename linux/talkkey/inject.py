"""Getting text into whatever window the user is actually typing in.

Not by typing it. ydotool types US-ASCII against a hardcoded layout, which
cannot produce Cyrillic — the languages TalkKey exists for — and wtype needs
a virtual-keyboard protocol that KDE does not offer. What does work
everywhere is the clipboard plus a single Ctrl+V, because the only keys
being synthesised are then Control and V.

Ctrl+V itself goes through the RemoteDesktop portal, which both KDE and
GNOME implement and which asks the user for permission once. The session is
persistent: the token it hands back is kept so later runs are not asked
again. ydotool remains selectable for anyone who would rather not grant it.
"""

from __future__ import annotations

import asyncio
import shutil
import subprocess

from dbus_next import Variant

from . import clipboard, keysyms
from .config import Config, state_dir
from .portal import Portal, PortalError

IFACE = "org.freedesktop.portal.RemoteDesktop"
KEYBOARD = 1
PERSIST_WHILE_ALLOWED = 2


class Injector:
    """Sends key combinations, and pastes text, into the focused window."""

    def __init__(self, portal: Portal, config: Config) -> None:
        self.portal = portal
        self.config = config
        self.session_handle: str | None = None
        self._token_path = state_dir() / "remote-desktop-token"

    # -- setup ---------------------------------------------------------

    async def start(self) -> None:
        if self.config.input_method == "ydotool":
            if not shutil.which("ydotool"):
                raise PortalError(
                    "input.method is 'ydotool' but ydotool is not installed. "
                    "Note it can only send ASCII keys — that is fine for Ctrl+V, "
                    "which is all TalkKey asks of it."
                )
            return
        await self._start_remote_desktop()

    async def _start_remote_desktop(self) -> None:
        iface = self.portal.interface(IFACE)
        session_token = self.portal.new_token()

        async def create(options):
            options["session_handle_token"] = Variant("s", session_token)
            return await iface.call_create_session(options)

        result = await self.portal.call(create, self.portal.new_token())
        self.session_handle = result.get("session_handle")
        if not self.session_handle:
            raise PortalError("the portal created no remote desktop session")

        async def select(options):
            options["types"] = Variant("u", KEYBOARD)
            options["persist_mode"] = Variant("u", PERSIST_WHILE_ALLOWED)
            token = self._restore_token()
            if token:
                options["restore_token"] = Variant("s", token)
            return await iface.call_select_devices(self.session_handle, options)

        await self.portal.call(select, self.portal.new_token())

        async def start(options):
            return await iface.call_start(self.session_handle, "", options)

        started = await self.portal.call(start, self.portal.new_token())
        if token := started.get("restore_token"):
            self._save_restore_token(token)

    def _restore_token(self) -> str:
        try:
            return self._token_path.read_text(encoding="utf-8").strip()
        except OSError:
            return ""

    def _save_restore_token(self, token: str) -> None:
        try:
            self._token_path.parent.mkdir(parents=True, exist_ok=True)
            self._token_path.write_text(token, encoding="utf-8")
        except OSError:
            pass  # Only costs the user one more permission dialog next time.

    # -- keys ----------------------------------------------------------

    async def _keysym(self, keysym: int, state: int) -> None:
        iface = self.portal.interface(IFACE)
        await iface.call_notify_keyboard_keysym(self.session_handle, {}, keysym, state)

    async def control_combo(self, keysym: int) -> None:
        """Hold Control, tap one key, let go."""
        if self.config.input_method == "ydotool":
            name = {keysyms.V: "v", keysyms.A: "a", keysyms.C: "c"}[keysym]
            subprocess.run(["ydotool", "key", f"29:1", f"{_ydotool_code(name)}:1",
                            f"{_ydotool_code(name)}:0", "29:0"], check=False, timeout=5)
            return

        await self._keysym(keysyms.CONTROL_L, keysyms.PRESSED)
        await self._keysym(keysym, keysyms.PRESSED)
        await asyncio.sleep(0.01)
        await self._keysym(keysym, keysyms.RELEASED)
        await self._keysym(keysyms.CONTROL_L, keysyms.RELEASED)

    # -- text ----------------------------------------------------------

    async def paste(self, text: str, *, replace_selection: bool = False) -> None:
        """Puts `text` where the cursor is, restoring the clipboard after.

        With `replace_selection` the field is selected first, so the text
        lands instead of what was there rather than next to it.
        """
        previous = clipboard.read()
        clipboard.write(text)
        # The clipboard manager needs a moment before the paste can see it.
        await asyncio.sleep(0.08)

        if replace_selection:
            await self.control_combo(keysyms.A)
            await asyncio.sleep(0.05)

        await self.control_combo(keysyms.V)

        await asyncio.sleep(self.config.restore_delay)
        if previous:
            clipboard.write(previous)

    async def read_focused_text(self) -> str:
        """Select-all, copy, and put the clipboard back. Returns what was there."""
        previous = clipboard.read()
        clipboard.write("")
        await asyncio.sleep(0.05)

        await self.control_combo(keysyms.A)
        await asyncio.sleep(0.05)
        await self.control_combo(keysyms.C)
        await asyncio.sleep(0.25)

        captured = clipboard.read()
        if previous:
            clipboard.write(previous)
        return captured


def _ydotool_code(letter: str) -> int:
    """Linux input event codes for the three letters that are ever needed."""
    return {"a": 30, "c": 46, "v": 47}[letter]
