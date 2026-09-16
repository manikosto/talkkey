"""Hold-to-talk keys on X11, without the portal.

The GlobalShortcuts portal is the only way to get a global hotkey on
Wayland, but on X11 it is merely one way — and on KDE Plasma 5 it is a
broken one: BindShortcuts opens the KDE settings window, returns success,
and hands back an empty list of bindings, so nothing is ever grabbed and
the key press never arrives. Plasma 5.27 ships in Ubuntu 24.04, so that is
not an edge case.

On X11 any client may listen to the keyboard, so this listens directly and
the portal is not involved at all.

One honest limitation: this observes the keys, it does not grab them, so
the combination also reaches whatever window is focused. Pick one that
nothing else wants.
"""

from __future__ import annotations

import asyncio
from typing import Callable

from .hotkeys import DICTATE, TRANSLATE_FIELD

MODIFIER_WORDS = {
    "CTRL": "<ctrl>", "CONTROL": "<ctrl>",
    "ALT": "<alt>",
    "SHIFT": "<shift>",
    "SUPER": "<cmd>", "META": "<cmd>", "LOGO": "<cmd>", "CMD": "<cmd>",
}


class X11ShortcutError(RuntimeError):
    pass


def to_pynput(trigger: str) -> str:
    """"CTRL+ALT+d" as pynput spells it: "<ctrl>+<alt>+d"."""
    parts = [part.strip() for part in trigger.split("+") if part.strip()]
    if not parts:
        raise X11ShortcutError(f"empty shortcut: {trigger!r}")
    spelled = []
    for part in parts:
        upper = part.upper()
        if upper in MODIFIER_WORDS:
            spelled.append(MODIFIER_WORDS[upper])
        elif len(part) == 1:
            spelled.append(part.lower())
        else:
            spelled.append(f"<{part.lower()}>")  # e.g. F5, space
    return "+".join(spelled)


class X11Shortcuts:
    """Same shape as the portal backend, so the app cannot tell them apart."""

    def __init__(self) -> None:
        self.on_press: Callable[[str], None] = lambda _shortcut: None
        self.on_release: Callable[[str], None] = lambda _shortcut: None
        self._listener = None
        self._combos: dict[str, frozenset] = {}
        self._held: set = set()
        self._active: set[str] = set()
        self._loop: asyncio.AbstractEventLoop | None = None

    async def start(self, dictate_trigger: str, translate_trigger: str) -> list[str]:
        try:
            from pynput import keyboard
        except Exception as exc:  # noqa: BLE001 - pynput raises more than ImportError
            raise X11ShortcutError(
                "listening for keys on X11 needs pynput:\n"
                "  pip install 'talkkey-linux[x11]'"
            ) from exc

        self._loop = asyncio.get_running_loop()
        self._keyboard = keyboard

        for shortcut_id, trigger in (
            (DICTATE, dictate_trigger),
            (TRANSLATE_FIELD, translate_trigger),
        ):
            try:
                keys = keyboard.HotKey.parse(to_pynput(trigger))
            except ValueError as exc:
                raise X11ShortcutError(f"could not read the shortcut {trigger!r}: {exc}") from exc
            self._combos[shortcut_id] = frozenset(keys)

        self._listener = keyboard.Listener(on_press=self._pressed, on_release=self._released)
        self._listener.start()
        return [f"{name}: {trigger} (listening directly, X11)"
                for name, trigger in ((DICTATE, dictate_trigger),
                                      (TRANSLATE_FIELD, translate_trigger))]

    # pynput calls these on its own thread, so everything is handed back to
    # the event loop before it touches anything the app owns.
    def _deliver(self, callback: Callable[[str], None], shortcut_id: str) -> None:
        if self._loop is not None:
            self._loop.call_soon_threadsafe(callback, shortcut_id)

    def _canonical(self, key):
        """pynput's normalisation, plus the one case it does not cover.

        With Control held, X11 reports the letter as a control character —
        Ctrl+D arrives as \x04 — and pynput's canonical() passes that
        through untouched. Matched against a combo parsed as `d` it would
        never fire, and the key would appear dead: the exact symptom this
        backend exists to fix. Control characters are folded back to their
        letters here. Backspace, Tab, Enter and Escape arrive as Key values
        rather than KeyCode, so they are not caught by this.
        """
        canon = self._listener.canonical(key)
        char = getattr(canon, "char", None)
        if char and len(char) == 1 and "\x01" <= char <= "\x1a":
            return self._keyboard.KeyCode.from_char(chr(ord(char) + 0x60))
        return canon

    def _pressed(self, key) -> None:
        self._held.add(self._canonical(key))
        for shortcut_id, combo in self._combos.items():
            if shortcut_id not in self._active and combo <= self._held:
                self._active.add(shortcut_id)
                self._deliver(self.on_press, shortcut_id)

    def _released(self, key) -> None:
        self._held.discard(self._canonical(key))
        for shortcut_id in list(self._active):
            if not self._combos[shortcut_id] <= self._held:
                self._active.discard(shortcut_id)
                self._deliver(self.on_release, shortcut_id)

    def stop(self) -> None:
        if self._listener is not None:
            self._listener.stop()
            self._listener = None
