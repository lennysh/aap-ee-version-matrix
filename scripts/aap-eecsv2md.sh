#!/bin/bash
# A script to convert CSV data to Markdown tables.

# Exit immediately if a command exits with a non-zero status.
set -e

# Get the directory of the script
script_dir=$(dirname "$(readlink -f "$0")")

# Get the parent directory of the script directory
parent_dir=$(dirname "$script_dir")

# Define the image paths you want to query.
IMAGE_PATHS=(
  "registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel9"
  "registry.redhat.io/ansible-automation-platform-25/ee-supported-rhel9"
  "registry.redhat.io/ansible-automation-platform-24/ee-minimal-rhel9"
  "registry.redhat.io/ansible-automation-platform-24/ee-supported-rhel9"
  "registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel8"
  "registry.redhat.io/ansible-automation-platform-25/ee-supported-rhel8"
  "registry.redhat.io/ansible-automation-platform-24/ee-minimal-rhel8"
  "registry.redhat.io/ansible-automation-platform-24/ee-supported-rhel8"
  "registry.redhat.io/ansible-automation-platform/ee-minimal-rhel9"
  "registry.redhat.io/ansible-automation-platform/ee-minimal-rhel8"
)

for path in "${IMAGE_PATHS[@]}"; do
  mkdir -p "${parent_dir}/${path}"
  echo "Processing image path: ${path}"
  ${script_dir}/csv2md.sh \
  -t "${path}" \
  -F "image_path=${path}" \
  -R "digest" \
  ${parent_dir}/data/AAP_EE.csv > ${parent_dir}/${path}/README.md
done
echo "Markdown tables generated successfully."