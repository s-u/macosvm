## macosvm
`macosvm` is a command line tool which allows creating and running of virtual machines on macOS 12 (Monterey) using the new Virtualization framework. It has been primarily developed for running macOS guest opearting systems inside virtual machines on M1-based Macs (arm64) with macOS hosts to support CI/CD such as GitHub M1-based runners and our R builds.

### Build
The project can be built either with `xcodebuild` or `make`. The former requires Xcode installation while the latter only requires command line tools (see `xcode-select --install`).

### Quick Start
The tools requires macOS 12 (Monterey) since that is the first system implementing the necessary pieces of the Virtualization framework. To create a macOS guest VM you need the following steps:

```
## Download the desired macOS ipsw image, e.g.:
curl -LO https://updates.cdn-apple.com/2021FCSFall/fullrestores/002-23780/D3417F21-41BD-4DDF-9135-FA5A129AF6AF/UniversalMac_12.0.1_21A559_Restore.ipsw

## create a new VM with 32Gb disk image and install macOS 12:
macosvm --disk disk.img,size=32g --aux aux.img --restore UniversalMac_12.0.1_21A559_Restore.ipsw vm.json

## start the created image with GUI window:
macosvm -g vm.json
```

After your started the VM it will go through the Apple Setup Assistant - you need the GUI to get through that. Once done, I strongly recommend going to Sharing system preferences, setting a unique name and enabling Remote Login and Screen Sharing. Then you can shut down the VM (using Shut Down in the macOS guest). Note that the default is to use NAT networking and your VM will show up on your host's network (details below) so you can use Finder to connect to its screen even if you start without the GUI.

After the minimal setup it ts possible to create a "clone" of your image to keep for later, e.g.:

```
cp -c disk.img master.img
```

Note the `-c` flag which will make a copy-on-write copy, i.e., the cloned image doesn't use any actual space on disk (if you use APFS). This allows you to store different modifications of your base operating system without duplicating storage space.

See `macosvm -h` for a minimal help page. Note that this is an experimental expert tool. There is a lot of debugging output, errors include stack traces etc - this is intentional at this point, nothing horrible is happening, but you may need to read more text that you want to on errors.

### Details

Each virtual machine requires one auxiliary storage (specified with `--aux`) and at least one root device (specified with `--disk`). You can specify multiple disk images for additional devices. The `--disk` option has the form `--disk <file>[,<option>[,<option>...]]`. Valid options are: `ro` = read-only device, `size=<spec>` allocate empty disk with that size. The `<spec>` argument allows `k`, `m` and `g` suffix for powers of 1024 so `32g` means `32*(1024^3)`.

You can specify the number of CPUs with `-c <cpus>` and the available memory (RAM) with `-r <spec>`. If not specified, `--restore` uses the image's minimal requirements (for macOS 12 that is 2 CPUs and 4Gb RAM).

During the macOS installation (`--restore`) step a unique machine identifier (ECID) is generated. The resulting aux image only works with that one identifier. This identifier is stored in the configuration file (as `machineId` entry) and the VM won't boot without it.

This is what the configuration file looks like for the above example:
```
{
  "hardwareModel":"YnBsaX[...]AAAAABt",
  "storage":[
    {"type":"disk", "file":"disk.img", "readOnly":false},
    {"type":"aux", "file":"aux.img", "readOnly":false}
  ],
  "ram":4294967296,
  "machineId":"YnBsaXN0MDDRAQJURUN[...]AAAACE=",
  "displays":[{"dpi":200, "width":2560, "height":1600}],
  "version":1,
  "cpus":2,
  "networks":[{"type":"nat"}],
  "audio":false
}
```
You can edit the file if you want to change the parameters (like CPUs, RAM, ...), but keep a copy in case you break something. The `"hardwareModel"` is just the OS/architecture spec from the image. (FWIW both `hardwareModel` and `machineId` are base64-encoded binary property lists so you can look at the payload with `base64 -d | plutil -p -` )

Note that the virtualization framework imposes some restrictions on what is allowed, e.g., you have to define at least one display even if you don't intend to use it (the `displays` entry is added automatically by `--restore`).

Unless run with `-g`/`--gui` the tool will run solely as a command line tool and can be run in the background. Terminating the tool terminates the VMs. However, if the GUI is used closing the window does NOT terminate the VM. Note that currently the macOS guest systems don't support VM control, so even though it is in theory possible to request VM stop via the VZ framework, it is not actually honored by the macOS guest (as of 12.0.1), so you should use guest-side shutdown (e.g. `sudo shutdown -h now` works). When the guest OS shuts down the tool terminates with exit code 0.

### Networking

The default setup is NAT networking which means your host will allocate a separate local network for the VM. You can use `--net <type>[:<iface>]` so specify different network adapters and different types. `macosvm` currently implements `nat` and `bridge` where the latter requires the name of the host interface to bridge to (if left blank the first interface is used). Note, however, that bridging requires a special entitlement so may not work with SIP enabled for security reasons.

