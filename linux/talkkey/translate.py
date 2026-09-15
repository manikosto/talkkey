"""Translation. There is no Apple Translation here, so: OpenAI, or Argos.

Argos runs offline once a language pair is installed, which is the closest
thing Linux has to the on-device translation the macOS build uses. It is
noticeably worse than OpenAI on short conversational text, so OpenAI stays
the default and Argos is the choice for someone who wants no API key.
"""

from __future__ import annotations

from .config import Config

LANGUAGE_NAMES = {
    "en": "English", "ru": "Russian", "uk": "Ukrainian", "es": "Spanish",
    "fr": "French", "de": "German", "it": "Italian", "pt": "Portuguese",
    "zh": "Chinese", "ja": "Japanese", "ko": "Korean", "ar": "Arabic",
    "hi": "Hindi", "pl": "Polish", "tr": "Turkish", "nl": "Dutch",
}


class TranslationError(RuntimeError):
    pass


def language_name(code: str) -> str:
    return LANGUAGE_NAMES.get(code, code)


class Translator:
    def __init__(self, config: Config) -> None:
        self.config = config

    def translate(self, text: str, target: str | None = None) -> tuple[str, str]:
        """Returns the translation and which engine produced it."""
        target = target or self.config.translate_target
        text = text.strip()
        if not text:
            return "", ""
        if self.config.translate_engine == "argos":
            return self._via_argos(text, target), "on this machine"
        return self._via_openai(text, target), "via OpenAI"

    def _via_openai(self, text: str, target: str) -> str:
        from .transcribe import _openai_client  # shares the key handling

        client = _openai_client(self.config)
        response = client.chat.completions.create(
            model=self.config.openai_text_model,
            messages=[
                {
                    "role": "system",
                    "content": (
                        f"Translate the user's text into {language_name(target)}. "
                        "Reply with the translation and nothing else — no quotes, "
                        "no notes, no explanation. Keep the register and the line "
                        "breaks of the original. If it is already in that language, "
                        "repeat it unchanged."
                    ),
                },
                {"role": "user", "content": text},
            ],
            temperature=0.2,
        )
        return (response.choices[0].message.content or "").strip()

    def _via_argos(self, text: str, target: str) -> str:
        try:
            import argostranslate.translate as argos
        except ImportError as exc:
            raise TranslationError(
                "offline translation needs Argos:\n"
                "  pip install 'talkkey-linux[offline-translate]'"
            ) from exc

        source = self._detect(text)
        if source == target:
            return text
        try:
            return argos.translate(text, source, target)
        except Exception as exc:  # noqa: BLE001 - Argos raises bare exceptions
            raise TranslationError(
                f"Argos has no {source} to {target} pair installed. Install one with:\n"
                f"  argospm install translate-{source}_{target}"
            ) from exc

    @staticmethod
    def _detect(text: str) -> str:
        """Enough to tell Cyrillic from Latin, which is the case that matters."""
        cyrillic = sum(1 for ch in text if "Ѐ" <= ch <= "ӿ")
        if cyrillic > len(text.strip()) * 0.3:
            # Ukrainian has four letters Russian does not.
            return "uk" if any(ch in "їієґЇІЄҐ" for ch in text) else "ru"
        return "en"
