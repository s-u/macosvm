#import "VMInstance.h"

/* for cloneAllStorage */
#include <sys/clonefile.h>
#include <unistd.h>
#include <sys/errno.h>
#include <sys/stat.h>
/* for socket networking */
#include <sys/un.h>
#include <sys/socket.h>

@implementation VMSpec

- (instancetype) init {
    self = [super init];
    machineIdentifierData = hardwareModelData = nil;
    storage = displays = networks = nil;
    cpus = 0;
    ram = 0;
    os = nil;
    bootInfo = nil;
    audio = NO;
#ifdef MACOS_GUEST
    _restoreImage = nil;
#endif
    use_serial = YES;
    pty = NO;
    spice = NO;
    ptyPath = nil;
    return self;
}

- (NSError *) readFromJSON: (NSInputStream*) jsonStream {
    NSError *err = nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithStream:jsonStream options: NSJSONReadingTopLevelDictionaryAssumed error: &err];
    if (err)
        return err;
    NSString *hardwareModel = root[@"hardwareModel"];
    hardwareModelData = hardwareModel ? [[NSData alloc] initWithBase64EncodedString:hardwareModel options:0] : nil;
    NSString *machineIdentifier = root[@"machineId"];
    machineIdentifierData = machineIdentifier ? [[NSData alloc] initWithBase64EncodedString:machineIdentifier options:0] : nil;
    os = root[@"os"];
    hardwareModelData = hardwareModel ? [[NSData alloc] initWithBase64EncodedString:hardwareModel options:0] : nil;
    id tmp = root[@"cpus"];
    if (tmp && [tmp isKindOfClass:[NSNumber class]])
        cpus = (int) [(NSNumber*)tmp integerValue];
    tmp = root[@"ram"];
    if (tmp && [tmp isKindOfClass:[NSNumber class]])
        ram = [(NSNumber*)tmp unsignedLongValue];
    tmp = root[@"storage"];
    if (tmp && [tmp isKindOfClass:[NSArray class]])
        storage = tmp;
    tmp = root[@"bootInfo"];
    if (tmp && [tmp isKindOfClass:[NSDictionary class]])
        bootInfo = tmp;
    tmp = root[@"networks"];
    if (tmp && [tmp isKindOfClass:[NSArray class]])
        networks = tmp;
    tmp = root[@"displays"];
    if (tmp && [tmp isKindOfClass:[NSArray class]])
        displays = tmp;
    tmp = root[@"shares"];
    if (tmp && [tmp isKindOfClass:[NSArray class]])
        shares = tmp;
    tmp = root[@"audio"];
    if (tmp && [tmp isKindOfClass:[NSNumber class]])
        audio = [(NSNumber*)tmp unsignedLongValue] ? YES : NO;
    tmp = root[@"serial"];
    if (tmp && [tmp isKindOfClass:[NSNumber class]])
        use_serial = [(NSNumber*)tmp unsignedLongValue] ? YES : NO;
    return nil;
}

- (NSError*) writeToJSON: (NSOutputStream*) jsonStream {
    NSDictionary *src = @{
        @"version": @1,
        @"os" : os ? os : @"macos",
        @"cpus": [NSNumber numberWithInteger: cpus],
        @"ram": [NSNumber numberWithUnsignedLong: ram],
        @"storage" : storage ? storage : [NSArray array],
        @"audio" : audio ? @(YES) : @(NO),
	@"serial" : use_serial ? @(YES) : @(NO)
    };
    NSMutableDictionary *root = [[NSMutableDictionary alloc] init];
    [root setDictionary:src];
    if (hardwareModelData)
        [root setObject:[hardwareModelData base64EncodedStringWithOptions:0] forKey:@"hardwareModel"];
    if (bootInfo)
        [root setObject:bootInfo forKey:@"bootInfo"];
    if (machineIdentifierData)
        [root setObject:[machineIdentifierData base64EncodedStringWithOptions:0] forKey:@"machineId"];
    if (displays)
        [root setObject:displays forKey:@"displays"];
    if (networks)
        [root setObject:networks forKey:@"networks"];
    if (shares)
        [root setObject:shares forKey:@"shares"];
    NSError *err = nil;
    [NSJSONSerialization writeJSONObject:root toStream:jsonStream
                                 options:NSJSONWritingWithoutEscapingSlashes
                                   error:&err];
    return err;
}

- (void) addDefaults {
    if (!displays) {
        displays = @[
            @{
                @"width": @2560,
                @"height": @1600,
                @"dpi": @200
            }
        ];
    }
    if (!networks)
        networks = @[ @{ @"type": @"nat" } ];
}

- (void) addDisplayWithWidth: (int) width height: (int) height dpi: (int) dpi {
    NSDictionary *display = @{
            @"width": [NSNumber numberWithInteger:width],
            @"height": [NSNumber numberWithInteger:height],
            @"dpi": [NSNumber numberWithInteger:dpi]
    };
    displays = displays ? [displays arrayByAddingObject:display] : @[display];
}

- (void) addDirectoryShare: (NSString*) path volume: (NSString*) volume readOnly: (BOOL) readOnly {
    NSDictionary *root = @{
        @"path" : path,
        @"volume" : volume,
        @"readOnly" : @(readOnly)
    };
    shares = shares ? [shares arrayByAddingObject:root] : @[root];
}

- (void) addDirectoryShares: (NSArray*) paths volume: (NSString*) volume readOnly: (BOOL) readOnly {
    NSDictionary *root = @{
        @"paths" : paths,
        @"volume" : volume,
        @"readOnly" : @(readOnly)
    };
    shares = shares ? [shares arrayByAddingObject:root] : @[root];
}

