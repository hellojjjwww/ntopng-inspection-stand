#!/usr/bin/env python3
"""Generate lab-only anomalous packets for ntopng alert validation.

File: generate_anomaly.py
Version: 1.1.0
License: MIT
"""

from __future__ import annotations

import argparse
import random
import string
import time

from scapy.all import DNS, DNSQR, ICMP, IP, RandShort, UDP, Raw, send
from scapy.layers.inet import TCP


def syn_flood(args: argparse.Namespace) -> None:
    for _ in range(args.count):
        packet = (
            IP(dst=args.target, src=args.source or random_private_ip())
            / TCP(sport=RandShort(), dport=args.port, flags="S", seq=random.randint(0, 2**32 - 1))
        )
        send(packet, verbose=False)
        sleep(args.delay)


def suspicious_dns(args: argparse.Namespace) -> None:
    for _ in range(args.count):
        label = "".join(random.choices(string.ascii_lowercase + string.digits, k=args.label_length))
        qname = f"{label}.{args.domain}"
        packet = IP(dst=args.resolver) / UDP(sport=RandShort(), dport=53) / DNS(rd=1, qd=DNSQR(qname=qname))
        send(packet, verbose=False)
        sleep(args.delay)


def oversized_icmp(args: argparse.Namespace) -> None:
    payload = b"X" * args.size
    for _ in range(args.count):
        packet = IP(dst=args.target) / ICMP() / Raw(load=payload)
        send(packet, verbose=False)
        sleep(args.delay)


def random_private_ip() -> str:
    return f"10.{random.randint(1, 254)}.{random.randint(1, 254)}.{random.randint(1, 254)}"


def sleep(delay: float) -> None:
    if delay > 0:
        time.sleep(delay)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate anomaly traffic for an ntopng lab")
    subparsers = parser.add_subparsers(dest="mode", required=True)

    syn = subparsers.add_parser("syn-flood", help="Generate TCP SYN packets")
    syn.add_argument("--target", required=True, help="Target IP controlled by your lab")
    syn.add_argument("--port", type=int, default=80)
    syn.add_argument("--source", help="Optional spoofed source IP")
    syn.add_argument("--count", type=int, default=200)
    syn.add_argument("--delay", type=float, default=0.005)
    syn.set_defaults(func=syn_flood)

    dns = subparsers.add_parser("suspicious-dns", help="Generate high-entropy DNS queries")
    dns.add_argument("--resolver", required=True, help="DNS resolver IP")
    dns.add_argument("--domain", required=True, help="Domain suffix you control or use for lab testing")
    dns.add_argument("--label-length", type=int, default=48)
    dns.add_argument("--count", type=int, default=100)
    dns.add_argument("--delay", type=float, default=0.02)
    dns.set_defaults(func=suspicious_dns)

    mtu = subparsers.add_parser("oversized-icmp", help="Generate large ICMP packets")
    mtu.add_argument("--target", required=True, help="Target IP controlled by your lab")
    mtu.add_argument("--size", type=int, default=3000)
    mtu.add_argument("--count", type=int, default=5)
    mtu.add_argument("--delay", type=float, default=0.5)
    mtu.set_defaults(func=oversized_icmp)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
