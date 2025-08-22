# Red Hat Ansible Automation Platform Execution Environment Version Matrix

[![GitHub last commit](https://img.shields.io/github/last-commit/lennysh/aap-ee-version-matrix.svg)](https://github.com/lennysh/aap-ee-version-matrix/commits/main) [![GitHub license](https://img.shields.io/github/license/lennysh/aap-ee-version-matrix.svg)](https://github.com/lennysh/aap-ee-version-matrix/blob/main/LICENSE) [![Contributions welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](https://github.com/lennysh/aap-ee-version-matrix/pulls) ![GitHub contributors](https://img.shields.io/github/contributors/lennysh/aap-ee-version-matrix) ![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/lennysh/aap-ee-version-matrix/update-md-table.yml.yml) ![GitHub Issues or Pull Requests](https://img.shields.io/github/issues/lennysh/aap-ee-version-matrix)

This repository provides a centralized, community-driven tracker for Red Hat Ansible Automation Platform (AAP) Execution Environment package and OS versions. It aims to offer a clear and quick reference for mapping AAP EE's to their corresponding package versions, such as `ansible-core` and `python`.

## 📋 Compatibility Tables

For easy viewing, the raw data has been converted into a user-friendly Markdown table, which is generated from the central CSV file.

* [**Execution Environments**](./AAP_EE.md)

## ⚙️ How It Works

The core of this repository is a simple, automated workflow designed for clarity and easy maintenance.

1.  **Data Collection (`aap-ee2csv.sh`)**: A master script, `aap-ee2csv.sh`, is responsible for gathering all the data. It's a multi-function tool that automates the entire collection process:
    * **Discovers** all available image tags from the Red Hat registry for a predefined list of EEs.
    * **Inspects** each image to find its `ansible-core`, `python`, and RHEL versions.
    * **Retrieves** the image creation timestamp using `skopeo`.

2.  **Raw Data**: All version information is maintained in the `AAP_EE.csv` file. This is the single source of truth for the entire repository and the only file that should be edited manually.

3.  **Conversion Script**: A bash script (`csv2md.sh`) reads the `AAP_EE.csv` file. This script can filter rows, remove columns, and format URLs into clickable links.

4.  **Markdown Output**: The script processes the data from each `AAP_EE.csv` file and generates the the Markdown files (`AAP_EE.md`), creating clean, readable tables.

### How to Update the Data

To run the full data collection pipeline and then generate the Markdown file, you would execute the following commands:

```bash
# 1. Run the master script to discover new tags and fill in all missing data
./scripts/aap-ee2csv.sh all ./data/AAP_EE.csv

# 2. Run the conversion script to update the Markdown table
./scripts/csv2md.sh \
  -t "Red Hat Ansible Automation Platform Execution Environment Version Matrix" \
  ./data/AAP_EE.csv > AAP_EE.md
```

## 🤝 Contributing

Found a mistake or have an update for a new release? Contributions are highly encouraged!

To contribute, please **submit a pull request with your changes to the `AAP_2x.csv` files only**. Do not edit the Markdown files directly, as they are overwritten by the automation script. Once your pull request is merged, the script will be re-run to update the tables.

## ✨ Contributors

A big thank you to all the contributors who have helped improve this project! You can see a full list of everyone who has contributed on the [contributors page](https://github.com/lennysh/aap-ee-version-matrix/graphs/contributors).

<a href = "https://github.com/lennysh/aap-ee-version-matrix/graphs/contributors">
  <img src = "https://contrib.rocks/image?repo=lennysh/aap-ee-version-matrix"/>
</a>

## ✍️ Authors

* [LennySh](https://github.com/lennysh)

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.