- (void) addAutomountDirectoryShare: (NSString*) path readOnly: (BOOL) readOnly {
    NSDictionary *root = @{
        @"path" : path,
        @"automount" : @(YES),
        @"readOnly" : @(readOnly)
    };
    shares = shares ? [shares arrayByAddingObject:root] : @[root];
}

- (void) addAutomountDirectoryShares: (NSArray*) paths readOnly: (BOOL) readOnly {
    NSDictionary *root = @{
        @"paths" : paths,
        @"automount" : @(YES),
        @"readOnly" : @(readOnly)
    };
    shares = shares ? [shares arrayByAddingObject:root] : @[root];
}

- (void) addNetwork: (NSString*) type {
    NSDictionary *root = @{
        @"type" : type
    };
    networks = networks ? [networks arrayByAddingObject:root] : @[root];
}

- (void) addNetworkSpecification: (NSDictionary*) spec {
    networks = networks ? [networks arrayByAddingObject:spec] : @[spec];
}

- (void) addNetwork: (NSString*) type mac:(NSString*) mac {
    NSDictionary *root = @{
        @"type" : type,
        @"mac" : mac
    };
    networks = networks ? [networks arrayByAddingObject:root] : @[root];
}

- (void) setPrimaryMAC: (NSString*) mac {
    if (networks && [networks count]) {
        NSDictionary *fa = [networks objectAtIndex:0];
        NSMutableDictionary *nn = [NSMutableDictionary dictionaryWithDictionary: fa];
	[nn setObject: mac forKey:@"mac"];
        if ([networks count] == 1)
            networks = @[nn];
        else {
            NSMutableArray *ma = [NSMutableArray arrayWithObject: nn];
            networks = [ma arrayByAddingObjectsFromArray:[networks subarrayWithRange: NSMakeRange(1, [ma count] - 1)]];
        }
    } else [self addNetwork: @"nat" mac:mac];
}

- (void) addNetwork: (NSString*) type interface: (NSString*) iface {
    NSDictionary *root = @{
        @"type" : type,
        @"interface" : iface
    };
    networks = networks ? [networks arrayByAddingObject:root] : @[root];
}

- (void) addNetwork: (NSString*) type interface: (NSString*) iface mac: (NSString*) mac {
    NSDictionary *root = @{
        @"type" : type,
        @"interface" : iface,
        @"mac" : mac
    };
    networks = networks ? [networks arrayByAddingObject:root] : @[root];
}

- (void) addFileStorage: (NSString*) path type: (NSString*) type readOnly: (BOOL) ro {
    NSDictionary *root = @{
        @"type" : type,
        @"file" : path,
        @"readOnly" : ro ? @(YES) : @(NO)
    };
    storage = storage ? [storage arrayByAddingObject:root] : @[root];
}

- (void) addFileStorage: (NSString*) path type: (NSString*) type options: (NSArray*) options {
    NSDictionary *initial = @{
        @"type" : type,
        @"file" : path
    };
    NSMutableDictionary *root = [NSMutableDictionary dictionaryWithDictionary:initial];
    for (NSString *option in options)
        [root setValue: @(YES) forKey: option];
    storage = storage ? [storage arrayByAddingObject:root] : @[root];
}

void add_unlink_on_exit(const char *fn); /* from main.m - a bit hacky but more safe ... ;) */

/* this is not the most elegant design .. but we need to re-design the loading of options
   otherwise we really have to do it here so we can cover both the JSON specs as well
   as disks added by the storage API calls .. and we want to allow opt-outs, but for now
   it does the job we need: run ephemeral runners .. */
- (void) cloneAllStorage {
    if (storage) {
        NSMutableArray *cloned = [[NSMutableArray alloc] init];
        for (NSDictionary *d in storage) {
            NSDictionary *e = d;
            id tmp;
            NSString *path = d[@"file"];
            BOOL ro = (d[@"readOnly"] && [d[@"readOnly"] boolValue]) ? YES : NO;
            BOOL keep = (d[@"keep"] && [d[@"keep"] boolValue]) ? YES : NO;
            if ((tmp = d[@"type"]) && path && !ro && !keep) {
                if ([tmp isEqualToString:@"disk"] || [tmp isEqualToString:@"aux"]) {
                    NSString *target = [path stringByAppendingFormat: @"-clone-%ld", (long) getpid()];
                    NSLog(@" . cloning %@ to ephemeral %@", path, target);
                    if (clonefile([path UTF8String], [target UTF8String], 0)) {
                        NSString *desc = [NSString stringWithFormat:@"Failed to clone '%@' to '%@': [errno=%d] %s", path, target, errno, strerror(errno)];
                        @throw [NSException exceptionWithName:@"FSClone" reason:desc userInfo:nil];
                    }
                    add_unlink_on_exit([target UTF8String]);
                    NSMutableDictionary *emu = [[NSMutableDictionary alloc] initWithDictionary:d];
                    emu[@"file"] = target;
                    e = emu;
                }
            }
            [cloned addObject: e];
        }
        storage = cloned;
    }
}

/* this is a hack to allow booting macOS without config files, extract
   ECID from the aux disk. This is purely empirical so may break
   with future versions of macOS */
