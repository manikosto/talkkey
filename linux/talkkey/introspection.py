"""Hand-written D-Bus interface descriptions for the portals we use.

Asking the portal to describe itself does not work. xdg-desktop-portal
publishes a property named `power-saver-enabled`, and a D-Bus member name
may not contain a hyphen, so dbus-next's validator rejects the whole
document — including the interfaces we do want — with
`InvalidMemberNameError: power-saver-enabled`. One unrelated interface
would otherwise take the app down with it.

Describing the three interfaces here instead means nothing the desktop adds
later can break startup, and there is no introspection round trip on the
way up. The cost is that these signatures have to match the portal spec; a
mismatch shows up as a D-Bus signature error on the call itself.
"""

GLOBAL_SHORTCUTS = """
<node>
  <interface name="org.freedesktop.portal.GlobalShortcuts">
    <method name="CreateSession">
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <method name="BindShortcuts">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a(sa{sv})" name="shortcuts" direction="in"/>
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <method name="ListShortcuts">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <signal name="Activated">
      <arg type="o" name="session_handle"/>
      <arg type="s" name="shortcut_id"/>
      <arg type="t" name="timestamp"/>
      <arg type="a{sv}" name="options"/>
    </signal>
    <signal name="Deactivated">
      <arg type="o" name="session_handle"/>
      <arg type="s" name="shortcut_id"/>
      <arg type="t" name="timestamp"/>
      <arg type="a{sv}" name="options"/>
    </signal>
    <signal name="ShortcutsChanged">
      <arg type="o" name="session_handle"/>
      <arg type="a(sa{sv})" name="shortcuts"/>
    </signal>
  </interface>
</node>
"""

REMOTE_DESKTOP = """
<node>
  <interface name="org.freedesktop.portal.RemoteDesktop">
    <method name="CreateSession">
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <method name="SelectDevices">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <method name="Start">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="o" name="handle" direction="out"/>
    </method>
    <method name="NotifyKeyboardKeycode">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="i" name="keycode" direction="in"/>
      <arg type="u" name="state" direction="in"/>
    </method>
    <method name="NotifyKeyboardKeysym">
      <arg type="o" name="session_handle" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="i" name="keysym" direction="in"/>
      <arg type="u" name="state" direction="in"/>
    </method>
  </interface>
</node>
"""

REQUEST = """
<node>
  <interface name="org.freedesktop.portal.Request">
    <method name="Close"/>
    <signal name="Response">
      <arg type="u" name="response"/>
      <arg type="a{sv}" name="results"/>
    </signal>
  </interface>
</node>
"""

BY_NAME = {
    "org.freedesktop.portal.GlobalShortcuts": GLOBAL_SHORTCUTS,
    "org.freedesktop.portal.RemoteDesktop": REMOTE_DESKTOP,
    "org.freedesktop.portal.Request": REQUEST,
}
