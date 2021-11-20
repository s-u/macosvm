## NEWS

### 0.1-2

* added `--ephemeral` flag: when specified, all (read-write) disks (including auxiliary) will be cloned (see `man clonefile`) prior to starting the VM (by appending `-clone-<pid>` to their paths) and the clones are used instead of the original. Upon termination all clones are deleted. This is functionally similar to the `--rm` flag in Docker. IMPORTANT: you will lose any changes to the mounted disks made by the VM. This is intended for runners that pick up work, do something and then post the results somewhere, but don't keep them locally. `macosvm` attempts to clean up clones even on abnormal termination where possible.

* added heuristic to detect ECID from the auxiliary storage if it is not supplied by the configuration file

* make the configuration file optional. It is now possible to start VMs simply by specifying the desired CPU/RAM and disk images and `macosvm` will try to infer all necessary settings automatically. I.e., if you have existing disk images `aux.img` and `disk.img` from previously restored/created VM, you can uset he following to start it:
  ```
  macosvm -g --disk disk.img --aux aux.img -c 2 -r 4g
  ```

* fixed a bug where the `"readOnly"` flag specified in the configuration file was not honored

* added `os` and `bootInfo` entries in the configuration. Currently valid entries for `os` are `"macos"` (default) and `"linux"`. The latter uses `bootInfo` dictionary with entries `kernel` (path, mandatory) and `parameters` (string, optional). Also a new storage type `"initrd"` has been added to support the Linux boot process (untested).

### 0.1-1

* initial version