- (NSData*) inferMachineIdFromAuxFile: (NSString*) path {
#define ECID_SIG_LEN 7
#define ECID_LEN     8
    /* We're looking for (len = 4) "ECID" (type = 2) (len = 8) [<ecid>] */
    NSData *ecidSig = [NSData dataWithBytes:"\04ECID\02\010" length: ECID_SIG_LEN];
    NSFileHandle *f = [NSFileHandle fileHandleForReadingAtPath:path];
    NSError *err;
    uint64_t ecid = 0;
    if (!f)
        return nil;

    /* Attempt #1: use known location */
    if ([f seekToOffset: 0x6c804 error:&err]) {
        NSData *data = [f readDataUpToLength: ECID_SIG_LEN error:&err], *ecidData;
        if ([data isEqualToData: ecidSig] && /* match! */
            (ecidData = [f readDataUpToLength: ECID_LEN error:&err]) &&
            ecidData.length == ECID_LEN)
            memcpy(&ecid, ecidData.bytes, ECID_LEN);
    }

    /* Attempt #2: search and pray .. */
    if (!ecid && [f seekToOffset:0 error:&err]) { /* rewind */
        /* we're lazy, aux is typically 32M so do it in memory for simplicity */
        NSData *data = [f readDataToEndOfFileAndReturnError:&err];
        NSRange r;
        if (data && (r = [data rangeOfData: ecidSig options:0 range: NSMakeRange(0, data.length)]).length) {
            NSData *ecidData = [data subdataWithRange: NSMakeRange(r.location + r.length, ECID_LEN)];
            if (ecidData)
                memcpy(&ecid, ecidData.bytes, ECID_LEN);
        }
    }

    [f closeAndReturnError:&err];

    if (ecid) {
        ecid = CFSwapInt64HostToBig(ecid);
        NSDictionary *payload = @{
            @"ECID": @(ecid)
        };
        NSLog(@" + ECID obtained from aux file: 0x%016lx (%lu)", (unsigned long)ecid, (unsigned long)ecid);
        return [NSPropertyListSerialization dataWithPropertyList: payload
                                                          format: NSPropertyListBinaryFormat_v1_0
                                                         options: 0
                                                           error: &err];
    }
    NSLog(@"WARNING: ECID not known and cannot be inferred from auxiliary storage!");
    return nil;
}

