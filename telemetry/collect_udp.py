"""Receive ACNG JSON datagrams on loopback; preserve samples and loss indicators."""
import argparse
import json
import socket
import time
from pathlib import Path


def collect(output, duration=30.0, port=44443):
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    counts = {"accepted": 0, "malformed": 0, "sequence_gaps": 0, "out_of_order": 0}
    last = {}
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock, output.open("x", encoding="utf-8") as stream:
        sock.bind(("127.0.0.1", port))
        sock.settimeout(0.25)
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            try:
                payload, peer = sock.recvfrom(65535)
            except socket.timeout:
                continue
            try:
                row = json.loads(payload)
                if row["schema_version"] != 1 or row["source"] != "beamng":
                    raise ValueError("unsupported schema/source")
                seq = row["sequence"]
                if not isinstance(seq, int) or seq < 1:
                    raise ValueError("invalid sequence")
                key = (row["vehicle_id"], row["generation"])
                prior = last.get(key)
                if prior is not None:
                    counts["sequence_gaps"] += max(0, seq - prior - 1)
                    counts["out_of_order"] += int(seq <= prior)
                last[key] = max(seq, prior or 0)
                row["host_monotonic_s"] = time.monotonic()
                stream.write(json.dumps(row, allow_nan=False) + "\n")
                counts["accepted"] += 1
            except (ValueError, KeyError, TypeError, UnicodeError):
                counts["malformed"] += 1
    summary = {**counts, "duration_requested_s": duration, "port": port, "output": str(output)}
    output.with_suffix(".summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output")
    parser.add_argument("--duration", type=float, default=30)
    parser.add_argument("--port", type=int, default=44443)
    args = parser.parse_args()
    if args.duration <= 0 or not 1024 <= args.port <= 65535:
        parser.error("duration must be positive; port must be 1024..65535")
    print(json.dumps(collect(args.output, args.duration, args.port), indent=2))
