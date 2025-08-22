#!/bin/bash
# A multi-function script to discover, inspect, and catalog
# Ansible Automation Platform Execution Environments.

# Exit immediately if a command exits with a non-zero status.
set -e

## --- Configuration ---

# Add the base paths of the container images you want to query.
IMAGE_PATHS=(
  "registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel9"
  "registry.redhat.io/ansible-automation-platform-25/ee-supported-rhel9"
  "registry.redhat.io/ansible-automation-platform-24/ee-minimal-rhel9"
  "registry.redhat.io/ansible-automation-platform-24/ee-supported-rhel9"
  "registry.redhat.io/ansible-automation-platform/ee-minimal-rhel9"
  "registry.redhat.io/ansible-automation-platform/ee-minimal-rhel8"
)

# Add string patterns to EXCLUDE from tag discovery results.
EXCLUDE_PATTERNS=(
  "-source"
  "sha256"
)

# Add strings to REMOVE from the RHEL version output for cleanup.
RHEL_TRIM_STRINGS=(
  "Red Hat Enterprise Linux release"
  "Red Hat Enterprise Linux Server release"
)

## --- Functions ---

# Function 1: Discover new tags and add them to the CSV.
discover_new_tags() {
    local CSV_FILE="$1"
    echo "---"
    echo "▶️  Starting Task: Discover New Tags"
    echo "---"

    if [ ! -f "${CSV_FILE}" ]; then
        echo "image_path,tag,ansible_core_version,python_version,rhel_version,created" > "${CSV_FILE}"
        echo "📝 Created new CSV file: ${CSV_FILE}"
    fi

    declare -A existing_entries
    echo "🧠 Loading existing entries from ${CSV_FILE} into memory..."
    while IFS=, read -r path tag _; do
        existing_entries["${path},${tag}"]=1
    done < <(tail -n +2 "${CSV_FILE}")
    echo "  ↳ Done. Found ${#existing_entries[@]} existing entries."

    local total_new_tags_added=0
    for path in "${IMAGE_PATHS[@]}"; do
        echo "---"
        echo "🔎 Finding tags for: ${path}"
        local new_tags_found=0
        while read -r tag; do
            local exclude_this_tag=false
            for pattern in "${EXCLUDE_PATTERNS[@]}"; do
                if [[ "$tag" == *"$pattern"* ]]; then
                    exclude_this_tag=true
                    break
                fi
            done
            if ! $exclude_this_tag; then
                local check_key="${path},${tag}"
                if [[ -z "${existing_entries["${check_key}"]}" ]]; then
                    echo "  ↳ Found new tag: ${tag}. Adding to ${CSV_FILE}."
                    echo "${path},${tag},,,," >> "${CSV_FILE}" # Ensure 5 commas for 6 columns
                    new_tags_found=$((new_tags_found + 1))
                fi
            fi
        done < <(podman search --limit 1000 --list-tags "${path}" | tail -n +2 | awk '{print $2}')
        echo "  ↳ Added ${new_tags_found} new tags for this path."
        total_new_tags_added=$((total_new_tags_added + new_tags_found))
    done

    echo "---"
    echo "✅ Discovery complete. Added a total of ${total_new_tags_added} new tags to ${CSV_FILE}."
}