- (instancetype) configure {
    if (!os)
        os = @"macos";
#ifdef MACOS_GUEST
    NSLog(@"%@ - configure for %@, OS: %@", self, self.restoreImage ? @"restore" : @"run", os);
    if ([os isEqualToString:@"macos"] && self.restoreImage) {
        VZMacOSRestoreImage *img = self.restoreImage;
        VZMacOSConfigurationRequirements *req = [img mostFeaturefulSupportedConfiguration];
        hardwareModelData = req.hardwareModel.dataRepresentation;
        
        NSLog(@"configure with restore, minimum requirements: %d CPUs, %lu RAM",
              (int)req.minimumSupportedCPUCount, (unsigned long)req.minimumSupportedMemorySize);
        
        if (!cpus)
            cpus = (int) req.minimumSupportedCPUCount;
        if (!ram)
            ram = (unsigned long)req.minimumSupportedMemorySize;
        
        if (req.minimumSupportedCPUCount > cpus)
            @throw [NSException exceptionWithName:@"VMConfig" reason:[NSString stringWithFormat:@"Image requires %d CPUs, but only %d configured", (int)req.minimumSupportedCPUCount, cpus] userInfo:nil];
        if (req.minimumSupportedMemorySize > ram)
            @throw [NSException exceptionWithName:@"VMConfig" reason:[NSString stringWithFormat:@"Image requires %lu bytes of RAM, but only %lu configured", (unsigned long)req.minimumSupportedMemorySize, ram] userInfo:nil];
    }
#else
    NSLog(@"%@ - configure for running, OS: %@", self, os);
#endif
    
    if (!cpus)
        @throw [NSException exceptionWithName:@"VMConfigCPU" reason:@"Number of CPUs not specified" userInfo:nil];
    if (!ram)
        @throw [NSException exceptionWithName:@"VMConfigRAM" reason:@"RAM size not specified" userInfo:nil];
    
#if MACOS_GUEST
    VZMacPlatformConfiguration *macPlatform = nil;
#endif
    
    if ([os isEqualToString:@"macos"]) {
#if MACOS_GUEST
        self.bootLoader = [[VZMacOSBootLoader alloc] init];
        macPlatform = [[VZMacPlatformConfiguration alloc] init];
#else
        @throw [NSException exceptionWithName:@"VMConfig" reason:@"This Mac does not support macOS as guest system" userInfo:nil];
#endif
    } else if ([os isEqualToString:@"linux"]) {
        NSURL *initrd = nil, *kernel = nil;
        NSString *params = nil;
        /* look for initrd */
        if (storage) for (NSDictionary *d in storage) {
            id tmp;
            NSString *path = d[@"file"];
            NSURL *url = nil;
            if ((tmp = d[@"url"])) url = [NSURL URLWithString:tmp];
            if ((tmp = d[@"type"]) && (url || path) && [tmp isEqualToString:@"initrd"]) {
                if (initrd)
                    fprintf(stderr, "WARNING: initrd specified more than once, using the first instance\n");
                else
                    initrd = url ? url : [NSURL fileURLWithPath:path];
            }
        }
        if (bootInfo) {
            NSString *kpath = bootInfo[@"kernel"];
            if (kpath)
                kernel = [NSURL fileURLWithPath:kpath];
            params = bootInfo[@"parameters"];
        }
        if (!kernel)
            @throw [NSException exceptionWithName:@"VMLinuxConfig" reason:@"Missing kernel path specification" userInfo:nil];
        NSLog(@" + Linux kernel %@", kernel);
        VZLinuxBootLoader *bootLoader = [[VZLinuxBootLoader alloc] initWithKernelURL: kernel];
        if (params) {
            bootLoader.commandLine = params;
            NSLog(@" + kernel boot parameters: %@", params);
        }
        if (initrd) {
            bootLoader.initialRamdiskURL = initrd;
            NSLog(@" + inital RAM disk: %@", initrd);
        }
        self.bootLoader = bootLoader;
    } else {
        NSLog(@"ERROR: unsupported os specification '%@', can only handle 'macos' and 'linux'.", os);
        @throw [NSException exceptionWithName:@"VMConfig" reason:@"Unsupported os specification" userInfo:nil];
    }
    
    if (use_serial) {
        NSFileHandle *readHandle = nil, *writeHandle = nil;
        if (pty) {
            int masterfd, slavefd;
            char *slavedevice;
            masterfd = posix_openpt(O_RDWR|O_NOCTTY);
            
            if (masterfd == -1
                || grantpt (masterfd) == -1
                || unlockpt (masterfd) == -1
                || (slavedevice = ptsname (masterfd)) == NULL) {
                perror("ERROR: cannot allocate pty");
                @throw [NSException exceptionWithName:@"PTYSetup" reason:@"Cannot allocate PTY for serial console" userInfo:nil];
            }
            /* FIXME: this is a bad hack - the VZ framework fails to spawn the VM if the tty is not connected. */
            printf("PTY allocated for serial link: %s\nPress <enter> here on stdin once connected to the tty to proceed.\n", slavedevice);
            static char tmp1[16];
            fgets(tmp1, sizeof(tmp1), stdin);
            writeHandle = readHandle = [[NSFileHandle alloc] initWithFileDescriptor: masterfd];
            //writeHandle = [[NSFileHandle alloc] initWithFileDescriptor: dup(masterfd)];
            ptyPath = [[NSString alloc] initWithUTF8String: slavedevice];
        } else {
            readHandle = [NSFileHandle fileHandleWithStandardInput];
            writeHandle = [NSFileHandle fileHandleWithStandardOutput];
        }
        VZVirtioConsoleDeviceSerialPortConfiguration *serial = [[VZVirtioConsoleDeviceSerialPortConfiguration alloc] init];
        VZFileHandleSerialPortAttachment *sata = [[VZFileHandleSerialPortAttachment alloc]
                                                  initWithFileHandleForReading: readHandle
                                                  fileHandleForWriting: writeHandle];
        serial.attachment = sata;
        self.serialPorts = @[ serial ];
    }
    
    self.entropyDevices = @[[[VZVirtioEntropyDeviceConfiguration alloc] init]];
    
    NSMutableArray *netList = [NSMutableArray arrayWithCapacity: networks ? [networks count] : 1];
    int net_count = 0;
    if (networks) for (NSDictionary *d in networks) {
        VZVirtioNetworkDeviceConfiguration *networkDevice = [[VZVirtioNetworkDeviceConfiguration alloc] init];
        NSString *type = d[@"type"];
        net_count++;
        /* default to NAT */
        if (!type || [type isEqualToString:@"nat"]) {
            NSLog(@" + NAT network");
            networkDevice.attachment = [[VZNATNetworkDeviceAttachment alloc] init];
        } else if (type && [type hasPrefix:@"br"]) {
            NSString *iface = d[@"interface"];
            VZBridgedNetworkInterface *brInterface = nil;
            NSArray *hostInterfaces = VZBridgedNetworkInterface.networkInterfaces;
            if ([hostInterfaces count] < 1)
                @throw [NSException exceptionWithName:@"VMConfigNet" reason: @"No host interfaces are available for bridging" userInfo:nil];
            if (iface) {
                for (VZBridgedNetworkInterface *hostIface in hostInterfaces)
                    if ([hostIface.identifier isEqualToString: iface]) {
                        brInterface = hostIface;
                        break;
                    }
            } else {
                brInterface = (VZBridgedNetworkInterface*) hostInterfaces[0];
                fprintf(stderr, "%s", [[NSString stringWithFormat: @"WARNING: no network interface specified for bridging, using first: %@ (%@)\n",
                                        brInterface.identifier, brInterface.localizedDisplayName] UTF8String]);
            }
            if (!brInterface) {
                fprintf(stderr, "%s", [[NSString stringWithFormat:@"ERROR: Network interface '%@' not found. Available interfaces for bridging:\n%@",
                                        iface, hostInterfaces] UTF8String]);
                @throw [NSException exceptionWithName:@"VMConfigNet" reason:
                        [NSString stringWithFormat:@"Network interface '%@' not found or not available", iface]
                                             userInfo:nil];
            }
            NSLog(@" + Bridged network to %@", brInterface);
            networkDevice.attachment = [[VZBridgedNetworkDeviceAttachment alloc] initWithInterface:brInterface];
            [netList addObject: networkDevice];
        } else if (type && [type isEqualToString:@"unix"]) {
            NSString *path = d[@"path"];
            int mtu = 1500;
            struct sockaddr_un caddr = {
                .sun_family = AF_UNIX,
            };
            struct sockaddr_un addr = {
                .sun_family = AF_UNIX,
                .sun_path = "/tmp/slirp"
            };
            NSFileHandle *fh;
            int sndbuflen = 2 * 1024 * 1024; /* for SO_RCVBUF/SO_SNDBUF - see below */
            int rcvbuflen = 6 * 1024 * 1024;
            int fd;
            
            id smtu = d[@"mtu"];
            if (smtu) {
                if ([smtu isKindOfClass:[NSString class]])
                    mtu = (int) ((NSString*)smtu).integerValue;
                else if ([smtu isKindOfClass:[NSNumber class]])
                    mtu = (int) ((NSNumber*)smtu).integerValue;
                if (mtu < 1500)
                    @throw [NSException exceptionWithName:@"VMConfigNet" reason:
                            [NSString stringWithFormat:@"MTU value %d is invalid, it must be at least 1500", mtu]
                                                 userInfo:nil];
            }
            
            NSLog(@" + UNIX domain socket network");
            
            if (path)
                strncpy(addr.sun_path, [path UTF8String], sizeof(addr.sun_path) - 1);
            
            const char *tsd = getenv("TMPSOCKDIR");
            NSString *tmpDir = (tsd && *tsd) ? [NSString stringWithUTF8String: tsd] : NSTemporaryDirectory();
            NSString *tmpSock = [NSString stringWithFormat: @"%@/macosvm.net.%d.%d", tmpDir, (int) getpid(), net_count];
            if ([tmpSock lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= sizeof(caddr.sun_path))
                @throw [NSException exceptionWithName:@"VMConfigNet" reason:
                        [NSString stringWithFormat:@"Temporary socket path '%@' is too long, consider setting TMPSOCKDIR to shorter path.", tmpSock]
                                             userInfo:nil];
            strcpy(caddr.sun_path, [tmpSock UTF8String]);
            { /* for security reasons we don't allow the target to be anything other
               that a previously created socket (especially not a link) */
                struct stat st;
                if (lstat(caddr.sun_path, &st) == 0) { /* target exists */
                    if ((st.st_mode & S_IFMT) != S_IFSOCK)
                        @throw [NSException exceptionWithName:@"VMConfigNet" reason:
                                [NSString stringWithFormat:@"Temporary socket path '%@' already exists and is not a socket.", tmpSock]
                                                     userInfo:nil];
                    /* ok, unlink it */
                    if (unlink(caddr.sun_path))
                        @throw [NSException exceptionWithName:@"VMConfigNet" reason:
                                [NSString stringWithFormat:@"Cannot remove stale temporary socket '%@': %s", tmpSock, strerror(errno)]
                                                     userInfo:nil];
                } /* if it doesn't exist, we're all good */
            }
            fd = socket(AF_UNIX, SOCK_DGRAM, 0);
            /* bind is mandatory */
            if (bind(fd, (struct sockaddr *)&caddr, sizeof(caddr)))
                @throw [NSException exceptionWithName:@"VMConfigNet" reason:
                        [NSString stringWithFormat:@"Could not bind UNIX socket to '%s': %s", caddr.sun_path, strerror(errno)]
                                             userInfo:nil];
            NSLog(@"   Bound to '%s', connecting to '%s'", caddr.sun_path, addr.sun_path);
            add_unlink_on_exit(caddr.sun_path);
            /* connect is optional for DGRAM, but fixes the peer so we force the desired target */
            if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)))
                @throw [NSException exceptionWithName:@"VMConfigNet" reason:
                        [NSString stringWithFormat:@"Could not connect to UNIX socket '%s': %s", addr.sun_path, strerror(errno)]
                                             userInfo:nil];
            
            /* according to VZFileHandleNetworkDeviceAttachment docs SO_RCVBUF has to be
             at least double of SO_SNDBUF, ideally 4x. Modern macOS have kern.ipc.maxsockbuf
             of 8Mb, so we try 2Mb + 6Mb first and fall back by halving */
            while (setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sndbuflen, sizeof(sndbuflen)) ||
                   setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &rcvbuflen, sizeof(rcvbuflen))) {
                sndbuflen /= 2;
                rcvbuflen /= 2;
                if (rcvbuflen < 128 * 1024) {
                    @throw [NSException exceptionWithName:@"VMConfigNet" reason:
                            [NSString stringWithFormat:@"Could not set socket buffer sizes: %s", strerror(errno)]
                                                 userInfo:nil];
                }
            }
            
            fh = [[NSFileHandle alloc] initWithFileDescriptor:fd];
            VZFileHandleNetworkDeviceAttachment *fhda = [[VZFileHandleNetworkDeviceAttachment alloc] initWithFileHandle:fh];
            if (mtu > 1500) {
#if (TARGET_OS_OSX && __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000)
                if (@available(macOS 13, *))
                    fhda.maximumTransmissionUnit = mtu;
                else
                    fprintf(stderr, "WARNING: your macOS does not support MTU changes, using default 1500\n");
#else
                fprintf(stderr, "WARNING: This build does not support MTU changes, using default 1500\n");
#endif
            }
            networkDevice.attachment = fhda;
        }
        NSString *macAddr = d[@"mac"];
        if (macAddr) {
            VZMACAddress *addr = [[VZMACAddress alloc] initWithString: macAddr];
            if (!addr) {
                @throw [NSException exceptionWithName:@"VMConfigNetworkError"
                                               reason:[NSString stringWithFormat:@"Invalid MAC address specification: '%@'", macAddr] userInfo:nil];
            }
            networkDevice.MACAddress = addr;
        } else {
            networkDevice.MACAddress = [VZMACAddress randomLocallyAdministeredAddress];
        }
        NSLog(@" + network: ether %@\n", [networkDevice.MACAddress string]);
        [netList addObject: networkDevice];
    }
    self.networkDevices = netList;
    
    if (@available(macOS 12, *)) {
        if (shares) {
            NSMutableArray *shDevs = [[NSMutableArray alloc] init];
            NSMutableArray *automountShares = [[NSMutableArray alloc] init];
            for (NSDictionary *d in shares) {
                id tmp;
                NSString *path = d[@"path"];
                NSString *volume = d[@"volume"];
                NSArray *paths = d[@"paths"];
                NSURL *url = nil;
                BOOL ro = (d[@"readOnly"] && [d[@"readOnly"] boolValue]) ? YES : NO;
                BOOL automount = (d[@"automount"] && [d[@"automount"] boolValue]) ? YES : NO;
                NSString *shareTag = @"macosvm";
                if (automount) {
                    BOOL canAutomount = NO;
#if (TARGET_OS_OSX && __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000)
                    if (@available(macOS 13, *)) {
                        shareTag = VZVirtioFileSystemDeviceConfiguration.macOSGuestAutomountTag;
                        canAutomount = YES;
                    }
#endif
                    if (!canAutomount) {
                        NSLog(@"WARNING: you macOS does NOT support automounts, setting the share name to 'automount', you have to use 'mount_virtiofs automount <directory>' in the guest OS\n");
                        shareTag = @"automount";
                        automount = NO;
                    } else {
                        [automountShares addObject:d];
                        continue;
                    }
                } else if (volume)
                    shareTag = volume;
                
                VZVirtioFileSystemDeviceConfiguration *shareCfg = [[VZVirtioFileSystemDeviceConfiguration alloc] initWithTag: shareTag];
                NSLog(@" + share, use mount_virtiofs '%@' <mountpoint> in guest OS\n", shareTag);
                if (path)
                    url = [NSURL fileURLWithPath:path];
                if ((tmp = d[@"url"]))
                    url = [NSURL URLWithString:tmp];
                if (path) {
                    VZSharedDirectory *directory = [[VZSharedDirectory alloc] initWithURL: url readOnly: ro];
                    NSLog(@"   sharing single %@ (%@)\n", url, ro ? @"read-only" : @"read-write");
                    shareCfg.share = [[VZSingleDirectoryShare alloc] initWithDirectory: directory];
                } else if (paths) {
                    NSMutableDictionary *dirs = [[NSMutableDictionary alloc] init];
                    for (NSString *path in paths) {
                        VZSharedDirectory *directory = [[VZSharedDirectory alloc] initWithURL: [NSURL fileURLWithPath: path] readOnly: ro];
                        NSLog(@"   sharing multi %@ (%@)\n", url, ro ? @"read-only" : @"read-write");
                        [dirs setObject: directory forKey:[path lastPathComponent]];
                    }
                    shareCfg.share = [[VZMultipleDirectoryShare alloc] initWithDirectories: dirs];
                }
                [shDevs addObject: shareCfg];
            }
#if (TARGET_OS_OSX && __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000)
            if (@available(macOS 13, *)) {
                if ([automountShares count] > 0) {
                    NSMutableDictionary *dirs = [[NSMutableDictionary alloc] init];
                    NSString *shareTag = VZVirtioFileSystemDeviceConfiguration.macOSGuestAutomountTag;
                    VZVirtioFileSystemDeviceConfiguration *shareCfg = [[VZVirtioFileSystemDeviceConfiguration alloc] initWithTag: shareTag];
                    for (NSDictionary *d in automountShares) {
                        id tmp;
                        NSString *path = d[@"path"];
                        NSArray *paths = d[@"paths"];
                        NSURL *url = nil;
                        BOOL ro = (d[@"readOnly"] && [d[@"readOnly"] boolValue]) ? YES : NO;
                        
                        NSLog(@" + automount share (in /Volumes/My Shared Files)\n");
                        
                        if (path)
                            url = [NSURL fileURLWithPath:path];
                        if ((tmp = d[@"url"]))
                            url = [NSURL URLWithString:tmp];
                        if (path) {
                            VZSharedDirectory *directory = [[VZSharedDirectory alloc] initWithURL: url readOnly: ro];
                            NSLog(@"   sharing single %@ (%@)\n", url, ro ? @"read-only" : @"read-write");
                            [dirs setObject: directory forKey:[path lastPathComponent]];
                        } else if (paths) {
                            for (NSString *path in paths) {
                                VZSharedDirectory *directory = [[VZSharedDirectory alloc] initWithURL: [NSURL fileURLWithPath: path] readOnly: ro];
                                NSLog(@"   sharing multi %@ (%@)\n", url, ro ? @"read-only" : @"read-write");
                                [dirs setObject: directory forKey:[path lastPathComponent]];
                            }
                            
                        }
                        
                    }
                    shareCfg.share = [[VZMultipleDirectoryShare alloc] initWithDirectories: dirs];
                    [shDevs addObject: shareCfg];
                }
            }
#endif

            
            self.directorySharingDevices = shDevs;
        }
    } else {
        if (shares)
            @throw [NSException exceptionWithName:@"VMConfigSharesError" reason:@"Your macOS does not support directory sharing, you need macOS 12 or higher." userInfo:nil];
    }
    
