# installK8s — Prerequisite scripts

This directory provides small, focused scripts to prepare a RHEL/CentOS/AlmaLinux (or compatible) host for a Kubernetes installation. The scripts are designed to be easy to read and to be run by an operator with root privileges.

Top-level helper scripts

- `00_prerequisite_check.sh`
  - Runs the set of *check* scripts (the files whose names start with `0` and contain "_check") and prints a human-readable status summary.
  - Intended for interactive inspection only — it does not apply changes. Output is sent to both the console and the log files `00_prerequisite_check.sh.log` and `00_prerequisite_check.sh.err`.

- `0_prerequisite.sh`
  - Runs the *apply* scripts that make system changes (install packages, disable swap, load kernel modules, set sysctl values, configure SELinux, and open firewall ports).
  - Default behaviour sets SELinux to `permissive`. To change that pass the desired mode as the first argument, e.g. `./0_prerequisite.sh enforcing`.
  - It logs stdout and stderr to `0_prerequisite.sh.log` and `0_prerequisite.sh.err` respectively.

Per-check scripts

- `01_os_packages_check.sh` / `1_os_packages.sh`
  - Checks for and installs required OS packages listed in `basicPackages`.
- `02_swap_disable_check.sh` / `2_swap_disable.sh`
  - Checks for swap (temporary and fstab) and disables it when applied.
- `03_activate_modules_check.sh` / `3_activate_modules.sh`
  - Checks and ensures kernel modules `overlay` and `br_netfilter` are loaded and persisted.
- `04_network_forwarding_check.sh` / `4_network_forwarding.sh`
  - Ensures sysctl keys required for bridged networking are present and set to `1`.
- `05_SELinux_check.sh` / `5_SELinux_config.sh`
  - Reports and sets SELinux runtime and configuration mode.
- `06_firewall_port_check.sh` / `6_firewall_port.sh`
  - Checks required firewall ports (e.g. 6443, 10250) and opens them when applying.

Recommended execution order

1. Inspect the system: run `./00_prerequisite_check.sh` and review the `.log`/`.err` files it produces.
2. If you are satisfied with the checks and understand the changes, run `./0_prerequisite.sh` to apply them.

Precautions and notes

- Run these scripts as root (or with sudo) — the apply scripts modify system configuration and install packages.
- The apply script will make changes such as disabling swap, modifying `/etc/fstab`, changing sysctl files under `/etc/sysctl.d/`, updating `/etc/selinux/config`, and opening firewall ports with `firewall-cmd`.
- Backups: important files modified by the scripts may be changed in place (some edits create `.bak` files where explicitly coded). Consider taking a manual backup before applying changes in production environments.
- Idempotence: scripts are written to try to be idempotent, but always validate after running.
- Testing: if possible, test these scripts in a disposable Vagrant/VM/container before running on production hosts.

Contact / further improvements

- If you'd like, I can add a dry-run mode to the apply script, produce unit tests for parsing logic, or generate a wrapper that performs safe, interactive confirmations before each change.
