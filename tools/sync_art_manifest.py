# -*- coding: utf-8 -*-
"""
sync_art_manifest.py —— 把 art/2d 下的正式 PNG 全量对账进 art/manifest.json。

背景：批次⑤~⑪ 的 80 张卡面由并行产线直接落盘，未走登记管线，
     导致 manifest 长期停在 163 项而磁盘已有 301 张（2026-11-09 梳理发现）。
纪律：只补缺失条目，不删已有条目、不改已有条目的任何字段；
     新增条目按 art-bible §10.2 四段式文件名登记，size 从 PNG 头读取。

用法：py -3.9 tools/sync_art_manifest.py [--dry-run]
"""

import argparse
import json
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "2d")
MANIFEST = os.path.join(ROOT, "art", "manifest.json")


def scan_disk():
    found = {}
    for dp, _dn, fn in os.walk(SRC):
        for f in fn:
            if not f.lower().endswith(".png"):
                continue
            path = os.path.join(dp, f)
            rel = os.path.relpath(path, SRC).replace(os.sep, "/")
            with Image.open(path) as im:
                found[rel] = [im.width, im.height]
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="只报告差异，不写文件")
    args = ap.parse_args()

    with open(MANIFEST, encoding="utf-8") as fh:
        doc = json.load(fh)
    existing = {x["file"]: x for x in doc["assets"]}
    disk = scan_disk()

    added = [rel for rel in sorted(disk) if rel not in existing]
    orphaned = [rel for rel in sorted(existing) if rel not in disk]
    mismatched = [
        (rel, existing[rel].get("size"), disk[rel])
        for rel in sorted(existing)
        if rel in disk and existing[rel].get("size") != disk[rel]
    ]

    print("manifest 原有 %d 项 / 磁盘 %d 张 PNG" % (len(existing), len(disk)))
    print("待补登记 %d 项 / 清单孤儿 %d 项 / size 不符 %d 项" % (
        len(added), len(orphaned), len(mismatched)))
    for rel, old, real in mismatched[:10]:
        print("  ! size", rel, old, "->", real)
    for rel in orphaned[:10]:
        print("  - orphan", rel)

    if args.dry_run:
        return
    for rel in added:
        existing[rel] = {"file": rel, "size": disk[rel]}
    doc["assets"] = [existing[k] for k in sorted(existing)]
    with open(MANIFEST, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, ensure_ascii=False, indent=1)
    print("已写入 %s，现有 %d 项" % (MANIFEST, len(doc["assets"])))


if __name__ == "__main__":
    main()