#ifdef MACOS_GUEST
    VZMacGraphicsDeviceConfiguration *graphics = [[VZMacGraphicsDeviceConfiguration alloc] init];
    NSMutableArray *disp = [NSMutableArray arrayWithCapacity:displays ? [displays count] : 1];
    if (displays) for (NSDictionary *d in displays) {
        int width = 2560, height = 1600, dpi = 200;
        id tmp;
        if ((tmp = d[@"width"]) && [tmp isKindOfClass:[NSNumber class]]) width = (int)[tmp integerValue];
        if ((tmp = d[@"height"]) && [tmp isKindOfClass:[NSNumber class]]) height = (int)[tmp integerValue];
        if ((tmp = d[@"dpi"]) && [tmp isKindOfClass:[NSNumber class]]) dpi = (int)[tmp integerValue];
        NSLog(@" + display: %d x %d @ %d", width, height, dpi);
        [disp addObject: [[VZMacGraphicsDisplayConfiguration alloc]
                          initWithWidthInPixels:width heightInPixels:height pixelsPerInch:dpi]];
    }
    graphics.displays = disp;
    self.graphicsDevices = @[graphics];
#endif
    
    self.keyboards = @[[[VZUSBKeyboardConfiguration alloc] init]];
    
#if (TARGET_OS_OSX && __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000 && defined(MACOS_GUEST))
    if (@available(macOS 13, *)) {
        if (macPlatform) self.pointingDevices = @[
            [[VZUSBScreenCoordinatePointingDeviceConfiguration alloc] init], /* < macOS 13 guest */
            [[VZMacTrackpadConfiguration alloc] init]]; /* macOS >= 13 guest */
    }