# Function 2: Get Ansible, Python, and RHEL versions for empty rows.
get_image_versions() {
    local CSV_FILE="$1"
    echo "---"
    echo "▶️  Starting Task: Get Image Versions"
    echo "---"

    local TEMP_FILE
    TEMP_FILE=$(mktemp)
    head -n 1 "${CSV_FILE}" > "${TEMP_FILE}"

    while IFS=, read -r image_path tag ansible_version python_version rhel_version created; do
        if [[ -z "$ansible_version" || -z "$python_version" || -z "$rhel_version" ]]; then
            local full_image="${image_path}:${tag}"
            echo "---"
            echo "🔄 Processing versions for: ${full_image}"
            echo "  ↳ 1. Pulling image..."
            if ! podman pull "${full_image}" > /dev/null 2>&1; then
                echo "  ↳ ❌ ERROR: Failed to pull ${full_image}. Skipping."
                echo "${image_path},${tag},pull_failed,pull_failed,pull_failed,${created}" >> "${TEMP_FILE}"
                continue
            fi

            echo "  ↳ 2. Running commands..."
            local COMMAND_OUTPUT
            COMMAND_OUTPUT=$(podman run --rm "${full_image}" sh -c "ansible --version && cat /etc/redhat-release") || COMMAND_OUTPUT="Error executing command"

            echo "  ↳ 3. Extracting versions..."
            local NEW_ANSIBLE_VERSION
            NEW_ANSIBLE_VERSION=$(echo "${COMMAND_OUTPUT}" | grep 'core' | sed 's/.*core //; s/].*//' || echo "n/a")
            local NEW_PYTHON_VERSION
            NEW_PYTHON_VERSION=$(echo "${COMMAND_OUTPUT}" | grep 'python version' | awk '{print $4}' || echo "n/a")
            local NEW_RHEL_VERSION
            NEW_RHEL_VERSION=$(echo "${COMMAND_OUTPUT}" | grep 'Red Hat Enterprise Linux' || echo "n/a")
            for pattern in "${RHEL_TRIM_STRINGS[@]}"; do
                NEW_RHEL_VERSION="${NEW_RHEL_VERSION//"$pattern"/}"
            done
            NEW_RHEL_VERSION=$(echo "$NEW_RHEL_VERSION" | xargs)

            echo "  ↳ 4. Writing updated row..."
            echo "${image_path},${tag},${NEW_ANSIBLE_VERSION},${NEW_PYTHON_VERSION},${NEW_RHEL_VERSION},${created}" >> "${TEMP_FILE}"

            echo "  ↳ 5. Deleting image..."
            podman rmi "${full_image}" > /dev/null 2>&1
            echo "✅ Successfully processed ${full_image}"
        else
            echo "${image_path},${tag},${ansible_version},${python_version},${rhel_version},${created}" >> "${TEMP_FILE}"
        fi
    done < <(tail -n +2 "${CSV_FILE}")

    mv "${TEMP_FILE}" "${CSV_FILE}"
    echo "---"
    echo "✅ Version collection complete."
}

# Function 3: Get image creation dates for empty rows.
get_creation_dates() {
    local CSV_FILE="$1"
    echo "---"
    echo "▶️  Starting Task: Get Creation Dates"
    echo "---"

    local TEMP_FILE
    TEMP_FILE=$(mktemp)
    head -n 1 "${CSV_FILE}" > "${TEMP_FILE}"

    while IFS=, read -r image_path tag ansible_version python_version rhel_version created; do
        if [[ -z "$created" ]]; then
            local full_image_url="docker://${image_path}:${tag}"
            echo "---"
            echo "🔄 Processing date for: ${image_path}:${tag}"
            local created_date=""

            echo "  ↳ 1. Inspecting with skopeo..."
            local skopeo_output
            if skopeo_output=$(skopeo inspect "${full_image_url}" 2>/dev/null); then
                created_date=$(echo "${skopeo_output}" | jq -r '.Created')
                echo "  ↳ 2. Found date: ${created_date}"
            else
                echo "  ↳ ❌ ERROR: Failed to inspect ${full_image_url}."
                created_date="inspect_failed"
            fi
            echo "${image_path},${tag},${ansible_version},${python_version},${rhel_version},${created_date}" >> "${TEMP_FILE}"
            echo "  ↳ 3. Updated row."
        else
            echo "${image_path},${tag},${ansible_version},${python_version},${rhel_version},${created}" >> "${TEMP_FILE}"
        fi
    done < <(tail -n +2 "${CSV_FILE}")

    mv "${TEMP_FILE}" "${CSV_FILE}"
    echo "---"
    echo "✅ Creation date collection complete."
}

# Function to display help message.
show_help() {
    echo "Usage: $0 <command> <csv_file>"
    echo
    echo "A multi-function script to manage an Execution Environment version matrix."
    echo
    echo "Commands:"
    echo "  discover    Find new image tags from the registry and add them to the CSV."
    echo "  versions    Fill in missing Ansible, Python, and RHEL versions for images in the CSV."
    echo "  dates       Fill in missing image creation dates using skopeo."
    echo "  all         Run all three tasks in sequence: discover, versions, then dates."
    echo "  help        Show this help message."
}

## --- Main Logic ---

# Check for dependencies first.
if ! command -v skopeo &> /dev/null || ! command -v jq &> /dev/null; then
    echo "Error: 'skopeo' and 'jq' are required. Please install them." >&2
    exit 1
fi

# Check for minimum number of arguments.
if [ "$#" -lt 2 ]; then
    show_help
    exit 1
fi

COMMAND="$1"
CSV_FILE="$2"

# Main command dispatcher.
case "$COMMAND" in
    discover)
        discover_new_tags "$CSV_FILE"
        ;;
    versions)
        get_image_versions "$CSV_FILE"
        ;;
    dates)
        get_creation_dates "$CSV_FILE"
        ;;
    all)
        discover_new_tags "$CSV_FILE"
        get_image_versions "$CSV_FILE"
        get_creation_dates "$CSV_FILE"
        ;;
    help)
        show_help
        ;;
    *)
        echo "Error: Unknown command '$COMMAND'" >&2
        show_help
        exit 1
        ;;
esac

echo
echo "🎉 All tasks complete!"