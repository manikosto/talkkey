"""The daemon: keys in, text out."""

from __future__ import annotations

import asyncio
import functools

from . import audio as audio_mod
from . import clipboard, hotkeys, notify
from .config import Config
from .inject import Injector
from .portal import Portal, PortalError
from .transcribe import Transcriber, TranscriptionError
from .translate import Translator, TranslationError, language_name

# Ctrl+A in something that is not a text field selects a whole document or
# page. Refusing to act on an implausibly large capture keeps a misfire from
# replacing someone's essay with one translated sentence.
MAX_FIELD_CHARS = 5_000


class TalkKey:
    def __init__(self, config: Config) -> None:
        self.config = config
        self.portal = Portal()
        self.injector = Injector(self.portal, config)
        self.hotkey_backend = hotkeys.choose_backend(config.hotkey_backend)
        if self.hotkey_backend == "x11":
            from .hotkeys_x11 import X11Shortcuts

            self.shortcuts = X11Shortcuts()
        else:
            self.shortcuts = hotkeys.Shortcuts(self.portal)
        self.recorder = audio_mod.Recorder()
        self.transcriber = Transcriber(config)
        self.translator = Translator(config)
        self._busy = False

    async def run(self) -> int:
        try:
            await self.portal.connect()
            await self.injector.start()
            bound = await self.shortcuts.start(
                self.config.dictate_shortcut, self.config.translate_shortcut
            )
        except Exception as exc:  # noqa: BLE001 - every startup failure reads the same
            notify.error("TalkKey could not start", str(exc))
            print(f"talkkey: {exc}")
            return 1

        self.shortcuts.on_press = self._on_press
        self.shortcuts.on_release = self._on_release

        print("talkkey: ready. Bound shortcuts:")
        for line in bound or ["(the desktop did not report the keys it bound)"]:
            print(f"  {line}")
        print("  Hold the dictate key, speak, let go.")

        if self.config.speech_engine == "local":
            asyncio.get_running_loop().run_in_executor(None, self._warm_up)

        await asyncio.Event().wait()  # portal signals drive everything from here
        return 0

    def _warm_up(self) -> None:
        try:
            self.transcriber.warm_up()
            print("talkkey: speech model ready")
        except TranscriptionError as exc:
            notify.error("Speech recognition is not set up", str(exc))
            print(f"talkkey: {exc}")

    # -- key events ----------------------------------------------------

    def _on_press(self, shortcut_id: str) -> None:
        if shortcut_id != hotkeys.DICTATE or self._busy:
            return
        try:
            self.recorder.start()
            notify.notify("Listening…", timeout_ms=30_000)
        except audio_mod.AudioError as exc:
            notify.error("The microphone could not be opened", str(exc))

    def _on_release(self, shortcut_id: str) -> None:
        if self._busy:
            return
        if shortcut_id == hotkeys.DICTATE and self.recorder.recording:
            asyncio.create_task(self._finish_dictation())
        elif shortcut_id == hotkeys.TRANSLATE_FIELD:
            asyncio.create_task(self._translate_field())

    # -- the two things it does ----------------------------------------

    async def _finish_dictation(self) -> None:
        self._busy = True
        try:
            samples = self.recorder.stop()
            if audio_mod.duration(samples) < 0.3:
                notify.notify("Nothing heard", "Hold the key while you speak.")
                return

            loop = asyncio.get_running_loop()
            text = await loop.run_in_executor(
                None, functools.partial(self.transcriber.transcribe, samples)
            )
            if not text:
                notify.notify("Nothing recognised", "No speech was found in that.")
                return

            await self.injector.paste(text)
        except (TranscriptionError, PortalError, clipboard.ClipboardError) as exc:
            notify.error("Dictation failed", str(exc))
            print(f"talkkey: {exc}")
        except Exception as exc:  # noqa: BLE001 - a daemon must not die on one failure
            notify.error("Dictation failed", str(exc))
            print(f"talkkey: unexpected error: {exc!r}")
        finally:
            self._busy = False

    async def _translate_field(self) -> None:
        self._busy = True
        try:
            source = (await self.injector.read_focused_text()).strip()
            if not source:
                notify.notify(
                    "Nothing to translate",
                    "Click into a text field with something in it, then press the key.",
                )
                return
            if len(source) > MAX_FIELD_CHARS:
                notify.error(
                    "That is too much text to replace",
                    f"{len(source)} characters came back, which usually means the "
                    "focus was not in a text field. Nothing was changed.",
                )
                return

            loop = asyncio.get_running_loop()
            translated, engine = await loop.run_in_executor(
                None, functools.partial(self.translator.translate, source)
            )
            if not translated:
                notify.error("Translation failed", "Nothing came back. Nothing was changed.")
                return
            if translated.strip() == source:
                notify.notify(
                    f"Already in {language_name(self.config.translate_target)}",
                    "The text is left as it is.",
                )
                return

            await self.injector.paste(translated, replace_selection=True)
            print(f"talkkey: translated {engine}")
        except (TranslationError, PortalError, clipboard.ClipboardError) as exc:
            notify.error("Translation failed", str(exc))
            print(f"talkkey: {exc}")
        except Exception as exc:  # noqa: BLE001 - same reasoning as above
            notify.error("Translation failed", str(exc))
            print(f"talkkey: unexpected error: {exc!r}")
        finally:
            self._busy = False