#endif
    if (!self.pointingDevices || [self.pointingDevices count] == 0)
        self.pointingDevices = @[[[VZUSBScreenCoordinatePointingDeviceConfiguration alloc] init]];
    
#if (TARGET_OS_OSX && __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000)
    if (@available(macOS 13, *)) if (spice) { /* SPICE-based clipboard sharing */
        VZVirtioConsoleDeviceConfiguration *consoleDevice = [[VZVirtioConsoleDeviceConfiguration alloc] init];
        VZVirtioConsolePortConfiguration *consolePort = [[VZVirtioConsolePortConfiguration alloc] init];
        consolePort.name = VZSpiceAgentPortAttachment.spiceAgentPortName;
        VZSpiceAgentPortAttachment *spiceAgent = [[VZSpiceAgentPortAttachment alloc] init];
        spiceAgent.sharesClipboard = YES;
        consolePort.attachment = spiceAgent;
        consoleDevice.ports[0] = consolePort;
        self.consoleDevices = @[ consoleDevice ];
    }
#endif
    
#ifdef MACOS_GUEST
    VZMacHardwareModel *hwm = hardwareModelData ? [[VZMacHardwareModel alloc] initWithDataRepresentation:hardwareModelData] : nil;
    
    if (macPlatform && !hardwareModelData) {
        fprintf(stderr, "WARNING: no hardware information found, using arm64 macOS 12.0.0 specs\n");
        hardwareModelData = [[NSData alloc] initWithBase64EncodedString: @"YnBsaXN0MDDTAQIDBAUGXxAZRGF0YVJlcHJlc2VudGF0aW9uVmVyc2lvbl8QD1BsYXRmb3JtVmVyc2lvbl8QEk1pbmltdW1TdXBwb3J0ZWRPUxQAAAAAAAAAAAAAAAAAAAABEAKjBwgIEAwQAAgPKz1SY2VpawAAAAAAAAEBAAAAAAAAAAkAAAAAAAAAAAAAAAAAAABt" options:0];
    }
