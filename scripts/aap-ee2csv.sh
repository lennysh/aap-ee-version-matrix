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

# Function 1: Discover new tags and add them to the CSV.
discover_new_tags() {
    local CSV_FILE="$1"
    echo "---"
    echo "▶️  Starting Task: Discover New Tags"
    echo "---"

    if [ ! -f "${CSV_FILE}" ]; then
        echo "image_path,tag,ansible_core_version,python_version,rhel_version,ansible_collections,packages,pip_packages,created" > "${CSV_FILE}"
        echo "📝 Created new CSV file: ${CSV_FILE}"
    fi

    declare -A existing_entries
    echo "🧠 Loading existing entries from ${CSV_FILE} into memory..."
    while IFS=$'\t' read -r path tag _; do
        existing_entries["${path},${tag}"]=1
    done < <(_csv_to_tsv "${CSV_FILE}" | tail -n +2) # Skip header
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
                    echo "${path},${tag},,,,,,," >> "${CSV_FILE}"
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

# Function 1.5: Discover new tags AND prune stale tags from the CSV.
discover_and_prune() {
    local CSV_FILE="$1"
    echo "---"
    echo "▶️  Starting Task: Discover New Tags and Prune Stale Entries"
    echo "---"

    if [ ! -f "${CSV_FILE}" ]; then
        discover_new_tags "$CSV_FILE"
        return
    fi

    declare -A remote_tags
    echo "🔎 Fetching all current tags from registries..."
    for path in "${IMAGE_PATHS[@]}"; do
        while read -r tag; do
            local exclude_this_tag=false
            for pattern in "${EXCLUDE_PATTERNS[@]}"; do
                if [[ "$tag" == *"$pattern"* ]]; then
                    exclude_this_tag=true
                    break
                fi
            done
            if ! $exclude_this_tag; then
                remote_tags["${path},${tag}"]=1
            fi
        done < <(podman search --limit 1000 --list-tags "${path}" | tail -n +2 | awk '{print $2}')
    done
    echo "  ↳ Found ${#remote_tags[@]} total valid remote tags."

    local TEMP_FILE
    TEMP_FILE=$(mktemp)
    head -n 1 "${CSV_FILE}" > "${TEMP_FILE}"

    local pruned_count=0
    local kept_count=0

    while IFS= read -r line; do
        IFS=, read -r path tag _ <<< "$line"
        local key="${path},${tag}"

        if [[ -n "${remote_tags[$key]}" ]]; then
            echo "$line" >> "${TEMP_FILE}"
            unset remote_tags[$key]
            kept_count=$((kept_count + 1))
        else
            echo "  ↳ Pruning stale tag: ${tag}"
            pruned_count=$((pruned_count + 1))
        fi
    done < <(tail -n +2 "${CSV_FILE}")

    echo "  ↳ Kept ${kept_count} existing tags."
    echo "  ↳ Pruned ${pruned_count} stale tags."

    local added_count=0
    for key in "${!remote_tags[@]}"; do
        local path="${key%,*}"
        local tag="${key##*,}"
        echo "  ↳ Found new tag: ${tag}. Adding to file."
        echo "${path},${tag},,,,,,,," >> "${TEMP_FILE}"
        added_count=$((added_count + 1))
    done
    echo "  ↳ Added ${added_count} new tags."

    mv "${TEMP_FILE}" "${CSV_FILE}"

    echo "---"
    echo "✅ Discovery and prune complete."
}

# Function 2: Get all image details (versions, collections, packages).
get_image_details() {
    local CSV_FILE="$1"
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
        image_path = $1; tag = $2; ansible_version = $3; python_version = $4
        rhel_version = $5; ansible_collections = $6; packages = $7; pip_packages = $8; created = $9

        if (ansible_version == "" || python_version == "" || rhel_version == "" || ansible_collections == "" || packages == "" || pip_packages == "") {
            full_image = image_path ":" tag
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
                printf("%s,%s,%s,%s,\"%s\",\"%s\",\"%s\",\"%s\",%s\n", image_path, tag, ansible_version, python_version, rhel_version, ansible_collections, packages, pip_packages, created) >> tmp_file
                next
            }

            # Fetch Ansible/Python versions only if needed
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

            # Fetch RHEL version only if needed
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

            # Fetch collections only if needed
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

            # Fetch RPM packages only if needed
            if (packages == "") {
                print "  ↳ Getting system packages (RPM)..." > "/dev/stderr"
                cmd = "podman run --rm " full_image " sh -c \"rpm -qa --qf \047%{NAME} %{VERSION}-%{RELEASE}\\n\047 | sort\" 2>/dev/null"
                rpm_str = ""
                while ((cmd | getline line) > 0) { rpm_str = (rpm_str == "" ? "" : rpm_str ", ") line }
                exit_code = close(cmd)
                packages = (exit_code != 0 || rpm_str == "" ? "Not found" : rpm_str)
            }
            
            # Fetch Pip packages only if needed
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
        
        printf("%s,%s,%s,%s,\"%s\",\"%s\",\"%s\",\"%s\",%s\n", image_path, tag, ansible_version, python_version, rhel_version, ansible_collections, packages, pip_packages, created) >> tmp_file
    }
    '

    mv "${TEMP_FILE}" "${CSV_FILE}"
    echo "---"
    echo "✅ Image details collection complete."
}

