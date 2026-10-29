#!/usr/bin/env python3
"""Deterministic 16-bit PCM WAV generator for mayhem/test.sh: gen_wav.py <channels> <out.wav>."""
import math
import struct
import sys

RATE = 44100
FRAMES = 22050


def sample(n, ch):
    f1 = 440.0 * (ch + 1)
    f2 = 1250.0 + 310.0 * ch
    v = 3000.0 * math.sin(2 * math.pi * f1 * n / RATE)
    v += 1200.0 * math.sin(2 * math.pi * f2 * n / RATE)
    v += 400.0 * math.sin(2 * math.pi * 3300.0 * n / RATE) * (1.0 if (n // 2000) % 2 else 0.25)
    return int(round(v))


def main():
    channels = int(sys.argv[1])
    data = bytearray()
    for n in range(FRAMES):
        for ch in range(channels):
            data += struct.pack("<h", sample(n, ch))
    header = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt " + struct.pack(
        "<IHHIIHH", 16, 1, channels, RATE, RATE * channels * 2, channels * 2, 16
    ) + b"data" + struct.pack("<I", len(data))
    with open(sys.argv[2], "wb") as f:
        f.write(header + bytes(data))


main()
