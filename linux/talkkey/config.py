"""Settings, read from ~/.config/talkkey/config.toml."""

from __future__ import annotations

import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

if sys.version_info >= (3, 11):
    import tomllib
else:  # pragma: no cover - 3.10 needs the backport
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None


def config_dir() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config"
    return Path(base) / "talkkey"


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or Path.home() / ".local" / "state"
    return Path(base) / "talkkey"


DEFAULT_CONFIG = """\
# TalkKey for Linux

[hotkeys]
# The portal can only bind key combinations, not a lone modifier, so these
# are combos. Hold one down, speak, let go. Your desktop shows a dialog the
# first time asking you to confirm or change them.
dictate = "CTRL+ALT+d"          # speak, and the text is typed where you are
translate_field = "CTRL+ALT+t"  # replace the text in the field with a translation

[speech]
# "local" runs faster-whisper on this machine; "openai" sends audio to the API.
engine = "local"
model = "small"                 # tiny | base | small | medium | large-v3
language = "auto"               # auto, or a code such as ru / en / uk
compute_type = "int8"           # int8 is the safe CPU default; float16 for a GPU

[translate]
# "openai" needs a key; "argos" runs offline once a language pair is installed.
engine = "openai"
target = "en"

[openai]
# Or set OPENAI_API_KEY in the environment instead.
api_key = ""
speech_model = "whisper-1"
text_model = "gpt-4o-mini"

[input]
# How Ctrl+V is delivered.
#   "auto"    — xdotool on X11, the RemoteDesktop portal on Wayland
#   "xdotool" — X11 only, nothing to grant
#   "portal"  — RemoteDesktop portal; asks permission once, then remembers
#   "ydotool" — needs the ydotool daemon and access to /dev/uinput
method = "auto"
# Pause after the paste before the clipboard is put back, in seconds.
restore_delay = 0.4
"""


@dataclass
class Config:
    dictate_shortcut: str = "CTRL+ALT+d"
    translate_shortcut: str = "CTRL+ALT+t"

    speech_engine: str = "local"
    speech_model: str = "small"
    speech_language: str = "auto"
    compute_type: str = "int8"

    translate_engine: str = "openai"
    translate_target: str = "en"

    openai_api_key: str = ""
    openai_speech_model: str = "whisper-1"
    openai_text_model: str = "gpt-4o-mini"

    input_method: str = "auto"
    restore_delay: float = 0.4

    path: Path = field(default_factory=lambda: config_dir() / "config.toml")

    @property
    def api_key(self) -> str:
        return self.openai_api_key or os.environ.get("OPENAI_API_KEY", "")


def write_default_config() -> Path:
    path = config_dir() / "config.toml"
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        path.write_text(DEFAULT_CONFIG, encoding="utf-8")
    return path


def load() -> Config:
    path = write_default_config()
    cfg = Config(path=path)

    if tomllib is None:
        print("talkkey: python 3.10 needs 'pip install tomli' to read the config; using defaults")
        return cfg

    with path.open("rb") as handle:
        raw = tomllib.load(handle)

    hotkeys = raw.get("hotkeys", {})
    cfg.dictate_shortcut = hotkeys.get("dictate", cfg.dictate_shortcut)
    cfg.translate_shortcut = hotkeys.get("translate_field", cfg.translate_shortcut)

    speech = raw.get("speech", {})
    cfg.speech_engine = speech.get("engine", cfg.speech_engine)
    cfg.speech_model = speech.get("model", cfg.speech_model)
    cfg.speech_language = speech.get("language", cfg.speech_language)
    cfg.compute_type = speech.get("compute_type", cfg.compute_type)

    translate = raw.get("translate", {})
    cfg.translate_engine = translate.get("engine", cfg.translate_engine)
    cfg.translate_target = translate.get("target", cfg.translate_target)

    openai_cfg = raw.get("openai", {})
    cfg.openai_api_key = openai_cfg.get("api_key", cfg.openai_api_key)
    cfg.openai_speech_model = openai_cfg.get("speech_model", cfg.openai_speech_model)
    cfg.openai_text_model = openai_cfg.get("text_model", cfg.openai_text_model)

    input_cfg = raw.get("input", {})
    cfg.input_method = input_cfg.get("method", cfg.input_method)
    cfg.restore_delay = float(input_cfg.get("restore_delay", cfg.restore_delay))

    return cfg
