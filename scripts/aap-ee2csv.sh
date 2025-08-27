#!/bin/bash
# A multi-function script to discover, inspect, and catalog
# Ansible Automation Platform Execution Environments based on image digests.

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

# Helper function to convert CSV to a clean Tab-Separated (TSV) stream.
_csv_to_tsv() {
    local file_to_parse="$1"
    [ ! -s "${file_to_parse}" ] && return
    python3 -c '
import sys, csv
reader = csv.reader(sys.stdin)
writer = csv.writer(sys.stdout, delimiter="\t", lineterminator="\n", quoting=csv.QUOTE_MINIMAL)
for row in reader:
    writer.writerow(row)
' < "${file_to_parse}"
}

# Helper function to check for the correct CSV header.
_check_csv_header() {
    local CSV_FILE="$1"
    if [ -f "${CSV_FILE}" ] && ! head -n 1 "${CSV_FILE}" 2>/dev/null | grep -q ",digest,"; then
        echo "❌ Error: CSV file '${CSV_FILE}' has an old format (missing 'digest' column)." >&2
        echo "   Please delete or rename the old file and run the 'discover' command first." >&2
        exit 1
    fi
}

# Function 1: Discover new images by digest and add them to the CSV.
# This function now ALSO captures the creation date.
discover_new_tags() {
    local CSV_FILE="$1"
    echo "---"
    echo "▶️  Starting Task: Discover New Images by Digest (and Creation Date)"
    echo "---"

    if [ ! -f "${CSV_FILE}" ]; then
        echo "image_path,tags,digest,ansible_core_version,python_version,rhel_version,ansible_collections,packages,pip_packages,created" > "${CSV_FILE}"
        echo "📝 Created new CSV file: ${CSV_FILE}"
    else
        _check_csv_header "$CSV_FILE"
    fi

    declare -A existing_digests
    echo "🧠 Loading existing image digests from ${CSV_FILE}..."
    while IFS=$'\t' read -r path _ digest _; do
        if [[ -n "$digest" ]]; then
            existing_digests["${path},${digest}"]=1
        fi
    done < <(_csv_to_tsv "${CSV_FILE}" | tail -n +2)
    echo "  ↳ Done. Found ${#existing_digests[@]} existing unique images."

    declare -A remote_images_by_digest
    declare -A digest_to_created_date
    echo "🔎 Fetching tags, digests, and dates from registries (this may take a while)..."
    for path in "${IMAGE_PATHS[@]}"; do
        echo "---"
        echo "   Querying path: ${path}"
        while read -r tag; do
            local exclude_this_tag=false
            for pattern in "${EXCLUDE_PATTERNS[@]}"; do
                if [[ "$tag" == *"$pattern"* ]]; then
                    exclude_this_tag=true
                    break
                fi
            done
            if ! $exclude_this_tag; then
                local inspect_json
                inspect_json=$(timeout 30s skopeo inspect "docker://${path}:${tag}" 2>/dev/null || echo "{}")
                
                local output
                output=$(echo "$inspect_json" | jq -r '[.Digest, .Created] | @tsv')
                local digest created_date
                IFS=$'\t' read -r digest created_date <<< "$output"

                if [[ -n "$digest" && "$digest" != "null" ]]; then
                    echo "     ↳ Found tag: '${tag}' -> Digest: ${digest:7:12}..."
                    remote_images_by_digest["${path},${digest}"]+="${tag},"
                    if [[ -z "${digest_to_created_date["${path},${digest}"]}" ]]; then
                       digest_to_created_date["${path},${digest}"]="$created_date"
                    fi
                else
                    echo "     ↳ ⚠️ Could not get digest for tag: '${tag}'. Skipping." >&2
                fi
            fi
        done < <(podman search --limit 1000 --list-tags "${path}" | tail -n +2 | awk '{print $2}')
    done

    local total_new_images_added=0
    echo "---"
    echo "🔄 Comparing remote images with local CSV..."
    for key in "${!remote_images_by_digest[@]}"; do
        if [[ -z "${existing_digests[$key]}" ]]; then
            local path="${key%,*}"
            local digest="${key##*,}"
            local tags=${remote_images_by_digest[$key]%,}
            local created=${digest_to_created_date[$key]}
            echo "  ↳ ✨ Found new image digest: ${digest:7:12}... with tags: ${tags}. Adding to ${CSV_FILE}."
            echo "${path},\"${tags}\",${digest},,,,,,,${created}" >> "${CSV_FILE}"
            total_new_images_added=$((total_new_images_added + 1))
        fi
    done
    echo "---"
    echo "✅ Discovery complete. Added ${total_new_images_added} new unique images to ${CSV_FILE}."
}

