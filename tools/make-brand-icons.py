#!/usr/bin/env python3
"""把 SenderAvatar.swift 里用到的品牌图形从 Simple Icons 复制进 Assets.xcassets/Brands。

Simple Icons(https://simpleicons.org)是 CC0 的品牌图标库，只用它的 SVG 数据：
    npm pack simple-icons@16.35.0 && tar -xzf simple-icons-16.35.0.tgz
    python3 tools/make-brand-icons.py package/icons
"""
import json
import re
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
icons = Path(sys.argv[1])
swift = (root / "MailHub/Views/SenderAvatar.swift").read_text()
slugs = sorted(set(re.findall(r'\.icon\("([a-z0-9]+)"\)', swift)))

out = root / "MailHub/Assets.xcassets/Brands"
shutil.rmtree(out, ignore_errors=True)
out.mkdir(parents=True)
(out / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
for slug in slugs:
    d = out / f"brand-{slug}.imageset"
    d.mkdir()
    shutil.copy(icons / f"{slug}.svg", d / f"{slug}.svg")
    (d / "Contents.json").write_text(json.dumps({
        "images": [{"filename": f"{slug}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    }, indent=2) + "\n")
print(f"{len(slugs)} 个图标 → {out.relative_to(root)}")
