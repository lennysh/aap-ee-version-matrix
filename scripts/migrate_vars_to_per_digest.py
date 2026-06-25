#!/usr/bin/env python3
"""
Split legacy monolithic vars.yml files into per-digest vars/<hex>.yml files.

Each image path directory had a single vars.yml with an images: list. This script
creates vars/<digest-hex>.yml for each entry and removes the old vars.yml.
"""

from __future__ import annotations

import sys
from pathlib import Path

import yaml


def digest_hex(digest: str) -> str:
    return digest.removeprefix("sha256:")


def migrate_vars_file(vars_path: Path) -> tuple[int, str | None]:
    with vars_path.open() as f:
        data = yaml.safe_load(f)

    if not data or "images" not in data:
        return 0, "No images found"

    vars_dir = vars_path.parent / "vars"
    vars_dir.mkdir(exist_ok=True)

    written = 0
    for image in data["images"]:
        digest = image.get("digest")
        if not digest:
            continue
        out_path = vars_dir / f"{digest_hex(digest)}.yml"
        with out_path.open("w") as f:
            yaml.dump(image, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
            f.write("\n")
        written += 1

    vars_path.unlink()
    return written, None


def main() -> int:
    images_dir = Path("images")
    if not images_dir.is_dir():
        print("No images/ directory found", file=sys.stderr)
        return 1

    legacy_files = sorted(images_dir.rglob("vars.yml"))
    if not legacy_files:
        print("No legacy vars.yml files to migrate")
        return 0

    total_written = 0
    errors = False

    for vars_path in legacy_files:
        count, error = migrate_vars_file(vars_path)
        if error:
            print(f"ERROR in {vars_path}: {error}")
            errors = True
            continue
        print(f"Migrated {vars_path} -> {vars_path.parent / 'vars'}/ ({count} digests)")
        total_written += count

    if errors:
        return 1

    print(f"\nDone. Migrated {total_written} digest records from {len(legacy_files)} vars.yml files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