# Function 1.5: Sync images by digest (discover new, update tags, and prune stale).
# This function now ALSO captures the creation date.
discover_and_prune() {
    local CSV_FILE="$1"
    echo "---"
    echo "▶️  Starting Task: Sync Images by Digest (Discover & Prune)"
    echo "---"

    if [ ! -f "${CSV_FILE}" ]; then
        discover_new_tags "$CSV_FILE"
        return
    fi
    _check_csv_header "$CSV_FILE"

    declare -A remote_images_by_digest
    declare -A digest_to_created_date
    echo "🔎 Fetching all current tags, digests, and dates from registries (this may take a while)..."
    for path in "${IMAGE_PATHS[@]}"; do
        echo "   Querying path: ${path}"
        while read -r tag; do
            local exclude_this_tag=false
            for pattern in "${EXCLUDE_PATTERNS[@]}"; do
                if [[ "$tag" == *"$pattern"* ]]; then
                    exclude_this_tag=true
                    break
                fi
            done
            if ! $exclude_this_tag; then
                local inspect_json
                inspect_json=$(timeout 30s skopeo inspect "docker://${path}:${tag}" 2>/dev/null || echo "{}")
                
                local output
                output=$(echo "$inspect_json" | jq -r '[.Digest, .Created] | @tsv')
                local digest created_date
                IFS=$'\t' read -r digest created_date <<< "$output"

                if [[ -n "$digest" && "$digest" != "null" ]]; then
                    remote_images_by_digest["${path},${digest}"]+="${tag},"
                     if [[ -z "${digest_to_created_date["${path},${digest}"]}" ]]; then
                       digest_to_created_date["${path},${digest}"]="$created_date"
                    fi
                fi
            fi
        done < <(podman search --limit 1000 --list-tags "${path}" | tail -n +2 | awk '{print $2}')
    done
    echo "  ↳ Found ${#remote_images_by_digest[@]} total unique remote images."

    local TEMP_FILE
    TEMP_FILE=$(mktemp)
    head -n 1 "${CSV_FILE}" > "${TEMP_FILE}"
    local pruned_count=0 kept_count=0 updated_count=0

    _csv_to_tsv "${CSV_FILE}" | tail -n +2 | while IFS=$'\t' read -r path tags digest ansible_core python rhel collections packages pip created; do
        local key="${path},${digest}"
        if [[ -n "${remote_images_by_digest[$key]}" ]]; then
            local remote_tags_csv=${remote_images_by_digest[$key]%,}
            local sorted_remote=$(echo "$remote_tags_csv" | tr ',' '\n' | sort | paste -sd ',' -)
            local sorted_local=$(echo "$tags" | tr ',' '\n' | sort | paste -sd ',' -)
            if [[ "$sorted_local" != "$sorted_remote" ]]; then
                echo "  ↳ 🔄 Updating tags for digest ${digest:7:12}..."
                tags=$remote_tags_csv
                updated_count=$((updated_count + 1))
            fi
            printf "%s,\"%s\",%s,%s,%s,\"%s\",\"%s\",\"%s\",\"%s\",%s\n" "$path" "$tags" "$digest" "$ansible_core" "$python" "$rhel" "$collections" "$packages" "$pip" "$created" >> "${TEMP_FILE}"
            unset remote_images_by_digest[$key]
            kept_count=$((kept_count + 1))
        else
            echo "  ↳ 🗑️ Pruning stale image: digest ${digest:7:12}..."
            pruned_count=$((pruned_count + 1))
        fi
    done

    echo "---"
    echo "📊 Sync Summary:"
    echo "  ↳ Kept ${kept_count} existing images."
    echo "  ↳ Updated ${updated_count} images with new tags."
    echo "  ↳ Pruned ${pruned_count} stale images."

    local added_count=0
    for key in "${!remote_images_by_digest[@]}"; do
        local path="${key%,*}"
        local digest="${key##*,}"
        local tags=${remote_images_by_digest[$key]%,}
        local created=${digest_to_created_date[$key]}
        echo "  ↳ ✨ Found new image: digest ${digest:7:12}... (tags: ${tags}). Adding to file."
        echo "${path},\"${tags}\",${digest},,,,,,,${created}" >> "${TEMP_FILE}"
        added_count=$((added_count + 1))
    done
    echo "  ↳ Added ${added_count} new images."

    mv "${TEMP_FILE}" "${CSV_FILE}"
    echo "---"
    echo "✅ Sync (discover and prune) complete."
}

