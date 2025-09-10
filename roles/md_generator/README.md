Markdown Generator
=========

Generates a markdown file from a template for each container image.

Role Variables
--------------

```yaml
# Defaults shown below

# The root path where the image VAR files are located
md_generator_var_root_path: "{{ playbook_dir }}/images"

# Default path for the generated output markdown file
md_generator_output_md_file: "output/image_report.md"
```

License
-------

MIT

Author Information
------------------

Lenny Shirley
