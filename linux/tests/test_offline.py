"""Everything that can be checked without a Linux desktop.

Run with:  python -m pytest linux/tests -q
"""

from __future__ import annotations

import io
import os
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from talkkey import audio, config as config_mod, introspection  # noqa: E402
from talkkey.hotkeys import Shortcuts, choose_backend  # noqa: E402
from talkkey.hotkeys_x11 import X11Shortcuts, to_pynput  # noqa: E402
from talkkey.inject import _ydotool_code, resolve_method  # noqa: E402
from talkkey.translate import Translator, language_name  # noqa: E402


@pytest.fixture()
def fresh_config(monkeypatch):
    monkeypatch.setenv("XDG_CONFIG_HOME", tempfile.mkdtemp())
    monkeypatch.delenv("OPENAI_API_KEY", raising=False)
    return config_mod.load()


# -- the bug that stopped the first Linux run --------------------------

# xdg-desktop-portal really publishes this, and a D-Bus member name may not
# contain a hyphen. Parsing the portal's own description therefore throws,
# taking down interfaces that are perfectly fine. Trimmed from a real reply.
PORTAL_XML_WITH_BAD_MEMBER = """
<node>
  <interface name="org.freedesktop.portal.PowerProfileMonitor">
    <property name="power-saver-enabled" type="b" access="read"/>
  </interface>
  <interface name="org.freedesktop.portal.GlobalShortcuts">
    <method name="CreateSession">
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
  </interface>
  <interface name="org.freedesktop.portal.RemoteDesktop"/>
</node>
"""


def test_portal_description_still_cannot_be_parsed():
    """The upstream problem is real; this is what we route around."""
    from dbus_next.introspection import Node

    with pytest.raises(Exception) as caught:
        Node.parse(PORTAL_XML_WITH_BAD_MEMBER)
    assert "power-saver-enabled" in str(caught.value)


def test_interfaces_are_found_without_parsing():
    """`doctor` reads the text, so a hyphenated property cannot blind it."""
    for name in (
        "org.freedesktop.portal.GlobalShortcuts",
        "org.freedesktop.portal.RemoteDesktop",
    ):
        assert f'"{name}"' in PORTAL_XML_WITH_BAD_MEMBER
    assert '"org.freedesktop.portal.ScreenCast"' not in PORTAL_XML_WITH_BAD_MEMBER


@pytest.mark.parametrize("name,xml", sorted(introspection.BY_NAME.items()))
def test_our_descriptions_parse(name, xml):
    """Ours must survive the same strict validator that rejects the portal's."""
    from dbus_next.introspection import Node

    node = Node.parse(xml)
    assert [iface.name for iface in node.interfaces] == [name]


def test_portal_call_signatures_match_the_spec():
    from dbus_next.introspection import Node

    shortcuts = Node.parse(introspection.GLOBAL_SHORTCUTS).interfaces[0]
    methods = {m.name: "".join(a.signature for a in m.in_args) for m in shortcuts.methods}
    assert methods["CreateSession"] == "a{sv}"
    assert methods["BindShortcuts"] == "oa(sa{sv})sa{sv}"
    signals = {s.name: "".join(a.signature for a in s.args) for s in shortcuts.signals}
    assert signals["Activated"] == signals["Deactivated"] == "osta{sv}"

    remote = Node.parse(introspection.REMOTE_DESKTOP).interfaces[0]
    rmethods = {m.name: "".join(a.signature for a in m.in_args) for m in remote.methods}
    assert rmethods["NotifyKeyboardKeysym"] == "oa{sv}iu"
    assert rmethods["SelectDevices"] == "oa{sv}"
    assert rmethods["Start"] == "osa{sv}"


def test_method_names_map_to_the_calls_we_make():
    """dbus-next builds `call_<snake_case>`; ours must line up with that."""
    from dbus_next.proxy_object import BaseProxyInterface

    expected = {
        "CreateSession": "create_session",
        "BindShortcuts": "bind_shortcuts",
        "SelectDevices": "select_devices",
        "NotifyKeyboardKeysym": "notify_keyboard_keysym",
        "Start": "start",
    }
    for member, snake in expected.items():
        assert BaseProxyInterface._to_snake_case(member) == snake


# -- configuration -----------------------------------------------------

def test_default_config_matches_the_dataclass(fresh_config):
    cfg = fresh_config
    assert cfg.path.exists()
    assert cfg.dictate_shortcut == "CTRL+ALT+d"
    assert cfg.translate_shortcut == "CTRL+ALT+t"
    assert cfg.speech_engine == "local"
    assert cfg.translate_target == "en"
    assert cfg.input_method == "auto"
    assert cfg.hotkey_backend == "auto"
    assert cfg.speech_device == "auto"


