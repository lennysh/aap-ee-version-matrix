#!/usr/bin/env python3
"""
Check for duplicate tags across per-digest vars files within each image path.

Each image path has a vars/ directory with one YAML file per digest. This script
reports if any tag value appears on more than one digest within the same image path.
"""

import sys
from collections import defaultdict
from pathlib import Path

import yaml


def check_duplicate_tags(vars_dir: Path) -> tuple[dict | None, str | None]:
    """Check for duplicate tags across all digest vars files in a vars/ directory."""
    digest_files = sorted(vars_dir.glob("*.yml"))
    if not digest_files:
        return None, "No digest vars files found"

    tag_to_digests: dict[str, set[str]] = defaultdict(set)

    for digest_file in digest_files:
        try:
            with digest_file.open() as f:
                image = yaml.safe_load(f)
        except Exception as exc:
            return None, f"{digest_file.name}: {exc}"

        if not image:
            continue

        digest = image.get("digest", digest_file.stem)
        for tag in image.get("tags") or []:
            tag_to_digests[str(tag)].add(digest)

    duplicates = {
        tag: sorted(digests)
        for tag, digests in tag_to_digests.items()
        if len(digests) > 1
    }
    return duplicates, None


def main() -> int:
    images_dir = Path("images")
    vars_dirs = sorted(p for p in images_dir.rglob("vars") if p.is_dir())

    if not vars_dirs:
        print("No vars/ directories found in images/")
        return 1

    issues_found = False

    for vars_dir in vars_dirs:
        image_path = vars_dir.relative_to(images_dir)
        duplicates, error = check_duplicate_tags(vars_dir)

        if error:
            print(f"ERROR in {image_path}: {error}")
            issues_found = True
            continue

        if duplicates:
            print(f"\nDUPLICATE TAGS FOUND in {image_path}:")
            for tag, digests in sorted(duplicates.items()):
                print(f"  Tag '{tag}' appears in {len(digests)} different images:")
                for digest in digests:
                    print(f"    - {digest}")
            issues_found = True
        else:
            digest_count = len(list(vars_dir.glob("*.yml")))
            print(f"OK {image_path} ({digest_count} digests) - No duplicate tags")

    if issues_found:
        print("\nIssues found! Please review the duplicate tags above.")
        return 1

    print("\nAll image paths checked - No duplicate tags found!")
    return 0


if __name__ == "__main__":
    sys.exit(main())
