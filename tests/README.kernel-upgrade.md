# Offline kernel dependency regression

Run from the repository root:

```sh
# Fetch the test environment once, if not already present:
docker pull python:3.14-slim@sha256:cd89c30eda26ee911a4611b18680086e0ea42e6f5f8cbe653d07fa7958c9cec8
python3 tests/run_kernel_upgrade_tests.py
```

The runner never pulls an image implicitly. It pins a multi-platform image containing
Python 3, Bash and APT. `--image` allows testing another such Linux image.
On Debian-based Linux, the resolver suite can also run without Docker or root:

```sh
python3 -B tests/test_kernel_upgrade.py
```

The container run is network-disabled, read-only, capability-dropped and uses a
64 MiB disposable tmpfs. Source mounts are read-only. No package is downloaded,
installed or removed. The APT architecture is explicitly amd64 even on ARM hosts.
The APT configuration redirects package lists, status, cache, sources, preferences
and configuration directories to the temporary fixture root, avoiding host state.

## Contract tested

Each of the two production upgrade commands is extracted from its script and
expanded by Bash with its actual `APT_OPTIONS` assignment. `TORIFY` is empty
because transport is outside this offline resolver test. An `apt-get` shell
function injects only `--simulate`; upgrade options come from the source, not a
second handwritten command. Only isolated command/assignment lines are evaluated;
the full appliance scripts and their sourced files are never executed.

For **each path**, the suite checks:

- The new ABI-specific signed image and updated kernel meta-package are selected.
- No package is removed. A synthetic conflicting application update must remain
  held back instead of removing its installed conflict partner.
- An explicit `hold ok installed` selection on the kernel meta-package remains
  respected, with neither a new image nor updated meta-package selected.
- Removing `--with-new-pkgs` is a negative control: plain upgrade keeps back the
  meta-package and does not select the new image.

To check the real baseline rather than just the negative control, export the
original three changed scripts into a separate source tree and run:

```sh
python3 tests/run_kernel_upgrade_tests.py --source-root /absolute/baseline-tree
```

The positive kernel-selection test must fail for both original command paths.
The runner also checks all three modified shell files using Linux `bash -n`.

## Fixtures and provenance

`fixtures/kernel-upgrade/Packages` contains **unchanged** official Debian
Bookworm-security stanzas for `linux-image-amd64` and
`linux-image-6.1.0-54-amd64`, version `6.1.190-1`. `provenance.json` records the
source URL, saved full-index hash and extracted fixture hash. The test verifies
the extracted fixture hash before invoking APT. These were extracted from a
previously saved HTTPS index; repository signatures were not independently
verified. No package binaries are included and no vulnerability/fix status is
inferred by these tests.

`status` is an **inert, synthetic dpkg installed-state fixture**, not an inventory
of a real device. It represents an older ABI image/meta-package, the dependencies
and recommendations needed by the official new image, and two synthetic conflict
control packages. Versions of supporting packages are fixture values, not a
claim about an actual installation. `synthetic-Packages` supplies only the
conflicting application update; it is deliberately separate from official data.

These checks cover APT dependency selection, not whole-script execution,
bootloader/initramfs updates, physical boot, Raspberry Pi/Armbian packages,
repository freshness, repository signatures, or the running kernel. Updating
packages alone does not prove host-kernel remediation.
