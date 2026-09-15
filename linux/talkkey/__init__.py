"""TalkKey for Linux — push-to-talk dictation and in-place translation.

The macOS app this mirrors leans on Accessibility, CGEvent taps and the
Apple Translation framework, none of which exist here. The Wayland
equivalents are deliberately narrower, so the shape is different:

* Hotkeys come from the XDG GlobalShortcuts portal, which reports a press
  and a release — enough for hold-to-talk, but only for key *combinations*.
  A bare modifier like macOS's Right Command cannot be bound.
* Text is delivered by putting it on the clipboard and sending Ctrl+V
  through the RemoteDesktop portal. Typing it out character by character
  is not an option: ydotool handles US-ASCII only, which rules out every
  language TalkKey exists for, and wtype does not work on KDE.
* Reading what is already in a field uses AT-SPI where the app exposes it,
  and falls back to Ctrl+A / Ctrl+C with the clipboard put back afterwards.
"""

__version__ = "0.1.0"