#endif
    
    NSMutableArray *std = [NSMutableArray arrayWithCapacity:storage ? [storage count] : 1];
    if (storage) for (NSDictionary *d in storage) {
        id tmp;
        NSString *path = d[@"file"];
        NSURL *url = nil;
        BOOL ro = (d[@"readOnly"] && [d[@"readOnly"] boolValue]) ? YES : NO;
        if ((tmp = d[@"url"])) url = [NSURL URLWithString:tmp];
        if ((tmp = d[@"type"]) && (url || path)) {
            if ([tmp isEqualToString:@"disk"] || [tmp isEqualToString:@"usb"]) {
                NSError *err = nil;
                NSURL *imageURL = url ? url : [NSURL fileURLWithPath:path];
                NSLog(@" + %@ image %@ (%@)", tmp, imageURL, ro ? @"read-only" : @"read-write");
                VZDiskImageStorageDeviceAttachment *a = [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:imageURL readOnly:ro error:&err];
                if (err)
                    @throw [NSException exceptionWithName:@"VMConfigDiskStorageError" reason:[err description] userInfo:nil];
                if ([tmp isEqualToString:@"disk"])
                    [std addObject:[[VZVirtioBlockDeviceConfiguration alloc] initWithAttachment:a]];
                else {
#if (TARGET_OS_OSX && __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000)
                    if (@available(macOS 13, *))
                        [std addObject:[[VZUSBMassStorageDeviceConfiguration alloc] initWithAttachment:a]];
                    else
#endif
                        @throw [NSException exceptionWithName:@"VMConfigDiskStorageError" reason:@"USB storage is not supported by this macOS/build" userInfo:nil];
                }
            }
            if ([tmp isEqualToString:@"aux"]) {
                NSError *err = nil;
                NSURL *imageURL = url ? url : [NSURL fileURLWithPath:path];
                BOOL useExisting = url || (path && [[NSFileManager defaultManager] fileExistsAtPath:path]);
#ifdef MACOS_GUEST
                if (self.restoreImage)
                    useExisting = NO;
                if (macPlatform) {
                    NSLog(@" + %@ aux storage %@", useExisting ? @"existing" : @"new", path);
                    if (useExisting && path && !machineIdentifierData)
                        machineIdentifierData = [self inferMachineIdFromAuxFile: path];
                    VZMacAuxiliaryStorage *aux = useExisting ?
                    [[VZMacAuxiliaryStorage alloc] initWithContentsOfURL: imageURL] :
                    [[VZMacAuxiliaryStorage alloc] initCreatingStorageAtURL: imageURL hardwareModel:hwm options:VZMacAuxiliaryStorageInitializationOptionAllowOverwrite error:&err];
                    if (err)
                        @throw [NSException exceptionWithName:@"VMConfigAuxStorageError" reason:[err description] userInfo:nil];
                    macPlatform.auxiliaryStorage = aux;
                } else
#endif
                    NSLog(@"WARNING: auxiliary storage is only supported for macOS guests, ignoring\n");
            }
        }
    }
    self.storageDevices = std;
    
    if (audio) {
        NSLog(@" + audio");
        VZVirtioSoundDeviceConfiguration *soundDevice = [[VZVirtioSoundDeviceConfiguration alloc] init];
        VZVirtioSoundDeviceOutputStreamConfiguration *outputStream = [[VZVirtioSoundDeviceOutputStreamConfiguration alloc] init];
        outputStream.sink = [[VZHostAudioOutputStreamSink alloc] init];
        VZVirtioSoundDeviceInputStreamConfiguration *inputStream = [[VZVirtioSoundDeviceInputStreamConfiguration alloc] init];
        inputStream.source = [[VZHostAudioInputStreamSource alloc] init];
        soundDevice.streams = @[outputStream, inputStream];
        self.audioDevices = @[soundDevice];
    }
    
    if ([os isEqualToString:@"macos"]) {
#ifdef MACOS_GUEST
        if (hwm) macPlatform.hardwareModel = hwm;
        
        /* either load existing or create new one */
        VZMacMachineIdentifier *mid = [VZMacMachineIdentifier alloc];
        mid = (machineIdentifierData) ? [mid initWithDataRepresentation:machineIdentifierData] : [mid init];
        macPlatform.machineIdentifier = mid;
        if (!machineIdentifierData)
            machineIdentifierData = mid.dataRepresentation;
        
        self.platform = macPlatform;
#endif
    } else { /* generic platform */
        self.platform = [[VZGenericPlatformConfiguration alloc] init];
    }
    
    NSLog(@" + %d CPUs", (int) cpus);
    self.CPUCount = cpus;
    NSLog(@" + %lu RAM", ram);
    self.memorySize = ram;
    
    return self;
}

