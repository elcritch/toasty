#!/usr/bin/env python3
"""Capture a PNG from a WayVNC server without external Python packages."""

from __future__ import annotations

import argparse
import binascii
import os
import socket
import struct
import sys
import time
import zlib
from pathlib import Path


RFB_VERSION = b"RFB 003.008\n"
SECURITY_NONE = 1
ENCODING_RAW = 0


def receive_exact(connection: socket.socket, size: int) -> bytes:
    chunks = bytearray()
    while len(chunks) < size:
        chunk = connection.recv(size - len(chunks))
        if not chunk:
            raise RuntimeError("WayVNC closed the connection")
        chunks.extend(chunk)
    return bytes(chunks)


def connect_rfb(
    host: str, port: int, timeout: float
) -> tuple[socket.socket, int, int, str]:
    connection = socket.create_connection((host, port), timeout=timeout)
    connection.settimeout(timeout)

    version = receive_exact(connection, 12)
    if not version.startswith(b"RFB "):
        raise RuntimeError(f"invalid RFB greeting: {version!r}")
    connection.sendall(RFB_VERSION)

    security_count = receive_exact(connection, 1)[0]
    if security_count == 0:
        reason_length = struct.unpack(">I", receive_exact(connection, 4))[0]
        reason = receive_exact(connection, reason_length).decode(errors="replace")
        raise RuntimeError(f"WayVNC rejected the connection: {reason}")
    security_types = receive_exact(connection, security_count)
    if SECURITY_NONE not in security_types:
        offered = ", ".join(str(value) for value in security_types)
        raise RuntimeError(
            "WayVNC does not offer unauthenticated RFB security "
            f"(offered types: {offered})"
        )

    connection.sendall(bytes([SECURITY_NONE]))
    security_status = struct.unpack(">I", receive_exact(connection, 4))[0]
    if security_status != 0:
        reason_length = struct.unpack(">I", receive_exact(connection, 4))[0]
        reason = receive_exact(connection, reason_length).decode(errors="replace")
        raise RuntimeError(f"WayVNC authentication failed: {reason}")

    connection.sendall(b"\x01")  # Share the session with other VNC clients.
    width, height = struct.unpack(">HH", receive_exact(connection, 4))
    receive_exact(connection, 16)  # Server pixel format; replaced below.
    name_length = struct.unpack(">I", receive_exact(connection, 4))[0]
    server_name = receive_exact(connection, name_length).decode(errors="replace")

    # Request little-endian BGRX. Each pixel is then easy to convert to PNG RGB.
    pixel_format = struct.pack(
        ">BBBBHHHBBB3x",
        32,
        24,
        0,
        1,
        255,
        255,
        255,
        16,
        8,
        0,
    )
    connection.sendall(b"\x00\x00\x00\x00" + pixel_format)
    connection.sendall(struct.pack(">BBHi", 2, 0, 1, ENCODING_RAW))
    return connection, width, height, server_name


def receive_framebuffer_update(connection: socket.socket, canvas: bytearray, width: int, height: int) -> None:
    while True:
        message_type = receive_exact(connection, 1)[0]
        if message_type == 0:
            break
        if message_type == 2:  # Bell
            continue
        if message_type == 3:  # ServerCutText
            receive_exact(connection, 3)
            text_length = struct.unpack(">I", receive_exact(connection, 4))[0]
            receive_exact(connection, text_length)
            continue
        raise RuntimeError(f"unsupported RFB server message type: {message_type}")

    receive_exact(connection, 1)
    rectangle_count = struct.unpack(">H", receive_exact(connection, 2))[0]
    for _ in range(rectangle_count):
        x, y, rect_width, rect_height, encoding = struct.unpack(
            ">HHHHi", receive_exact(connection, 12)
        )
        if encoding != ENCODING_RAW:
            raise RuntimeError(f"unsupported RFB rectangle encoding: {encoding}")
        if x + rect_width > width or y + rect_height > height:
            raise RuntimeError("WayVNC sent a rectangle outside the framebuffer")

        raw = receive_exact(connection, rect_width * rect_height * 4)
        for row in range(rect_height):
            source_row = row * rect_width * 4
            target_row = ((y + row) * width + x) * 3
            for column in range(rect_width):
                source = source_row + column * 4
                target = target_row + column * 3
                canvas[target : target + 3] = (
                    raw[source + 2],
                    raw[source + 1],
                    raw[source],
                )


def capture_framebuffer(
    connection: socket.socket,
    width: int,
    height: int,
    frames: int,
    frame_delay: float,
) -> bytearray:
    canvas = bytearray(width * height * 3)
    request = struct.pack(">BBHHHH", 3, 0, 0, 0, width, height)
    for frame in range(frames):
        if frame > 0 and frame_delay > 0:
            time.sleep(frame_delay)
        connection.sendall(request)
        receive_framebuffer_update(connection, canvas, width, height)
    return canvas


def png_chunk(kind: bytes, payload: bytes) -> bytes:
    checksum = binascii.crc32(kind + payload) & 0xFFFFFFFF
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", checksum)


def write_png(path: Path, pixels: bytearray, width: int, height: int) -> None:
    stride = width * 3
    scanlines = bytearray()
    for row in range(height):
        scanlines.append(0)
        start = row * stride
        scanlines.extend(pixels[start : start + stride])
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", header)
        + png_chunk(b"IDAT", zlib.compress(scanlines, level=6))
        + png_chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="PNG output path")
    parser.add_argument("--host", default="127.0.0.1", help="WayVNC host")
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("TOASTY_VNC_PORT", "5905")),
        help="WayVNC port (default: TOASTY_VNC_PORT or 5905)",
    )
    parser.add_argument(
        "--timeout", type=float, default=5.0, help="socket timeout in seconds"
    )
    parser.add_argument(
        "--frames",
        type=int,
        default=2,
        help="full frames to request; the first may be WayVNC's placeholder",
    )
    parser.add_argument(
        "--frame-delay",
        type=float,
        default=0.5,
        help="delay between requested frames in seconds",
    )
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    if args.frames < 1:
        parser.error("--frames must be at least 1")
    if args.frame_delay < 0:
        parser.error("--frame-delay cannot be negative")
    return args


def main() -> int:
    args = parse_args()
    try:
        connection, width, height, server_name = connect_rfb(
            args.host, args.port, args.timeout
        )
        try:
            pixels = capture_framebuffer(
                connection, width, height, args.frames, args.frame_delay
            )
        finally:
            connection.close()
        write_png(args.output, pixels, width, height)
    except (OSError, RuntimeError, struct.error) as error:
        print(f"wayvnc-screenshot: {error}", file=sys.stderr)
        return 1

    print(
        f"wayvnc-screenshot: captured {width}x{height} from "
        f"{server_name or args.host} to {args.output}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
