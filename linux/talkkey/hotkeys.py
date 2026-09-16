"""Hold-to-talk keys, via the XDG GlobalShortcuts portal.

The portal reports Activated on press and Deactivated on release, which is
exactly the hold-to-talk shape the macOS app gets from its event tap. What
it will not do is bind a lone modifier: macOS's "hold Right Command" has no
equivalent here, so the shortcuts are combinations.

The desktop, not the app, owns the binding. On the first run KDE or GNOME
shows a dialog listing what is asked for, and the user may change the keys
there — so whatever ends up bound is reported back rather than assumed.
"""

from __future__ import annotations

import os
from typing import Callable

from dbus_next import Variant

from .portal import Portal, PortalError

IFACE = "org.freedesktop.portal.GlobalShortcuts"

DICTATE = "dictate"
TRANSLATE_FIELD = "translate-field"


def choose_backend(configured: str) -> str:
    """Which way the hotkeys are caught, when the config says "auto".

    X11 lets a client listen to the keyboard itself, which sidesteps the
    portal entirely — worth doing, because the Plasma 5 portal binds
    nothing. Wayland has no alternative to the portal.
    """
    if configured != "auto":
        return configured
    wayland = os.environ.get("XDG_SESSION_TYPE") == "wayland" or bool(
        os.environ.get("WAYLAND_DISPLAY")
    )
    return "portal" if wayland else "x11"


class Shortcuts:
    def __init__(self, portal: Portal) -> None:
        self.portal = portal
        self.session_handle: str | None = None
        self.on_press: Callable[[str], None] = lambda _shortcut: None
        self.on_release: Callable[[str], None] = lambda _shortcut: None

    async def start(self, dictate_trigger: str, translate_trigger: str) -> list[str]:
        iface = self.portal.interface(IFACE)

        session_token = self.portal.new_token()
        token = self.portal.new_token()

        async def create(options):
            options["session_handle_token"] = Variant("s", session_token)
            return await iface.call_create_session(options)

        result = await self.portal.call(create, token)
        self.session_handle = result.get("session_handle")
        if not self.session_handle:
            raise PortalError("the portal created no shortcuts session")

        iface.on_activated(self._activated)
        iface.on_deactivated(self._deactivated)

        shortcuts = [
            (
                DICTATE,
                {
                    "description": Variant("s", "TalkKey: hold to dictate"),
                    "preferred_trigger": Variant("s", dictate_trigger),
                },
            ),
            (
                TRANSLATE_FIELD,
                {
                    "description": Variant("s", "TalkKey: translate the text in this field"),
                    "preferred_trigger": Variant("s", translate_trigger),
                },
            ),
        ]

        bind_token = self.portal.new_token()

        async def bind(options):
            return await iface.call_bind_shortcuts(
                self.session_handle, shortcuts, "", options
            )

        bound = await self.portal.call(bind, bind_token)
        shortcuts_bound = bound.get("shortcuts") or []
        if not shortcuts_bound:
            # KDE Plasma 5 answers BindShortcuts successfully, opens its
            # settings window, and binds nothing. Reported as success, the
            # app would sit there looking ready while no key ever arrived.
            raise PortalError(
                "the desktop accepted the shortcuts but bound none of them.\n"
                "That is what KDE Plasma 5 does — its global shortcuts portal is "
                "unfinished, and Plasma 5.27 is what Ubuntu 24.04 ships.\n"
                "On an X11 session set  backend = \"x11\"  under [hotkeys] in "
                "the config; the keys are then caught without the portal.\n"
                "On Wayland this needs Plasma 6.1 or newer, or GNOME 48 or newer."
            )
        return self._describe(shortcuts_bound)

    @staticmethod
    def _describe(bound) -> list[str]:
        """Turn the portal's reply into lines naming the keys actually bound."""
        lines = []
        for entry in bound:
            try:
                shortcut_id, props = entry
            except (TypeError, ValueError):
                continue
            trigger = props.get("trigger_description")
            if isinstance(trigger, Variant):
                trigger = trigger.value
            lines.append(f"{shortcut_id}: {trigger or 'bound (keys not reported)'}")
        return lines

    def _activated(self, session_handle: str, shortcut_id: str, timestamp: int, options: dict) -> None:
        if session_handle == self.session_handle:
            self.on_press(shortcut_id)

    def _deactivated(self, session_handle: str, shortcut_id: str, timestamp: int, options: dict) -> None:
        if session_handle == self.session_handle:
            self.on_release(shortcut_id)
