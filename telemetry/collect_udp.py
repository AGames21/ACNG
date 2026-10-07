"""Receive ACNG JSON datagrams on loopback; preserve samples and loss indicators."""
import argparse
import json
import socket
import time
from pathlib import Path


def collect(output, duration=30.0, port=44443, idle_timeout=None):
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    counts = {"accepted": 0, "malformed": 0, "sequence_gaps": 0, "out_of_order": 0}
    last = {}
    started = time.monotonic()
    last_accepted = None
    finish_reason = 'duration'
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock, output.open("x", encoding="utf-8") as stream:
        sock.bind(("127.0.0.1", port))
        sock.settimeout(0.25)
        deadline = time.monotonic() + duration
        while time.monotonic() < deadline:
            if idle_timeout is not None and last_accepted is not None and time.monotonic()-last_accepted>=idle_timeout:
                finish_reason='idle_after_samples'
                break
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
                key = (row.get("capture_id"), row["vehicle_id"], row["generation"])
                prior = last.get(key)
                if prior is not None:
                    counts["sequence_gaps"] += max(0, seq - prior - 1)
                    counts["out_of_order"] += int(seq <= prior)
                last[key] = max(seq, prior or 0)
                row["host_monotonic_s"] = time.monotonic()
                stream.write(json.dumps(row, allow_nan=False) + "\n")
                counts["accepted"] += 1
                last_accepted=row['host_monotonic_s']
                # Expose complete samples for live inspection/process recovery.
                stream.flush()
            except (ValueError, KeyError, TypeError, UnicodeError):
                counts["malformed"] += 1
    summary = {**counts, "duration_requested_s": duration, "duration_observed_s":time.monotonic()-started,
               "finish_reason":finish_reason,"idle_timeout_s":idle_timeout,"port": port, "output": str(output)}
    output.with_suffix(".summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    return summary


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output")
    parser.add_argument("--duration", type=float, default=30)
    parser.add_argument("--port", type=int, default=44443)
    parser.add_argument('--idle-timeout',type=float,help='End after this many silent seconds, only after accepting a sample')
    args = parser.parse_args()
    if args.duration <= 0 or not 1024 <= args.port <= 65535:
        parser.error("duration must be positive; port must be 1024..65535")
    if args.idle_timeout is not None and args.idle_timeout<=0:parser.error('Idle timeout must be positive')
    print(json.dumps(collect(args.output, args.duration, args.port,args.idle_timeout), indent=2))
