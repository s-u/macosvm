#import "VMInstance.h"

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
    _restoreImage = nil;
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
    return nil;
}

- (NSError*) writeToJSON: (NSOutputStream*) jsonStream {
    NSDictionary *src = @{
        @"version": @1,
        @"os" : os ? os : @"macos",
        @"cpus": [NSNumber numberWithInteger: cpus],
        @"ram": [NSNumber numberWithUnsignedLong: ram],
        @"storage" : storage ? storage : [NSArray array],
        @"audio" : audio ? @(YES) : @(NO)
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

- (void) addNetwork: (NSString*) type {
    NSDictionary *root = @{
        @"type" : type
    };
    networks = networks ? [networks arrayByAddingObject:root] : @[root];
}

- (void) addNetwork: (NSString*) type interface: (NSString*) iface {
    NSDictionary *root = @{
        @"type" : type,
        @"interface" : iface
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
        [root addObject: @(YES) forKey: option];
    storage = storage ? [storage arrayByAddingObject:root] : @[root];
}

#include <sys/clonefile.h>
#include <unistd.h>
#include <sys/errno.h>

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

    if (!cpus)
        @throw [NSException exceptionWithName:@"VMConfigCPU" reason:@"Number of CPUs not specified" userInfo:nil];
    if (!ram)
        @throw [NSException exceptionWithName:@"VMConfigRAM" reason:@"RAM size not specified" userInfo:nil];

    if ([os isEqualToString:@"macos"]) {
        self.bootLoader = [[VZMacOSBootLoader alloc] init];
    } else {
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
    }

    self.entropyDevices = @[[[VZVirtioEntropyDeviceConfiguration alloc] init]];

    NSMutableArray *netList = [NSMutableArray arrayWithCapacity: networks ? [networks count] : 1];
    if (networks) for (NSDictionary *d in networks) {
            VZVirtioNetworkDeviceConfiguration *networkDevice = [[VZVirtioNetworkDeviceConfiguration alloc] init];
            NSString *type = d[@"type"];
            if (type && [type isEqualToString:@"nat"]) {
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
            } else
                @throw [NSException exceptionWithName:@"VMConfigNet" reason: type ? @"Missing type in network specification" : @"Unsupported type in network specification" userInfo:nil];
            [netList addObject: networkDevice];
    }
    self.networkDevices = netList;

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
    self.keyboards = @[[[VZUSBKeyboardConfiguration alloc] init]];
    self.pointingDevices = @[[[VZUSBScreenCoordinatePointingDeviceConfiguration alloc] init]];

    VZMacPlatformConfiguration *platform = [[VZMacPlatformConfiguration alloc] init];

    if (!hardwareModelData) {
        fprintf(stderr, "WARNING: no hardware information found, using arm64 macOS 12.0.0 specs\n");
        hardwareModelData = [[NSData alloc] initWithBase64EncodedString: @"YnBsaXN0MDDTAQIDBAUGXxAZRGF0YVJlcHJlc2VudGF0aW9uVmVyc2lvbl8QD1BsYXRmb3JtVmVyc2lvbl8QEk1pbmltdW1TdXBwb3J0ZWRPUxQAAAAAAAAAAAAAAAAAAAABEAKjBwgIEAwQAAgPKz1SY2VpawAAAAAAAAEBAAAAAAAAAAkAAAAAAAAAAAAAAAAAAABt" options:0];
    }

    VZMacHardwareModel *hwm = hardwareModelData ? [[VZMacHardwareModel alloc] initWithDataRepresentation:hardwareModelData] : nil;

    NSMutableArray *std = [NSMutableArray arrayWithCapacity:storage ? [storage count] : 1];
    if (storage) for (NSDictionary *d in storage) {
        id tmp;
        NSString *path = d[@"file"];
        NSURL *url = nil;
        BOOL ro = (d[@"readOnly"] && [d[@"readOnly"] boolValue]) ? YES : NO;
        if ((tmp = d[@"url"])) url = [NSURL URLWithString:tmp];
        if ((tmp = d[@"type"]) && (url || path)) {
            if ([tmp isEqualToString:@"disk"]) {
                NSError *err = nil;
                NSURL *imageURL = url ? url : [NSURL fileURLWithPath:path];
                NSLog(@" + disk image %@ (%@)", imageURL, ro ? @"read-only" : @"read-write");
                VZDiskImageStorageDeviceAttachment *a = [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:imageURL readOnly:ro error:&err];
                if (err)
                    @throw [NSException exceptionWithName:@"VMConfigDiskStorageError" reason:[err description] userInfo:nil];
                [std addObject:[[VZVirtioBlockDeviceConfiguration alloc] initWithAttachment:a]];
            }
            if ([tmp isEqualToString:@"aux"]) {
                NSError *err = nil;
                NSURL *imageURL = url ? url : [NSURL fileURLWithPath:path];
                BOOL useExisting = url || (path && [[NSFileManager defaultManager] fileExistsAtPath:path]);
                if (self.restoreImage)
                    useExisting = NO;
                NSLog(@" + %@ aux storage %@", useExisting ? @"existing" : @"new", path);
                if (useExisting && path && !machineIdentifierData)
                    machineIdentifierData = [self inferMachineIdFromAuxFile: path];
                VZMacAuxiliaryStorage *aux = useExisting ?
                [[VZMacAuxiliaryStorage alloc] initWithContentsOfURL: imageURL] :
                [[VZMacAuxiliaryStorage alloc] initCreatingStorageAtURL: imageURL hardwareModel:hwm options:VZMacAuxiliaryStorageInitializationOptionAllowOverwrite error:&err];
                if (err)
                    @throw [NSException exceptionWithName:@"VMConfigAuxStorageError" reason:[err description] userInfo:nil];
                platform.auxiliaryStorage = aux;
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

    if (hwm) platform.hardwareModel = hwm;

    /* either load existing or create new one */
    VZMacMachineIdentifier *mid = [VZMacMachineIdentifier alloc];
    mid = (machineIdentifierData) ? [mid initWithDataRepresentation:machineIdentifierData] : [mid init];
    platform.machineIdentifier = mid;
    if (!machineIdentifierData)
        machineIdentifierData = mid.dataRepresentation;

    self.platform = platform;

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
    [_virtualMachine startWithCompletionHandler:^(NSError *err) {
        NSLog(@"start completed err=%@", err ? err : @"nil");
        if (err)
            @throw [NSException exceptionWithName:@"VMStartError" reason:[err description] userInfo:nil];
    }];
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
