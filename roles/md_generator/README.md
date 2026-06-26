Markdown Generator
=========

Reads per-digest Ansible vars files produced by `image_inspector` and renders a
`README.md` version matrix for each image path under `images/<image_path>/README.md`.

Playbook
--------

```bash
ansible-playbook md_generator.yml
```

Run this after `image_inspector` has written or updated vars files. Re-run whenever
vars change to refresh the published markdown tables.

Input / output
--------------

| | Path |
|---|------|
| **Reads** | `images/<image_path>/vars/*.yml` |
| **Writes** | `images/<image_path>/README.md` |

Each digest file is loaded and aggregated into an `images` list for the Jinja template.
The template groups rows by Ansible Core major.minor and lists tags, versions, and
collapsible package/collection details.

Role Variables
--------------

```yaml
# Root directory containing image paths and their vars/ subdirectories
md_generator_var_root_path: "{{ playbook_dir }}/images"

# Ensures this path's parent directory exists before generation
md_generator_output_md_file: "output/image_report.md"
```

Note: per-image `README.md` files are written under `md_generator_var_root_path`, not
under `output/`. The `md_generator_output_md_file` default only controls creation of
the legacy `output/` directory.

License
-------

MIT

Author Information
------------------

Lenny Shirley
