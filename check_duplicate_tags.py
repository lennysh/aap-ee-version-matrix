#!/usr/bin/env python3
"""
Check for duplicate tags in vars.yml files.
This script examines each vars.yml file and reports if any tag value
appears more than once across different image entries.
"""

import yaml
import sys
from pathlib import Path
from collections import defaultdict

def check_duplicate_tags(file_path):
    """Check for duplicate tags in a vars.yml file."""
    try:
        with open(file_path, 'r') as f:
            data = yaml.safe_load(f)
        
        if not data or 'images' not in data:
            return None, "No images found"
        
        # Collect all tags with their image digests
        tag_to_images = defaultdict(list)
        
        for image in data.get('images', []):
            if 'tags' not in image or not image['tags']:
                continue
            
            digest = image.get('digest', 'unknown')
            for tag in image['tags']:
                # Normalize tag to string for comparison
                tag_str = str(tag)
                tag_to_images[tag_str].append(digest)
        
        # Find duplicates
        duplicates = {}
        for tag, digests in tag_to_images.items():
            if len(digests) > 1:
                # Check if it's actually a duplicate (same tag on different images)
                unique_digests = set(digests)
                if len(unique_digests) > 1:
                    duplicates[tag] = list(unique_digests)
        
        return duplicates, None
    except Exception as e:
        return None, str(e)

def main():
    """Main function to check all vars.yml files."""
    images_dir = Path('images')
    vars_files = list(images_dir.rglob('vars.yml'))
    
    if not vars_files:
        print("No vars.yml files found in images/ directory")
        return 1
    
    issues_found = False
    
    for vars_file in sorted(vars_files):
        duplicates, error = check_duplicate_tags(vars_file)
        
        if error:
            print(f"ERROR in {vars_file}: {error}")
            issues_found = True
            continue
        
        if duplicates:
            print(f"\n❌ DUPLICATE TAGS FOUND in {vars_file}:")
            for tag, digests in sorted(duplicates.items()):
                print(f"  Tag '{tag}' appears in {len(digests)} different images:")
                for digest in digests:
                    print(f"    - {digest}")
            issues_found = True
        else:
            print(f"✓ {vars_file} - No duplicate tags")
    
    if issues_found:
        print("\n⚠️  Issues found! Please review the duplicate tags above.")
        return 1
    else:
        print("\n✅ All files checked - No duplicate tags found!")
        return 0

if __name__ == '__main__':
    sys.exit(main())

