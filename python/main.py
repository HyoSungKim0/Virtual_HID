import asyncio

from ble.peripheral import VirtualHidPeripheral


async def main() -> None:
    peripheral = VirtualHidPeripheral()
    try:
        await peripheral.start()
        print("Press Ctrl+C to stop.", flush=True)
        while True:
            await asyncio.sleep(3600)
    finally:
        await peripheral.stop()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("stopped", flush=True)