# Function 2: Get all image details (versions, collections, packages).
get_image_details() {
    local CSV_FILE="$1"
    _check_csv_header "$CSV_FILE"
    echo "---"
    echo "▶️  Starting Task: Get Image Details"
    echo "---"

    local TEMP_FILE
    TEMP_FILE=$(mktemp)
    head -n 1 "${CSV_FILE}" > "${TEMP_FILE}"

    _csv_to_tsv "${CSV_FILE}" | tail -n +2 | awk -F'\t' -v tmp_file="${TEMP_FILE}" \
      -v rhel_trim_str="${RHEL_TRIM_STRINGS[*]}" '
    BEGIN {
        split(rhel_trim_str, rhel_trim_arr, " ")
    }
    {
        image_path = $1; tags = $2; digest = $3; ansible_version = $4; python_version = $5
        rhel_version = $6; ansible_collections = $7; packages = $8; pip_packages = $9; created = $10

        if ((ansible_version == "" || python_version == "" || rhel_version == "" || ansible_collections == "" || packages == "" || pip_packages == "") && digest != "") {
            full_image = image_path "@" digest
            print "---" > "/dev/stderr"
            print "🔄 Processing details for: " full_image > "/dev/stderr"

            if (system("podman pull " full_image " > /dev/null 2>&1") != 0) {
                print "  ↳ ❌ ERROR: Failed to pull " full_image ". Skipping." > "/dev/stderr"
                if(ansible_version == "") {ansible_version = "pull_failed"}
                if(python_version == "") {python_version = "pull_failed"}
                if(rhel_version == "") {rhel_version = "pull_failed"}
                if(ansible_collections == "") {ansible_collections = "pull_failed"}
                if(packages == "") {packages = "pull_failed"}
                if(pip_packages == "") {pip_packages = "pull_failed"}
                printf("%s,\"%s\",%s,%s,%s,\"%s\",\"%s\",\"%s\",\"%s\",%s\n", image_path, tags, digest, ansible_version, python_version, rhel_version, ansible_collections, packages, pip_packages, created) >> tmp_file
                next
            }

            if (ansible_version == "" || python_version == "") {
                print "  ↳ Getting Ansible Core and Python versions..." > "/dev/stderr"
                cmd = "podman run --rm " full_image " ansible --version 2>/dev/null"
                new_ansible_version = "n/a"; new_python_version = "n/a"
                while ((cmd | getline line) > 0) {
                    if (line ~ /core/) { sub(/.*core /, "", line); sub(/].*/, "", line); new_ansible_version=line }
                    if (line ~ /python version/) { sub(/.*python version = /, "", line); sub(/ .*/, "", line); new_python_version=line }
                }
                close(cmd)
                if (ansible_version == "") { ansible_version = new_ansible_version }
                if (python_version == "") { python_version = new_python_version }
            }

            if (rhel_version == "") {
                print "  ↳ Getting RHEL version..." > "/dev/stderr"
                cmd = "podman run --rm " full_image " cat /etc/redhat-release 2>/dev/null"
                new_rhel_version = "n/a"
                if ((cmd | getline line) > 0) { new_rhel_version = line }
                close(cmd)
                for (i in rhel_trim_arr) { gsub(rhel_trim_arr[i], "", new_rhel_version) }
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", new_rhel_version)
                rhel_version = new_rhel_version
            }

            if (ansible_collections == "") {
                print "  ↳ Getting Ansible collections..." > "/dev/stderr"
                cmd = "podman run --rm " full_image " ansible-galaxy collection list 2>/dev/null"
                collections_str = ""
                while ((cmd | getline line) > 0) {
                    if (line ~ /\./ && line !~ /^#/) {
                        split(line, parts, /[[:space:]]+/); collections_str = (collections_str == "" ? "" : collections_str ", ") parts[1] " " parts[2]
                    }
                }
                exit_code = close(cmd)
                ansible_collections = (exit_code != 0 || collections_str == "" ? "No collections found" : collections_str)
            }

            if (packages == "") {
                print "  ↳ Getting system packages (RPM)..." > "/dev/stderr"
                cmd = "podman run --rm " full_image " sh -c \"rpm -qa --qf \047%{NAME} %{VERSION}-%{RELEASE}\\n\047 | sort\" 2>/dev/null"
                rpm_str = ""
                while ((cmd | getline line) > 0) { rpm_str = (rpm_str == "" ? "" : rpm_str ", ") line }
                exit_code = close(cmd)
                packages = (exit_code != 0 || rpm_str == "" ? "Not found" : rpm_str)
            }
            
            if (pip_packages == "") {
                print "  ↳ Getting Python packages (Pip)..." > "/dev/stderr"
                cmd = "podman run --rm " full_image " pip freeze 2>/dev/null"
                pip_str = ""
                while ((cmd | getline line) > 0) { pip_str = (pip_str == "" ? "" : pip_str ", ") line }
                exit_code = close(cmd)
                pip_packages = (exit_code != 0 || pip_str == "" ? "Not found" : pip_str)
            }

            system("podman rmi " full_image " > /dev/null 2>&1")
            print "✅ Successfully processed details for " full_image > "/dev/stderr"
        }
        
        gsub(/"/, "", rhel_version); gsub(/"/, "", ansible_collections)
        gsub(/"/, "", packages); gsub(/"/, "", pip_packages)
        
        printf("%s,\"%s\",%s,%s,%s,\"%s\",\"%s\",\"%s\",\"%s\",%s\n", image_path, tags, digest, ansible_version, python_version, rhel_version, ansible_collections, packages, pip_packages, created) >> tmp_file
    }
    '

    mv "${TEMP_FILE}" "${CSV_FILE}"
    echo "---"
    echo "✅ Image details collection complete."
}

