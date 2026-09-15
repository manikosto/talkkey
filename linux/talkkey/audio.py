"""Microphone capture, held open only while a key is down."""

from __future__ import annotations

import io
import wave

import numpy as np

SAMPLE_RATE = 16_000  # what every Whisper build expects
CHANNELS = 1


class AudioError(RuntimeError):
    pass


class Recorder:
    def __init__(self, device: int | str | None = None) -> None:
        self.device = device
        self._stream = None
        self._chunks: list[np.ndarray] = []

    def start(self) -> None:
        try:
            import sounddevice as sd
        except OSError as exc:  # PortAudio missing is an OSError, not ImportError
            raise AudioError(
                "PortAudio is not installed, so the microphone cannot be opened:\n"
                "  sudo apt install libportaudio2     # Debian, Ubuntu\n"
                "  sudo dnf install portaudio         # Fedora\n"
                "  sudo pacman -S portaudio           # Arch"
            ) from exc

        self._chunks = []

        def on_audio(indata, _frames, _time, status):
            if status:
                print(f"talkkey: audio input warning: {status}")
            self._chunks.append(indata.copy())

        self._stream = sd.InputStream(
            samplerate=SAMPLE_RATE,
            channels=CHANNELS,
            dtype="float32",
            device=self.device,
            callback=on_audio,
        )
        self._stream.start()

    def stop(self) -> np.ndarray:
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None
        if not self._chunks:
            return np.zeros(0, dtype=np.float32)
        return np.concatenate(self._chunks, axis=0).reshape(-1)

    @property
    def recording(self) -> bool:
        return self._stream is not None


def to_wav(audio: np.ndarray) -> bytes:
    """16-bit PCM WAV, for the APIs that want a file rather than samples."""
    clipped = np.clip(audio, -1.0, 1.0)
    pcm = (clipped * 32767).astype(np.int16)
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as handle:
        handle.setnchannels(CHANNELS)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(pcm.tobytes())
    return buffer.getvalue()


def duration(audio: np.ndarray) -> float:
    return len(audio) / SAMPLE_RATE
