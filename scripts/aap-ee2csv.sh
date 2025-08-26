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
# Awk will consume this stream, as its TSV parser is flawless.
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
        echo "image_path,tag,ansible_core_version,python_version,rhel_version,ansible_collections,created" > "${CSV_FILE}"
        echo "📝 Created new CSV file: ${CSV_FILE}"
    fi

    # Load existing entries into an awk array, avoiding the buggy 'while read' loop.
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
                    echo "${path},${tag},,,,," >> "${CSV_FILE}"
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

# Function 2: Get versions. Re-engineered to run entirely inside AWK.
get_image_versions() {
    local CSV_FILE="$1"
    echo "---"
    echo "▶️  Starting Task: Get Image Versions"
    echo "---"

    local TEMP_FILE
    TEMP_FILE=$(mktemp)
    head -n 1 "${CSV_FILE}" > "${TEMP_FILE}"

    # The entire file processing logic is now inside this single, robust awk command.
    _csv_to_tsv "${CSV_FILE}" | tail -n +2 | awk -F'\t' -v tmp_file="${TEMP_FILE}" \
      -v rhel_trim_count=${#RHEL_TRIM_STRINGS[@]} \
      -v rhel_trim_str="${RHEL_TRIM_STRINGS[*]}" '
    BEGIN {
        # Split the Bash array string into an awk array
        split(rhel_trim_str, rhel_trim_arr, " ")
    }
    {
        image_path = $1; tag = $2; ansible_version = $3; python_version = $4
        rhel_version = $5; ansible_collections = $6; created = $7

        if (ansible_version == "" || python_version == "" || rhel_version == "" || ansible_collections == "") {
            full_image = image_path ":" tag
            print "---" > "/dev/stderr"
            print "🔄 Processing versions for: " full_image > "/dev/stderr"

            # Check if image can be pulled
            if (system("podman pull " full_image " > /dev/null 2>&1") != 0) {
                print "  ↳ ❌ ERROR: Failed to pull " full_image ". Skipping." > "/dev/stderr"
                printf("%s,%s,%s,%s,%s,%s,%s\n", image_path, tag, "pull_failed", "pull_failed", "pull_failed", "pull_failed", created) >> tmp_file
                next
            }

            # Fetch Ansible/Python versions if needed
            if (ansible_version == "" || python_version == "") {
                print "  ↳ Getting Ansible Core and Python versions..." > "/dev/stderr"
                cmd = "podman run --rm " full_image " ansible --version 2>/dev/null"
                if (ansible_version == "") {
                    ansible_version = "n/a" # Default
                    while ((cmd | getline line) > 0) { if (line ~ /core/) { sub(/.*core /, "", line); sub(/].*/, "", line); ansible_version=line; break } }
                    close(cmd)
                }
                cmd = "podman run --rm " full_image " ansible --version 2>/dev/null" # Re-open for python
                if (python_version == "") {
                    python_version = "n/a" # Default
                    while ((cmd | getline line) > 0) {
                        if (line ~ /python version/) {
                            python_version = line
                            sub(/.*python version = /, "", python_version)
                            sub(/ .*/, "", python_version)
                            break
                        }
                    }
                    close(cmd)
                }
            }

            # Fetch RHEL version if needed
            if (rhel_version == "") {
                print "  ↳ Getting RHEL version..." > "/dev/stderr"
                cmd = "podman run --rm " full_image " cat /etc/redhat-release 2>/dev/null"
                rhel_version = "n/a"
                if ((cmd | getline line) > 0) { rhel_version = line }
                close(cmd)
                # Trim strings
                for (i in rhel_trim_arr) { gsub(rhel_trim_arr[i], "", rhel_version) }
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", rhel_version)
            }

            # Fetch collections if needed
            if (ansible_collections == "") {
                print "  ↳ Getting Ansible collections..." > "/dev/stderr"
                cmd = "podman run --rm " full_image " ansible-galaxy collection list 2>/dev/null"
                collections_str = ""
                while ((cmd | getline line) > 0) {
                    if (line ~ /\./ && line !~ /^#/) {
                        split(line, parts, /[[:space:]]+/)
                        collections_str = (collections_str == "" ? "" : collections_str ", ") parts[1] " " parts[2]
                    }
                }
                exit_code = close(cmd)

                if (exit_code != 0 || collections_str == "") {
                    ansible_collections = "No collections found"
                } else {
                    ansible_collections = collections_str
                }
            }

            # Delete image
            system("podman rmi " full_image " > /dev/null 2>&1")
            print "✅ Successfully processed " full_image > "/dev/stderr"

        }
        # Print the final, correct line to the temp file
        gsub(/"/, "", rhel_version); # Sanitize just in case
        gsub(/"/, "", ansible_collections) # Sanitize quotes before adding our own
        printf("%s,%s,%s,%s,\"%s\",%s,%s\n", image_path, tag, ansible_version, python_version, rhel_version, "\"" ansible_collections "\"", created) >> tmp_file
    }
    '

    mv "${TEMP_FILE}" "${CSV_FILE}"
    echo "---"
    echo "✅ Version collection complete."
}

# Function 3: Get dates. Re-engineered to run entirely inside AWK.
get_creation_dates() {
    local CSV_FILE="$1"
    echo "---"
    echo "▶️  Starting Task: Get Creation Dates"
    echo "---"

    local TEMP_FILE
    TEMP_FILE=$(mktemp)
    head -n 1 "${CSV_FILE}" > "${TEMP_FILE}"

    # The entire file processing logic is now inside this single, robust awk command.
    _csv_to_tsv "${CSV_FILE}" | tail -n +2 | awk -F'\t' -v tmp_file="${TEMP_FILE}" '
    {
        # Assign fields for clarity
        image_path = $1; tag = $2; ansible_version = $3; python_version = $4
        rhel_version = $5; ansible_collections = $6; created = $7

        if (created == "" || created == "inspect_failed") {
            print "---" > "/dev/stderr"
            print "🔄 Processing date for: " image_path ":" tag > "/dev/stderr"

            cmd = "skopeo inspect docker://" image_path ":" tag " 2>/dev/null | jq -r \".Created\""
            created_date = "inspect_failed" # Default in case of failure
            if ((cmd | getline line) > 0 && line != "null" && line != "") {
                created_date = line
            }
            close(cmd)
            created = created_date
            print "  ↳ Found date: " created > "/dev/stderr"
        }

        # Sanitize quotes before printing
        gsub(/"/, "", rhel_version)
        gsub(/"/, "", ansible_collections)
        
        # Print the final, correct line to the temp file
        printf("%s,%s,%s,%s,\"%s\",\"%s\",%s\n", image_path, tag, ansible_version, python_version, rhel_version, ansible_collections, created) >> tmp_file
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

    # 1. Write the header row to the new file.
    head -n 1 "${CSV_FILE}" > "${TEMP_FILE}"

    # 2. Sort the rest of the file (tail -n +2 skips the header) and append it.
    #    -t, sets the delimiter to a comma.
    #    -k1,1 sorts by the first field.
    #    -k2,2 then sorts by the second field.
    tail -n +2 "${CSV_FILE}" | sort -t, -k1,1 -k2,2 >> "${TEMP_FILE}"

    # 3. Replace the original file with the sorted one.
    mv "${TEMP_FILE}" "${CSV_FILE}"

    echo "✅ CSV file sorted successfully."
}


# Function to display help message.
show_help() {
    echo "Usage: $0 <command> <csv_file>"
    echo
    echo "A multi-function script to manage an Execution Environment version matrix."
    echo
    echo "Commands:"
    echo "  discover    Find new image tags from the registry and add them to the CSV."
    echo "  versions    Fill in missing Ansible, Python, RHEL, and Collection versions for images in the CSV."
    echo "  dates       Fill in missing image creation dates using skopeo."
    echo "  sort        Sort the CSV by image path and then by tag."
    echo "  all         Run all tasks in sequence: discover, versions, dates, then sort."
    echo "  help        Show this help message."
}

## --- Main Logic ---

# Check for dependencies first.
for cmd in python3 podman skopeo jq; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "Error: Dependency '$cmd' is not installed. Please install it." >&2
        exit 1
    fi
done

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
    sort)
        sort_csv "$CSV_FILE"
        ;;
    all)
        discover_new_tags "$CSV_FILE"
        get_image_versions "$CSV_FILE"
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