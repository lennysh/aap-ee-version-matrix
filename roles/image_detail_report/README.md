Image Detail Report
=========

Discovers, inspects, and reports on container images entirely in memory. Writes
detailed local markdown files under `output/<image_path>/<digest-hex>.md`. Does
**not** read or write `image_inspector` per-digest vars files and does not affect
`md_generator` output.

When multiple tags share a digest, re-inspecting any of those tags updates the
same file.

Usage
-----

From the repository root:

```bash
# All tags for an image repository path
ansible-playbook playbooks/inspect_single_image.yml \
  -e image_path=registry.redhat.io/ansible-automation-platform/ee-minimal-rhel8

# Single tag only
ansible-playbook playbooks/inspect_single_image.yml \
  -e image_path=registry.redhat.io/ansible-automation-platform/ee-minimal-rhel8 \
  -e image_tag=2.12.10
```

Role Variables
--------------

```yaml
# Required — set via -e image_path=... (mapped to image_detail_report_image_path)
image_detail_report_image_path: "{{ image_path }}"

# Root of the repository (playbooks live in playbooks/)
image_detail_report_repo_root: "{{ playbook_dir | dirname }}"

# A list of string patterns to exclude from tag discovery results
image_detail_report_exclude_patterns:
  - "-source"
  - "sha256"

# When non-empty, only discover and inspect images matching these tags (exact match).
# playbooks/inspect_single_image.yml sets this from -e image_tag=...
image_detail_report_include_tags: []

# Fallback Python version used to locate Ansible collections when not detected
image_detail_report_default_python_version: "3.12"

# Base directory for generated reports (files written under <dir>/<image_path>/<digest-hex>.md)
image_detail_report_output_dir: "{{ image_detail_report_repo_root }}/output"
```

License
-------

MIT

Author Information
------------------

Lenny Shirley
