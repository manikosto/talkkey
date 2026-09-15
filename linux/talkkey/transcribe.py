"""Speech to text: faster-whisper on this machine, or the OpenAI API.

faster-whisper stands in for WhisperKit, which is CoreML and so has no
Linux build. The first run downloads the model, which is why the loader is
lazy and says so rather than appearing to hang.
"""

from __future__ import annotations

import tempfile

import numpy as np

from . import audio as audio_mod
from .config import Config


class TranscriptionError(RuntimeError):
    pass


class Transcriber:
    def __init__(self, config: Config) -> None:
        self.config = config
        self._model = None

    def warm_up(self) -> None:
        """Load the model before the first real request, not during it."""
        if self.config.speech_engine == "local":
            self._load_local()

    def _load_local(self):
        if self._model is not None:
            return self._model
        try:
            from faster_whisper import WhisperModel
        except ImportError as exc:
            raise TranscriptionError(
                "local speech recognition needs faster-whisper:\n"
                "  pip install 'talkkey-linux[local]'\n"
                "Or set speech.engine = \"openai\" in the config."
            ) from exc

        print(f"talkkey: loading the {self.config.speech_model} model "
              "(the first run downloads it, which takes a while)…")
        self._model = WhisperModel(
            self.config.speech_model,
            device="auto",
            compute_type=self.config.compute_type,
        )
        return self._model

    def transcribe(self, samples: np.ndarray) -> str:
        if audio_mod.duration(samples) < 0.25:
            return ""
        if self.config.speech_engine == "openai":
            return self._via_openai(samples)
        return self._via_local(samples)

    def _via_local(self, samples: np.ndarray) -> str:
        model = self._load_local()
        language = None if self.config.speech_language == "auto" else self.config.speech_language
        segments, _info = model.transcribe(samples, language=language, beam_size=5)
        return " ".join(segment.text.strip() for segment in segments).strip()

    def _via_openai(self, samples: np.ndarray) -> str:
        client = _openai_client(self.config)
        with tempfile.NamedTemporaryFile(suffix=".wav") as handle:
            handle.write(audio_mod.to_wav(samples))
            handle.flush()
            handle.seek(0)
            kwargs = {}
            if self.config.speech_language != "auto":
                kwargs["language"] = self.config.speech_language
            with open(handle.name, "rb") as audio_file:
                result = client.audio.transcriptions.create(
                    model=self.config.openai_speech_model,
                    file=audio_file,
                    **kwargs,
                )
        return (result.text or "").strip()


def _openai_client(config: Config):
    try:
        from openai import OpenAI
    except ImportError as exc:
        raise TranscriptionError(
            "this needs the OpenAI client:\n  pip install 'talkkey-linux[cloud]'"
        ) from exc
    if not config.api_key:
        raise TranscriptionError(
            "no OpenAI key. Put one in the config under [openai] api_key, "
            "or set OPENAI_API_KEY in the environment."
        )
    return OpenAI(api_key=config.api_key)
