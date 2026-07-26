# ConfigMgr Boot Image Automation

PowerShell automation for creating, updating, and maintaining Microsoft Configuration Manager (ConfigMgr) boot images. This project streamlines the boot image lifecycle by reducing manual effort, enforcing consistency, and simplifying deployment management.

## Overview

Managing boot images in Configuration Manager can be repetitive and error-prone, especially across multiple operating system versions. This script automates the end-to-end process of maintaining boot images, allowing administrators to standardize deployments and reduce operational overhead.

Designed for enterprise environments, the automation provides a repeatable workflow that can be customized through a centralized configuration section.

## Features

* Automated boot image creation and updates
* Configuration Manager integration
* Driver injection support
* Windows ADK and WinPE support
* Automatic content distribution
* Logging and status reporting
* Configuration-driven deployment settings
* Modular design for easy customization

## Requirements

* Microsoft Configuration Manager (Current Branch)
* Windows PowerShell 5.1+
* Windows ADK with WinPE Add-on
* Configuration Manager PowerShell Module
* Appropriate administrative permissions

## Configuration

Environment-specific settings are centralized within the configuration section of the script. Before running, review and update values such as:

* Configuration Manager Site Code
* Site Server
* Content Library / Data Source Paths
* Boot Image Storage Locations
* Driver Repository Paths
* Distribution Points or Distribution Point Groups

This design allows the remainder of the script to remain portable across environments.

## Usage

1. Configure the environment-specific settings.
2. Run the script from a Configuration Manager administrative workstation or site server.
3. Review the generated log output.
4. Validate the updated boot images in the Configuration Manager console.

## Customization

The project is designed to be adapted to different Configuration Manager environments by modifying only the configuration section. The core automation logic remains unchanged.

## Repository Structure

```text
ConfigMgrBootImageAutomation.ps1
README.md
LICENSE
```

## Disclaimer

This project is provided as an example of enterprise automation. Review and test all configuration settings in a non-production environment before deploying into production.

## License

This project is released under the MIT License.