def test_edits_are_read_and_omissions_keep_defaults(fresh_config):
    fresh_config.path.write_text(
        '[hotkeys]\ndictate = "SUPER+q"\n'
        '[speech]\nengine = "openai"\nlanguage = "ru"\n'
        '[translate]\ntarget = "uk"\n'
        '[input]\nmethod = "ydotool"\nrestore_delay = 1.5\n',
        encoding="utf-8",
    )
    cfg = config_mod.load()
    assert cfg.dictate_shortcut == "SUPER+q"
    assert cfg.speech_engine == "openai"
    assert cfg.speech_language == "ru"
    assert cfg.translate_target == "uk"
    assert cfg.input_method == "ydotool"
    assert cfg.restore_delay == 1.5
    assert cfg.translate_shortcut == "CTRL+ALT+t"  # untouched


def test_api_key_falls_back_to_the_environment(fresh_config, monkeypatch):
    assert fresh_config.api_key == ""
    monkeypatch.setenv("OPENAI_API_KEY", "env-key")
    assert config_mod.load().api_key == "env-key"


# -- language and audio ------------------------------------------------

@pytest.mark.parametrize(
    "text,expected",
    [
        ("Привет, как дела?", "ru"),
        ("Привіт, як справи?", "uk"),
        ("Це тест із ґ та є", "uk"),
        ("Hello, how are you?", "en"),
    ],
)
def test_language_detection(text, expected):
    assert Translator._detect(text) == expected


def test_language_names():
    assert language_name("uk") == "Ukrainian"
    assert language_name("xx") == "xx"


def test_wav_is_valid_16k_mono():
    samples = (np.sin(np.linspace(0, 400, audio.SAMPLE_RATE)) * 0.5).astype(np.float32)
    with wave.open(io.BytesIO(audio.to_wav(samples))) as handle:
        assert handle.getframerate() == 16_000
        assert handle.getnchannels() == 1
        assert handle.getsampwidth() == 2
        assert handle.getnframes() == len(samples)
    assert abs(audio.duration(samples) - 1.0) < 0.001


def test_loud_audio_clips_instead_of_wrapping():
    """Wrapping would turn a shout into noise Whisper cannot read."""
    pcm = np.frombuffer(audio.to_wav(np.array([5.0, -5.0], dtype=np.float32))[44:],
                        dtype=np.int16)
    assert pcm[0] > 32_000 and pcm[1] < -32_000


def test_blank_text_never_reaches_a_paid_api(fresh_config):
    assert Translator(fresh_config).translate("   ") == ("", "")


# -- small helpers -----------------------------------------------------

def test_shortcut_reply_parsing_survives_junk():
    from dbus_next import Variant

    assert Shortcuts._describe(
        [("dictate", {"trigger_description": Variant("s", "Ctrl+Alt+D")})]
    ) == ["dictate: Ctrl+Alt+D"]
    assert Shortcuts._describe([("x", {})]) == ["x: bound (keys not reported)"]
    assert Shortcuts._describe(["nonsense"]) == []
    assert Shortcuts._describe([]) == []


def test_explicit_input_method_is_never_second_guessed():
    for method in ("portal", "xdotool", "ydotool"):
        assert resolve_method(method) == method


def test_auto_picks_the_portal_on_wayland(monkeypatch):
    monkeypatch.setenv("XDG_SESSION_TYPE", "wayland")
    monkeypatch.setenv("WAYLAND_DISPLAY", "wayland-0")
    # Even with xdotool installed, Wayland does not let it through.
    monkeypatch.setattr("talkkey.inject.shutil.which", lambda _name: "/usr/bin/xdotool")
    assert resolve_method("auto") == "portal"


def test_auto_prefers_xdotool_on_x11(monkeypatch):
    monkeypatch.setenv("XDG_SESSION_TYPE", "x11")
    monkeypatch.delenv("WAYLAND_DISPLAY", raising=False)
    monkeypatch.setattr("talkkey.inject.shutil.which", lambda _name: "/usr/bin/xdotool")
    assert resolve_method("auto") == "xdotool"


def test_auto_falls_back_to_the_portal_when_xdotool_is_absent(monkeypatch):
    monkeypatch.setenv("XDG_SESSION_TYPE", "x11")
    monkeypatch.delenv("WAYLAND_DISPLAY", raising=False)
    monkeypatch.setattr("talkkey.inject.shutil.which", lambda _name: None)
    assert resolve_method("auto") == "portal"


def test_ydotool_codes_are_real_input_event_codes():
    assert (_ydotool_code("a"), _ydotool_code("c"), _ydotool_code("v")) == (30, 46, 47)


# -- catching the hotkeys ---------------------------------------------

def test_hotkey_backend_auto_follows_the_session(monkeypatch):
    monkeypatch.setenv("XDG_SESSION_TYPE", "wayland")
    assert choose_backend("auto") == "portal"
    monkeypatch.setenv("XDG_SESSION_TYPE", "x11")
    monkeypatch.delenv("WAYLAND_DISPLAY", raising=False)
    assert choose_backend("auto") == "x11"