@end


@implementation VMInstance
{
    NSError *stopError;
}

- (instancetype) initWithSpec: (VMSpec*) spec_ {
    self = [super init];
    self.spec = [spec_ configure];
    stopError = nil;
    NSError *err = nil;
    [_spec validateWithError:&err];
    NSLog(@"validateWithError = %@", err ? err : @"OK");
    if (err)
        @throw [NSException exceptionWithName:@"VMConfigError" reason:[err description] userInfo:nil];
    //queue = dispatch_get_main_queue(); //dispatch_queue_create("macvm", DISPATCH_QUEUE_SERIAL);
    queue = dispatch_queue_create("macvm", DISPATCH_QUEUE_SERIAL);
    self.virtualMachine = [[VZVirtualMachine alloc] initWithConfiguration:_spec queue:queue];
    NSLog(@" init OK");
    return self;
}

- (void) start {
    dispatch_async(queue, ^{ [self start_ ]; });
}

- (void) performVM: (id) target selector: (SEL) aSelector withObject:(id)anArgument {
    dispatch_sync(queue, ^{
        NSLog(@" - on VM queue start");
        /* the selector is void, so no leaks, tell clang that ... */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [target performSelector:aSelector withObject:anArgument];
#pragma clang diagnostic pop
        NSLog(@" - on VM queue end");
    });
}

- (void) start_ {
    void (^completionHandler)(NSError *errorOrNil) = ^(NSError *err) {
        NSLog(@"start completed err=%@", err ? err : @"nil");
        if (err)
            @throw [NSException exceptionWithName:@"VMStartError" reason:[err description] userInfo:nil];
    };

#if (TARGET_OS_OSX && __MAC_OS_X_VERSION_MAX_ALLOWED >= 130000)
    /* recovery has been introduced in 13.0 */
    if (@available(macOS 13.0, *)) {
        VZMacOSVirtualMachineStartOptions *opts = [[VZMacOSVirtualMachineStartOptions alloc] init];
        opts.startUpFromMacOSRecovery = _spec->use_recovery;
        NSLog(@"starting macOS in %@ mode", _spec->use_recovery ? @"recovery" : @"normal");
        [_virtualMachine startWithOptions:opts completionHandler:completionHandler];
    } else
#endif
        /* macOS SDK <13.0 can only do normal start */
        [_virtualMachine startWithCompletionHandler:completionHandler];
}

- (void) stop_ {
    NSError *err = nil;
    BOOL res = [_virtualMachine requestStopWithError:&err];
    if (err) NSLog(@"VM.stop rejected with %@", err);
    NSLog(@"stop requested %@, err=%@", res ? @"OK" : @"FAIL", err ? err : @"nil");
    /* neither should trigger since the API defines that err much match the result */
    if (res)
        err = nil;
    else if (!err)
        err = [NSError errorWithDomain:@"VMInstance" code:1 userInfo:nil];
    stopError = err;
}

- (BOOL) stop {
    dispatch_sync(queue, ^{ [self stop_ ]; });
    return ! stopError;
}

@end

/* Local Variables:      */
/* c-basic-offset: 4     */
/* indent-tabs-mode: nil */
/* End:                  */
