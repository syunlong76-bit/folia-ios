#!/usr/bin/env python3
"""3.6 (7) P1 CI 卡点（DS 第十六轮 4.1）：静态断言墙解码登记表钳制的
结构模式在供包 JS 里可命中。前端升级若改了 wall chunk 结构导致模式
全灭（total == 0），P1 会静默失效——CI 直接失败，不许带病出包；
命中数 != 3 只警告（根目录增减时人工确认）。

模式与 LocalServer.WallRegistryPatch 的 Swift 正则保持同构。
"""
import re
import sys
from pathlib import Path

PAT = re.compile(
    r"([A-Za-z_$][\w$]*)=(\d{2,4}),([A-Za-z_$][\w$]*)=new Map,"
    r"([A-Za-z_$][\w$]*)=new Map,([A-Za-z_$][\w$]*)=new Map,"
    r"([A-Za-z_$][\w$]*)=\(e,t\)=>\{for\(e\.delete\(t\),e\.set\(t,!0\);e\.size>\1"
)

ROOT = Path(__file__).resolve().parent.parent / "Resources"


def main() -> int:
    total = 0
    hits = []
    for js in sorted(ROOT.glob("Web*/assets/*.js")):
        text = js.read_text(encoding="utf-8", errors="replace")
        n = len(PAT.findall(text))
        if n:
            total += n
            hits.append(f"{js.relative_to(ROOT)}: {n}")
    for h in hits:
        print(f"registry-patch pattern hit: {h}")
    print(f"registry-patch total matches: {total}")
    if total == 0:
        print("ERROR: registry patch pattern matches NOTHING — P1 would be silently dead. "
              "Frontend wall chunk structure changed; update WallRegistryPatch anchor before shipping.")
        return 1
    if total != 3:
        print(f"WARNING: expected 3 matches (one per web root), got {total} — verify by hand.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