# Function 3: Sort the CSV by image_path and then tags.
sort_csv() {
    local CSV_FILE="$1"
    echo "---"
    echo "▶️  Starting Task: Sort CSV File"
    echo "---"
    _check_csv_header "$CSV_FILE"

    local TEMP_FILE
    TEMP_FILE=$(mktemp)
    head -n 1 "${CSV_FILE}" > "${TEMP_FILE}"
    tail -n +2 "${CSV_FILE}" | sort -t, -k1,1 -k2,2 >> "${TEMP_FILE}"
    mv "${TEMP_FILE}" "${CSV_FILE}"

    echo "✅ CSV file sorted successfully."
}

# Function to display help message.
show_help() {
    echo "Usage: $0 <command> <csv_file>"
    echo
    echo "Commands:"
    echo "  discover         Find and ADD new unique images (by digest) and their creation dates."
    echo "  discover-prune   SYNC images; adds new ones, updates tags, and REMOVES stale ones."
    echo "  details          Fill in missing versions, collections, and packages for images."
    echo "  sort             Sort the CSV by image path and then by tags."
    echo "  all              Run tasks in sequence: discover, details, sort."
    echo "  all-prune        Run tasks in sequence: discover-prune, details, sort."
    echo "  help             Show this help message."
    echo
    echo "Note: This script now uses a new CSV format. If you have an old CSV, please delete it first."
}

## --- Main Logic ---

# Check for dependencies first.
for cmd in python3 podman skopeo jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Dependency '$cmd' is not installed. Please install it." >&2
        exit 1
    fi
done

if [ "$#" -lt 2 ]; then
    show_help
    exit 1
fi

COMMAND="$1"
CSV_FILE="$2"

case "$COMMAND" in
    discover)
        discover_new_tags "$CSV_FILE"
        ;;
    discover-prune)
        discover_and_prune "$CSV_FILE"
        ;;
    details)
        get_image_details "$CSV_FILE"
        ;;
    sort)
        sort_csv "$CSV_FILE"
        ;;
    all)
        discover_new_tags "$CSV_FILE"
        get_image_details "$CSV_FILE"
        sort_csv "$CSV_FILE"
        ;;
    all-prune)
        discover_and_prune "$CSV_FILE"
        get_image_details "$CSV_FILE"
        sort_csv "$CSV_FILE"
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