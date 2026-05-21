import asyncio
from asyncio.events import AbstractEventLoop
import os
import sys

from bless.backends.attribute import GATTAttributePermissions
from bless.backends.characteristic import GATTCharacteristicProperties

from ble.handlers import InputHandler
from ble.uuid import INPUT_UUID, LOCAL_NAME, SERVICE_UUID, STATUS_UUID


class VirtualHidPeripheral:
    def __init__(self) -> None:
        self._patch_unused_winrt_adapter_probe()
        from bless import BlessServer

        self._server = BlessServer(name=LOCAL_NAME)
        self._handler = InputHandler(self._notify_status)
        self._quiet = os.environ.get("VHID_QUIET") == "1"
        self._loop: AbstractEventLoop | None = None

    async def start(self) -> None:
        self._loop = asyncio.get_running_loop()
        await self._server.add_new_service(SERVICE_UUID)
        await self._server.add_new_characteristic(
            SERVICE_UUID,
            INPUT_UUID,
            GATTCharacteristicProperties.write_without_response,
            None,
            GATTAttributePermissions.writeable,
        )
        await self._server.add_new_characteristic(
            SERVICE_UUID,
            STATUS_UUID,
            GATTCharacteristicProperties.notify,
            bytearray(),
            GATTAttributePermissions.readable,
        )
        self._server.write_request_func = self._on_write
        # bless 0.3.0 WinRT can wait forever for the advertising status callback.
        # The service provider still starts advertising; this only prevents a
        # console process that cannot be stopped cleanly during Phase 1 testing.
        advertising_started = getattr(self._server, "_advertising_started", None)
        if advertising_started is not None:
            advertising_started.set()
        await self._server.start()
        if not self._quiet:
            print(f"advertising as {LOCAL_NAME}", flush=True)

    async def stop(self) -> None:
        await self._server.stop()

    def _on_write(self, characteristic: object, value: bytearray, **_: object) -> None:
        uuid = getattr(characteristic, "uuid", "").lower()
        if uuid != INPUT_UUID:
            return
        self._handler.handle_write(bytes(value))

    def _notify_status(self, data: bytes) -> None:
        if self._loop is None:
            return
        asyncio.run_coroutine_threadsafe(self._notify_status_async(data), self._loop)

    async def _notify_status_async(self, data: bytes) -> None:
        self._server.get_characteristic(STATUS_UUID).value = bytearray(data)
        self._server.update_value(SERVICE_UUID, STATUS_UUID)

    def _patch_unused_winrt_adapter_probe(self) -> None:
        if sys.platform != "win32":
            return

        from bless.backends.winrt import server

        class _NoopAdapter:
            def set_local_name(self, local_name: str) -> None:
                return

        server.BLEAdapter = _NoopAdapter
