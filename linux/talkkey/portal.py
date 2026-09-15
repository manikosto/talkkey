"""Thin wrapper over the XDG desktop portals.

Every portal call is asynchronous in the same way: the method returns the
object path of a Request, and the real answer arrives later as a Response
signal on that path. The subscription has to exist before the call is made,
or a fast portal can answer before anyone is listening — hence the token is
chosen up front and the path derived from it rather than taken from the
method's return value.
"""

from __future__ import annotations

import asyncio
import secrets

from dbus_next import BusType, Variant
from dbus_next.aio import MessageBus

PORTAL_BUS = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
REQUEST_IFACE = "org.freedesktop.portal.Request"


class PortalError(RuntimeError):
    """A portal refused a request, or no portal answered at all."""


class Portal:
    def __init__(self) -> None:
        self.bus: MessageBus | None = None
        self._introspection = None

    async def connect(self) -> None:
        self.bus = await MessageBus(bus_type=BusType.SESSION).connect()
        self._introspection = await self.bus.introspect(PORTAL_BUS, PORTAL_PATH)

    def interface(self, name: str):
        if self.bus is None or self._introspection is None:
            raise PortalError("portal not connected")
        obj = self.bus.get_proxy_object(PORTAL_BUS, PORTAL_PATH, self._introspection)
        try:
            return obj.get_interface(name)
        except Exception as exc:  # noqa: BLE001 - surfaced with context below
            raise PortalError(
                f"this desktop does not offer {name}. "
                "On KDE it needs Plasma 6.1 or newer, on GNOME version 48 or newer."
            ) from exc

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

        introspection = await self.bus.introspect(PORTAL_BUS, request_path)
        request_obj = self.bus.get_proxy_object(PORTAL_BUS, request_path, introspection)
        request = request_obj.get_interface(REQUEST_IFACE)

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
