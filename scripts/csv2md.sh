#!/bin/bash

# A script to convert CSV to a Markdown table using AWK for robust parsing.

# --- Functions ---
usage() {
    echo "Usage: $0 [-t <title>] [-F \"Filters\"] [-R \"Columns_to_remove\"] <input_csv>"
    echo
    echo "Converts a CSV file to a Markdown table, correctly handling quoted commas."
    echo
    echo "Options:"
    echo "  -t <title>      Add a Markdown H1 header to the output."
    echo "  -F <filters>    Filter rows. Ex: \"Release Date=December 3, 2024\""
    echo "  -R <columns>    Comma-separated list of column headers to remove. Ex: \"Notes,EDA\""
    echo "  -h              Display this help message."
    exit 1
}

# --- Argument Parsing ---
markdown_title=""
filter_string=""
remove_string=""
while getopts ":t:F:R:h" opt; do
    case ${opt} in
        t) markdown_title=$OPTARG ;;
        F) filter_string=$OPTARG ;;
        R) remove_string=$OPTARG ;;
        h) usage ;;
        \?) echo "Invalid option: -$OPTARG" >&2; usage ;;
        :) echo "Option -$OPTARG requires an argument." >&2; usage ;;
    esac
done
shift $((OPTIND -1))

# --- Input Validation ---
if [ -z "$1" ]; then
    echo "Error: Input CSV file is required." >&2
    usage
fi
input_file="$1"
if [ ! -f "$input_file" ]; then
    echo "Error: File '$input_file' not found." >&2
    exit 1
fi

# --- Core Logic using AWK ---
awk -v title="$markdown_title" -v filters="$filter_string" -v remove_cols="$remove_string" '
BEGIN {
    FPAT = "(\"[^\"]*\")|([^,]*)"

    # Define a list of columns that should get the code block formatting.
    split("tags", temp, ",")
    for (i in temp) {
        codeblock_columns[temp[i]] = 1
    }

    # Define a list of columns that should get the collapsible <details> formatting.
    split("ansible_collections,packages,pip_packages", temp, ",")
    for (i in temp) {
        collapsible_columns[temp[i]] = 1
    }

    if (remove_cols != "") {
        n = split(remove_cols, temp_arr, ",")
        for (i=1; i<=n; i++) {
            cols_to_remove[temp_arr[i]] = 1
        }
    }

    if (filters != "") {
        n = split(filters, pairs, ",")
        for (i = 1; i <= n; i++) {
            split(pairs[i], pair, "=")
            key = pair[1]
            val = substr(pairs[i], length(key) + 2)
            filter_map[key] = val
        }
    }
}
NR == 1 {
    # This block for processing the header is unchanged.
    sub(/\r$/, "")
    if (title != "") { print "# " title "\n" }

    num_cols_to_keep = 0
    for (i = 1; i <= NF; i++) {
        header_field = $i
        gsub(/^"|"$/, "", header_field)
        gsub(/^[ \t]+|[ \t]+$/, "", header_field)

        if (!(header_field in cols_to_remove)) {
            num_cols_to_keep++
            cols_to_keep[num_cols_to_keep] = i
            kept_headers[num_cols_to_keep] = header_field
        }
        header_to_idx[header_field] = i
    }

    for (col_name in filter_map) {
        if (!(col_name in header_to_idx)) {
            print "Error: Filter column \047" col_name "\047 not found in CSV header." > "/dev/stderr"; exit 1
        }
    }

    for (j = 1; j <= num_cols_to_keep; j++) { printf "| %s ", kept_headers[j] }; print "|"
    for (j = 1; j <= num_cols_to_keep; j++) { printf "|---" }; print "|"
    next
}
{
    # This block for processing data rows has the updated logic.
    sub(/\r$/, "")
    for (col_name in filter_map) {
        raw_field = $header_to_idx[col_name]
        gsub(/^"|"$/, "", raw_field)
        filter_val = filter_map[col_name]
        if (raw_field != filter_val) { next }
    }

    for (j = 1; j <= num_cols_to_keep; j++) {
        original_idx = cols_to_keep[j]
        current_field = $original_idx
        current_header = kept_headers[j]

        gsub(/^"|"$/, "", current_field)
        gsub(/^[ \t]+|[ \t]+$/, "", current_field)

        # GENERIC LOGIC: Check if the current column header is in our list.
        if (current_header in codeblock_columns) {
            count = split(current_field, temp_array, ",")
            formatted_string = ""
            for (i = 1; i <= count; i++) {
                formatted_string = formatted_string "`" temp_array[i] "`"
                if (i < count) 
                {
                    formatted_string = formatted_string ", "
                }
            }
            printf "| %s ", formatted_string
        } else if (current_header in collapsible_columns) {
            count = split(current_field, temp_array, ", ")
            display_count = count

            # Handle "empty" cases to show a count of 0 in the summary.
            if (count == 1 && (current_field == "No collections found" || current_field == "Not found")) {
                display_count = 0
                formatted_string = current_field
                # Print the final, newly formatted string within a <details> block.
                printf "| %s ", formatted_string
            } else {
                # Rebuild the string with backticks and HTML line breaks.
                formatted_string = ""
                for (i = 1; i <= count; i++) 
                {
                    formatted_string = formatted_string "`" temp_array[i] "`"
                    if (i < count) 
                    {
                        formatted_string = formatted_string "<br>"
                    }
                }
                # Print the final, newly formatted string within a <details> block.
                printf "| <details><summary>View (%d)</summary>%s</details> ", display_count, formatted_string
            }
        } else if (current_field ~ /^https?:\/\//) {
            printf "| [%s](%s) ", current_header, current_field
        } else {
            printf "| %s ", current_field
        }
    }
    print "|"
}' "$input_file"