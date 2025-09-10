# Red Hat Ansible Automation Platform Execution Environment Version Matrix

[![GitHub last commit](https://img.shields.io/github/last-commit/lennysh/aap-ee-version-matrix.svg)](https://github.com/lennysh/aap-ee-version-matrix/commits/main) [![GitHub license](https://img.shields.io/github/license/lennysh/aap-ee-version-matrix.svg)](https://github.com/lennysh/aap-ee-version-matrix/blob/main/LICENSE) [![Contributions welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](https://github.com/lennysh/aap-ee-version-matrix/pulls) ![GitHub contributors](https://img.shields.io/github/contributors/lennysh/aap-ee-version-matrix) ![GitHub Issues or Pull Requests](https://img.shields.io/github/issues/lennysh/aap-ee-version-matrix)

This repository provides a centralized, community-driven tracker for Red Hat Ansible Automation Platform (AAP) Execution Environment package and OS versions. It aims to offer a clear and quick reference for mapping AAP EE's to their corresponding package versions, such as `ansible-core` and `python` as well as their included Ansible collections (with versions) and other packages.

## 📋 Data Tables

For easy viewing, the raw data has been converted into a user-friendly Markdown table, which is generated from the central CSV file.

* [registry.redhat.io/ansible-automation-platform/ee-minimal-rhel8](./images/registry.redhat.io/ansible-automation-platform/ee-minimal-rhel8/README.md)
* [registry.redhat.io/ansible-automation-platform/ee-minimal-rhel9](./images/registry.redhat.io/ansible-automation-platform/ee-minimal-rhel9/README.md)
* [registry.redhat.io/ansible-automation-platform-24/ee-minimal-rhel8](./images/registry.redhat.io/ansible-automation-platform-24/ee-minimal-rhel8/README.md)
* [registry.redhat.io/ansible-automation-platform-24/ee-minimal-rhel9](./images/registry.redhat.io/ansible-automation-platform-24/ee-minimal-rhel9/README.md)
* [registry.redhat.io/ansible-automation-platform-24/ee-supported-rhel8](./images/registry.redhat.io/ansible-automation-platform-24/ee-supported-rhel8/README.md)
* [registry.redhat.io/ansible-automation-platform-24/ee-supported-rhel9](./images/registry.redhat.io/ansible-automation-platform-24/ee-supported-rhel9/README.md)
* [registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel8](./images/registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel8/README.md)
* [registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel9](./images/registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel9/README.md)
* [registry.redhat.io/ansible-automation-platform-25/ee-supported-rhel8](./images/registry.redhat.io/ansible-automation-platform-25/ee-supported-rhel8/README.md)
* [registry.redhat.io/ansible-automation-platform-25/ee-supported-rhel9](./images/registry.redhat.io/ansible-automation-platform-25/ee-supported-rhel9/README.md)

## 🤝 Contributing

Found a mistake or have an update for a new release? Contributions are highly encouraged!

To contribute, please **submit a pull request with your changes to the `AAP_EE.csv` files only**. Do not edit the Markdown file directly, as it is overwritten by the automation script. Once your pull request is merged, the script will be re-run to update the table.

## ✍️ Authors

* [LennySh](https://github.com/lennysh)

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.