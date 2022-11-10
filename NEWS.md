## NEWS

### 0.2-0
* command line parameters are now parsed __after__ the specified configuration file is loaded and will cause the settings to be __added__ to the configuration. This allows the use of pre-specified configurations which can be supplemented by command line arguments. This behavior is more intuitive, but different from 0.1 versions which is why we chose to increase the version.
* added `--save <path>` which will write the resulting configuration after all arguments were parsed into a JSON file specified by `<path>`. Note that `--restore` already creates the configuration file without this option, so `--save` should only be used when it is desired to update an existing configuration augmented with command line options to create a new configuration file.
* optional capabilities that depend on the host environment are listed as `Capabilities:` in the output of `--version`

### 0.1-4

* `--net unix:<socket>[,mac=<mac>][,mtu=<mtu>]` creates a network interface which routes network traffic to a unix socket `<socket>` on the host. The default (and minimum) MTU is 1500, but it can be increased (only on macOS 13 and higher). A temporary socket is created in the temporary directory by default, but the directory can be overridden by the `TMPSOCKDIR` environment variable.
* ephemeral files are now also removed on `SIGABRT` which can happen if the Virtualization framework raises an execption
* added support for `usb` disk type (macOS 13 and above only)
* added support for Mac trackpad if both the guest and host are macOS 13
* added `--spice` which will enable clipboard shaing between the host and guest using the SPICE protocol (experimental). Requires macOS 13 host and `spice-vdagent` in the guest. Due to an issue in the Apple VZ framework this currently only works with Linux guests (macOS guests crash).

### 0.1-3

* MAC address of each network interface created will be shown at startup, e.g.:
  ```
   + network: ether 9a:74:8c:65:6d:e0
  ```
  to make it easier to associate IP addresses to VMs via `arp -a`.

* `--net nat:<MAC>` defines a NAT network interface with a given pre-defined MAC address. Similarly, the interfaces in the `"networks"` configuration section can have `"mac"` keys that define the MAC address.

* additonal option `--mac <MAC>` on the command line will override the MAC address of the first interface, regardless how it was defined (configuration file or command line). This is useful when creating multiple VMs from the same configuration file, typically with `--ephemeral`.

* added support for VirtIOFS shared directories via `--vol` option. The syntax is `--vol <path>[,ro][,{name=<name>|automount}]` where `<path>` is the path on the host OS to share and `<name>` is the name (also known as "tag") of the share. On macOS 13 (Ventura) and higher `automount` option can be specified in which case the share is automatically mounted in `/Volumes/My Shared Files`. If not specifed, the share has to be mounted by name with `mount_virtiofs <name> <mountpoint>` in the guest OS.

* guest serial console is now also enabled in macOS guests (in `/dev/cu.virtio` and `/dev/tty.virtio`). Previous versions enabled it only for Linux guests. It can be explicitly disabled using `--no-serial` option.

* experimental `--pty` option allows the creation of pseudo-tty device for the guest serial console. Without this option the serial console is mapped to the stdin/out streams of the `macosvm` process. If the `--pty` option is specified then `macosvm` will create a new `pty` (typically in `/dev/ptys.<n>`) and map VM's serial port to it.

  Unfortuantely, Apple Virtialization Framework requires that the pty is connected before the VM is started. Therefore currently `macosvm` will print the `pty` path and wait for user input so that the user can connect to the newly created pty before starting the VM. Proceeding without connected pty leads to an error. This behavior may change in the future, which is why it is considered experimental.


### 0.1-2

* added `--ephemeral` flag: when specified, all (read-write) disks (including auxiliary) will be cloned (see `man clonefile`) prior to starting the VM (by appending `-clone-<pid>` to their paths) and the clones are used instead of the original. Upon termination all clones are deleted. This is functionally similar to the `--rm` flag in Docker. IMPORTANT: you will lose any changes to the mounted disks made by the VM. This is intended for runners that pick up work, do something and then post the results somewhere, but don't keep them locally. `macosvm` attempts to clean up clones even on abnormal termination where possible. Individual disks can specify `keep` option which prevents them from being cloned in the ephemeral mode, e.g.: `--disk results.img,keep` will cause `results.img` to be used directly and modified by the VM even if `--ephemeral` is specified.

* added heuristic to detect ECID from the auxiliary storage if it is not supplied by the configuration file

* make the configuration file optional. It is now possible to start VMs simply by specifying the desired CPU/RAM and disk images and `macosvm` will try to infer all necessary settings automatically. I.e., if you have existing disk images `aux.img` and `disk.img` from previously restored/created VM, you can use the following to start it:
  ```
  macosvm -g --disk disk.img --aux aux.img -c 2 -r 4g
  ```

* fixed a bug where the `"readOnly"` flag specified in the configuration file was not honored

* added `os` and `bootInfo` entries in the configuration. Currently valid entries for `os` are `"macos"` (default) and `"linux"`. The latter uses `bootInfo` dictionary with entries `kernel` (path, mandatory) and `parameters` (string, optional). Also a new storage type `"initrd"` has been added to support the Linux boot process (untested).

### 0.1-1

* initial version