def test_hotkey_backend_respects_an_explicit_choice(monkeypatch):
    monkeypatch.setenv("XDG_SESSION_TYPE", "x11")
    assert choose_backend("portal") == "portal"


@pytest.mark.parametrize(
    "trigger,expected",
    [
        ("CTRL+ALT+d", "<ctrl>+<alt>+d"),
        ("ctrl+alt+D", "<ctrl>+<alt>+d"),
        ("SUPER+q", "<cmd>+q"),
        ("CTRL+SHIFT+F5", "<ctrl>+<shift>+<f5>"),
        ("ALT+space", "<alt>+<space>"),
    ],
)
def test_shortcut_translated_to_pynput(trigger, expected):
    assert to_pynput(trigger) == expected


def test_empty_shortcut_is_refused():
    from talkkey.hotkeys_x11 import X11ShortcutError

    with pytest.raises(X11ShortcutError):
        to_pynput("  ")


def test_hold_to_talk_fires_once_on_press_and_once_on_release():
    """The state machine, driven with stand-in keys rather than real ones."""
    shortcuts = X11Shortcuts()
    shortcuts._listener = type("L", (), {"canonical": staticmethod(lambda key: key)})()
    shortcuts._combos = {"dictate": frozenset({"ctrl", "alt", "d"})}
    pressed, released = [], []
    shortcuts._loop = type("Loop", (), {
        "call_soon_threadsafe": staticmethod(lambda fn, arg: fn(arg))
    })()
    shortcuts.on_press = pressed.append
    shortcuts.on_release = released.append

    shortcuts._pressed("ctrl")
    shortcuts._pressed("alt")
    assert pressed == []            # not yet complete
    shortcuts._pressed("d")
    assert pressed == ["dictate"]
    shortcuts._pressed("d")         # key repeat must not fire again
    assert pressed == ["dictate"]
    assert released == []

    shortcuts._released("d")
    assert released == ["dictate"]
    shortcuts._released("ctrl")     # letting go of the rest changes nothing
    shortcuts._released("alt")
    assert released == ["dictate"]


def test_an_unrelated_key_does_not_fire_the_shortcut():
    shortcuts = X11Shortcuts()
    shortcuts._listener = type("L", (), {"canonical": staticmethod(lambda key: key)})()
    shortcuts._combos = {"dictate": frozenset({"ctrl", "alt", "d"})}
    fired = []
    shortcuts._loop = type("Loop", (), {
        "call_soon_threadsafe": staticmethod(lambda fn, arg: fn(arg))
    })()
    shortcuts.on_press = fired.append

    for key in ("ctrl", "shift", "d", "x"):
        shortcuts._pressed(key)
    assert fired == []


def test_control_characters_fold_back_to_their_letter():
    """Ctrl+D reaches us as \x04; matched against `d` it must still fire."""
    from pynput import keyboard

    shortcuts = X11Shortcuts()
    shortcuts._keyboard = keyboard
    listener = keyboard.Listener(on_press=lambda k: None)
    shortcuts._listener = listener

    assert shortcuts._canonical(keyboard.KeyCode.from_char("\x04")) == \
        keyboard.KeyCode.from_char("d")
    assert shortcuts._canonical(keyboard.KeyCode.from_char("\x01")) == \
        keyboard.KeyCode.from_char("a")
    assert shortcuts._canonical(keyboard.KeyCode.from_char("\x1a")) == \
        keyboard.KeyCode.from_char("z")
    # Ordinary keys and modifiers are left exactly as pynput normalised them.
    assert shortcuts._canonical(keyboard.KeyCode.from_char("D")) == \
        keyboard.KeyCode.from_char("d")
    assert shortcuts._canonical(keyboard.Key.ctrl_r) == listener.canonical(keyboard.Key.ctrl_l)


def test_ctrl_alt_d_matches_when_the_letter_arrives_as_a_control_character():
    """End to end through the state machine, with what X11 really sends."""
    from pynput import keyboard

    shortcuts = X11Shortcuts()
    shortcuts._keyboard = keyboard
    shortcuts._listener = keyboard.Listener(on_press=lambda k: None)
    shortcuts._combos = {"dictate": frozenset(keyboard.HotKey.parse("<ctrl>+<alt>+d"))}
    fired, let_go = [], []
    shortcuts._loop = type("Loop", (), {
        "call_soon_threadsafe": staticmethod(lambda fn, arg: fn(arg))
    })()
    shortcuts.on_press = fired.append
    shortcuts.on_release = let_go.append

    shortcuts._pressed(keyboard.Key.ctrl_l)
    shortcuts._pressed(keyboard.Key.alt_l)
    shortcuts._pressed(keyboard.KeyCode.from_char("\x04"))   # Ctrl+D, as sent
    assert fired == ["dictate"]
    shortcuts._released(keyboard.KeyCode.from_char("\x04"))
    assert let_go == ["dictate"]