# Function 3: Get dates.
get_creation_dates() {
    local CSV_FILE="$1"
    echo "---"
    echo "▶️  Starting Task: Get Creation Dates"
    echo "---"

    local TEMP_FILE
    TEMP_FILE=$(mktemp)
    head -n 1 "${CSV_FILE}" > "${TEMP_FILE}"

    _csv_to_tsv "${CSV_FILE}" | tail -n +2 | awk -F'\t' -v tmp_file="${TEMP_FILE}" '
    {
        image_path = $1; tag = $2; ansible_version = $3; python_version = $4
        rhel_version = $5; ansible_collections = $6; packages = $7; pip_packages = $8; created = $9

        if (created == "" || created == "inspect_failed") {
            print "---" > "/dev/stderr"
            print "🔄 Processing date for: " image_path ":" tag > "/dev/stderr"

            cmd = "skopeo inspect docker://" image_path ":" tag " 2>/dev/null | jq -r \".Created\""
            created_date = "inspect_failed"
            if ((cmd | getline line) > 0 && line != "null" && line != "") {
                created_date = line
            }
            close(cmd)
            created = created_date
            print "  ↳ Found date: " created > "/dev/stderr"
        }

        gsub(/"/, "", rhel_version); gsub(/"/, "", ansible_collections)
        gsub(/"/, "", packages); gsub(/"/, "", pip_packages)
        
        printf("%s,%s,%s,%s,\"%s\",\"%s\",\"%s\",\"%s\",%s\n", image_path, tag, ansible_version, python_version, rhel_version, ansible_collections, packages, pip_packages, created) >> tmp_file
    }
    '

    mv "${TEMP_FILE}" "${CSV_FILE}"
    echo "---"
    echo "✅ Creation date collection complete."
}

# Function 4: Sort the CSV by image_path and then tag.
sort_csv() {
    local CSV_FILE="$1"
    echo "---"
    echo "▶️  Starting Task: Sort CSV File"
    echo "---"

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
    echo "  discover         Find and ADD new image tags to the CSV."
    echo "  discover-prune   SYNC tags; adds new ones and REMOVES stale ones from the CSV."
    echo "  details          Fill in missing versions, collections, and packages for images."
    echo "  dates            Fill in missing image creation dates using skopeo."
    echo "  sort             Sort the CSV by image path and then by tag."
    echo "  all              Run tasks in sequence: discover, details, dates, sort."
    echo "  all-prune        Run tasks in sequence: discover-prune, details, dates, sort."
    echo "  help             Show this help message."
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
    dates)
        get_creation_dates "$CSV_FILE"
        ;;
    sort)
        sort_csv "$CSV_FILE"
        ;;
    all)
        discover_new_tags "$CSV_FILE"
        get_image_details "$CSV_FILE"
        get_creation_dates "$CSV_FILE"
        sort_csv "$CSV_FILE"
        ;;
    all-prune)
        discover_and_prune "$CSV_FILE"
        get_image_details "$CSV_FILE"
        get_creation_dates "$CSV_FILE"
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