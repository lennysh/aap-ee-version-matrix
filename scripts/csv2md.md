# CSV to Markdown Table Converter

A command-line script for converting CSV files into well-formatted Markdown tables.

This script is designed to handle real-world, messy CSV files, correctly parsing fields with spaces, embedded commas, and empty values. It provides flexible options for filtering rows, removing columns, and formatting the final output, making it an ideal tool for documentation and reporting workflows.

## Features

* **Robust CSV Parsing:** Correctly handles spaces in headers, quoted fields containing commas, and empty fields without breaking column alignment.

* **URL Formatting:** Automatically detects URLs in your data and converts them into clickable Markdown links, using the column header as the link text.

* **Row Filtering:** Filter the output to include only the rows that match one or more specific criteria (e.g., `Status=Active`).

* **Column Removal:** Exclude one or more columns from the final table to create a more focused view of your data.

* **Custom Title:** Prepend a main H1 title to your Markdown output.

* **Cross-Platform Compatibility:** Sanitizes Windows-style line endings (`\r\n`) for reliable execution in any environment.

## Requirements

* **Bash:** A standard Unix-like shell.

* **awk:** A standard command-line text-processing utility. `gawk` (GNU Awk) is recommended and is the default on most Linux systems.

## Installation

1. Save the script to a file named `csv2md.sh`.

2. Make the script executable from your terminal:

   ```
   chmod +x csv2md.sh
   ```

3. (Optional) For system-wide access, move the script to a directory in your `PATH`, such as `/usr/local/bin`.

## Usage

The script is run from the command line with several optional flags to control the output.

```
./csv2md.sh [OPTIONS] <input_csv_file>
```

### Options

| **Flag** | **Argument** | **Description** |
|---|---|---|
| `-t` | `<"Title Text">` | Adds a Markdown H1 header to the top of the output. |
| `-F` | `<"Filters">` | A comma-separated string of `Column=Value` pairs to filter rows. Only rows matching **all** filters are included. |
| `-R` | `<"Columns">` | A comma-separated string of column headers to **remove** from the output. |
| `-h` |  | Displays the help message. |

## Examples

First, let's use the following sample CSV file named `releases.csv`:

```
AAP Ver.,Release Date,Operator CSV (Cluster-scoped),Operator CSV (Namespace-scoped),Controller,Release_Notes,Notes
2.4,"December 3, 2024",aap-operator.v2.4.0-0.1733186325,aap-operator.v2.4.0-0.1733185647,4.5.13,[https://docs.redhat.com/en/notes/1](https://docs.redhat.com/en/notes/1),
2.4,"December 18, 2024",aap-operator.v2.4.0-0.1733945743,aap-operator.v2.4.0-0.1733943951,4.5.15,[https://docs.redhat.com/en/notes/2](https://docs.redhat.com/en/notes/2),
2.4,,aap-operator.v2.4.0-0.1725257213,aap-operator.v2.4.0-0.1725256739,4.5.x,,DEAD release
```

### 1. Basic Conversion

Convert the entire CSV file to a Markdown table.

**Command:**

```
./csv2md.sh releases.csv
```

**Output:**

```
| AAP Ver. | Release Date | Operator CSV (Cluster-scoped) | Operator CSV (Namespace-scoped) | Controller | Release_Notes | Notes |
|---|---|---|---|---|---|---|
| 2.4 | December 3, 2024 | aap-operator.v2.4.0-0.1733186325 | aap-operator.v2.4.0-0.1733185647 | 4.5.13 | [Release_Notes](https://docs.redhat.com/en/notes/1) |  |
| 2.4 | December 18, 2024 | aap-operator.v2.4.0-0.1733945743 | aap-operator.v2.4.0-0.1733943951 | 4.5.15 | [Release_Notes](https://docs.redhat.com/en/notes/2) |  |
| 2.4 |  | aap-operator.v2.4.0-0.1725257213 | aap-operator.v2.4.0-0.1725256739 | 4.5.x |  | DEAD release |
```

### 2. Filtering Rows

Show only the releases where the `Controller` version is `4.5.15`.

**Command:**

```
./csv2md.sh -F "Controller=4.5.15" releases.csv
```

**Output:**

```
| AAP Ver. | Release Date | Operator CSV (Cluster-scoped) | Operator CSV (Namespace-scoped) | Controller | Release_Notes | Notes |
|---|---|---|---|---|---|---|
| 2.4 | December 18, 2024 | aap-operator.v2.4.0-0.1733945743 | aap-operator.v2.4.0-0.1733943951 | 4.5.15 | [Release_Notes](https://docs.redhat.com/en/notes/2) |  |
```

### 3. Removing Columns

Display the table but remove the long operator CSV columns to make it more readable.

**Command:**

```
./csv2md.sh -R "Operator CSV (Cluster-scoped),Operator CSV (Namespace-scoped)" releases.csv
```

**Output:**

```
| AAP Ver. | Release Date | Controller | Release_Notes | Notes |
|---|---|---|---|---|
| 2.4 | December 3, 2024 | 4.5.13 | [Release_Notes](https://docs.redhat.com/en/notes/1) |  |
| 2.4 | December 18, 2024 | 4.5.15 | [Release_Notes](https://docs.redhat.com/en/notes/2) |  |
| 2.4 |  | 4.5.x |  | DEAD release |
```

### 4. Combining All Options

Create a titled, filtered, and cleaned-up table showing only releases in December that have notes.

**Command:**

```
./csv2md.sh \
  -t "December 2024 Releases with Notes" \
  -F "Release Date=December 18, 2024" \
  -R "Operator CSV (Cluster-scoped),Operator CSV (Namespace-scoped),AAP Ver." \
  releases.csv
```

**Output:**

```
# December 2024 Releases with Notes

| Release Date | Controller | Release_Notes | Notes |
|---|---|---|---|
| December 18, 2024 | 4.5.15 | [Release_Notes](https://docs.redhat.com/en/notes/2) |  |
