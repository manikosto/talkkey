"""Thin wrapper over the XDG desktop portals.

Every portal call is asynchronous in the same way: the method returns the
object path of a Request, and the real answer arrives later as a Response
signal on that path. The subscription has to exist before the call is made,
or a fast portal can answer before anyone is listening — hence the token is
chosen up front and the path derived from it rather than taken from the
method's return value.

Nothing here asks the portal to describe itself; see `introspection.py` for
why that cannot be done. The interface descriptions are ours, so the proxies
are built without a round trip and no interface we do not use can break us.
"""

from __future__ import annotations

import asyncio
import secrets

from dbus_next import BusType, Message, Variant
from dbus_next.aio import MessageBus
from dbus_next.introspection import Node

from . import introspection

PORTAL_BUS = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
REQUEST_IFACE = "org.freedesktop.portal.Request"


class PortalError(RuntimeError):
    """A portal refused a request, or no portal answered at all."""


class Portal:
    def __init__(self) -> None:
        self.bus: MessageBus | None = None
        self._nodes: dict[str, Node] = {}

    async def connect(self) -> None:
        self.bus = await MessageBus(bus_type=BusType.SESSION).connect()

    def _node(self, iface_name: str) -> Node:
        if iface_name not in self._nodes:
            xml = introspection.BY_NAME.get(iface_name)
            if xml is None:
                raise PortalError(f"no description on file for {iface_name}")
            self._nodes[iface_name] = Node.parse(xml)
        return self._nodes[iface_name]

    def interface(self, name: str, path: str = PORTAL_PATH):
        if self.bus is None:
            raise PortalError("portal not connected")
        obj = self.bus.get_proxy_object(PORTAL_BUS, path, self._node(name))
        return obj.get_interface(name)

    async def raw_introspect(self) -> str:
        """The portal's own description, as text.

        Returned unparsed on purpose: it contains a property name with a
        hyphen that no D-Bus parser will accept. Searching the text is how
        `doctor` can honestly report which portals this desktop offers.
        """
        if self.bus is None:
            raise PortalError("portal not connected")
        reply = await self.bus.call(
            Message(
                destination=PORTAL_BUS,
                path=PORTAL_PATH,
                interface="org.freedesktop.DBus.Introspectable",
                member="Introspect",
            )
        )
        if reply is None or not reply.body:
            raise PortalError("the portal service did not describe itself")
        return reply.body[0]

    async def has_interface(self, name: str) -> bool:
        try:
            return f'"{name}"' in await self.raw_introspect()
        except Exception:  # noqa: BLE001 - absence is the answer
            return False

    def new_token(self) -> str:
        return "talkkey_" + secrets.token_hex(8)

    async def call(self, coro_factory, token: str, timeout: float = 120.0) -> dict:
        """Run a portal method and wait for the Response that answers it.

        `coro_factory` is handed the options dict (already carrying the
        handle_token) and returns the coroutine for the method call.
        """
        if self.bus is None:
            raise PortalError("portal not connected")

        sender = self.bus.unique_name[1:].replace(".", "_")
        request_path = f"{PORTAL_PATH}/request/{sender}/{token}"

        loop = asyncio.get_running_loop()
        answered: asyncio.Future = loop.create_future()

        request = self.interface(REQUEST_IFACE, path=request_path)

        def on_response(code: int, results: dict) -> None:
            if not answered.done():
                answered.set_result((code, results))

        request.on_response(on_response)
        try:
            await coro_factory({"handle_token": Variant("s", token)})
            code, results = await asyncio.wait_for(answered, timeout=timeout)
        except asyncio.TimeoutError as exc:
            raise PortalError(
                "the desktop never answered the portal request. "
                "If a permission dialog appeared, it may still be waiting for you."
            ) from exc
        finally:
            try:
                request.off_response(on_response)
            except Exception:  # noqa: BLE001 - nothing useful to do on teardown
                pass

        if code == 1:
            raise PortalError("you dismissed the request")
        if code != 0:
            raise PortalError(f"the portal refused the request (code {code})")
        return {key: value.value if isinstance(value, Variant) else value
                for key, value in results.items()}
