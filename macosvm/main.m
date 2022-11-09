#import <Foundation/Foundation.h>

#import "VMInstance.h"

static const char *version = "0.1-4";

@interface App : NSObject <NSApplicationDelegate, NSWindowDelegate, VZVirtualMachineDelegate> {
@public
    NSWindow *window;
    VZVirtualMachineView *view;
    VMInstance *vm;
    VMSpec *spec;
    NSTimer *installProgressTimer;
    int tick;
}

@property BOOL useGUI;
@property (strong) NSString *configPath;
@property (strong) NSString *restorePath;
#ifdef MACOS_GUEST
@property (strong) VZMacOSInstaller *installer;
#endif

@end

@implementation App

- (instancetype) init {
    self = [super init];
    window = nil;
    view = nil;
    vm = nil;
    spec = nil;
    _configPath = nil;
    _restorePath = nil;
#ifdef MACOS_GUEST
    _installer = nil;
#endif
    tick = 0;
    installProgressTimer = nil;
    return self;
}

- (void)windowWillClose:(NSNotification *)notification {
    NSLog(@"Window will close");
}

/* IMPORTANT: delegate methods are called from VM's queue */
- (void)guestDidStopVirtualMachine:(VZVirtualMachine *)virtualMachine {
    NSLog(@"VM %@ guest stopped", virtualMachine);
    [NSApp performSelectorOnMainThread:@selector(terminate:) withObject:self waitUntilDone:NO];
}

- (void)virtualMachine:(VZVirtualMachine *)virtualMachine didStopWithError:(NSError *)error {
    NSLog(@"VM %@ didStopWithError: %@", virtualMachine, error);
    [NSApp performSelectorOnMainThread:@selector(terminate:) withObject:self waitUntilDone:NO];
}

- (void)virtualMachine:(VZVirtualMachine *)virtualMachine  networkDevice:(VZNetworkDevice *)networkDevice
attachmentWasDisconnectedWithError:(NSError *)error {
    NSLog(@"VM %@ networkDevice:%@ disconnected:%@", virtualMachine, networkDevice, error);
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self->spec addDefaults];
#ifdef MACOS_GUEST
    if (_restorePath) {
        NSLog(@"Restoring from %@", _restorePath);
        [VZMacOSRestoreImage loadFileURL:[NSURL fileURLWithPath:_restorePath] completionHandler:^(VZMacOSRestoreImage *img, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"  image load: %@", err ? err : @"OK");
                if (err)
                    @throw [NSException exceptionWithName:@"VMRestoreError" reason:[err description] userInfo:nil];
                self->spec.restoreImage = img;
                [self createVM:nil];
            });
        }];
    } else
#endif
        [self createVM: nil];
}

- (void) updateProgess: (id) object {
    const char ticks[] = "-\\|/";
#ifdef MACOS_GUEST
    NSProgress *progress = (_installer && _installer.progress) ? _installer.progress : nil;
    tick++;
    tick &= 3;
    if (progress)
        printf("\r [%c] Progress: %.1f%%\r", ticks[tick], [progress fractionCompleted] * 100.0);
    else
        printf("\r [%c] Progress: ?????\r", ticks[tick]);
    fflush(stdout);
#endif
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:NSStringFromSelector(@selector(fractionCompleted))])
        [self updateProgess: object];
    else
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void) installMacOS: (id) dummy {
#ifdef MACOS_GUEST
    // beats me why Installer doesn't take VZMacOSRestoreImage ..
    NSLog(@" installMacOS: from %@", _restorePath);
    self.installer = [[VZMacOSInstaller alloc] initWithVirtualMachine:vm.virtualMachine restoreImageURL:[NSURL fileURLWithPath:_restorePath]];
    [_installer.progress addObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted)) options:NSKeyValueObservingOptionInitial context:0];
    installProgressTimer = [NSTimer timerWithTimeInterval: 1.0 target:self selector:@selector(updateProgess:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:installProgressTimer forMode:NSRunLoopCommonModes];
    [self.installer installWithCompletionHandler:^(NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
	if (self->installProgressTimer) {
	    [self->installProgressTimer invalidate];
	    self->installProgressTimer = nil;
	}
        NSLog(@"  Installer done: %@", err ? err : @"OK");
        if (err)
            @throw [NSException exceptionWithName:@"MacOSInstall" reason:[err description] userInfo:nil];
        });
    }];
#endif
}

- (void) createVM: (id) dummy {
    @try {
        NSLog(@"Creating instance ...");
        vm = [[VMInstance alloc] initWithSpec:spec];
        VZVirtualMachine *vz = vm.virtualMachine;
        vz.delegate = self;

#ifdef MACOS_GUEST
        if (spec.restoreImage && _restorePath) {
            /* dump config */
            @try {
                NSLog(@"Save configuration to %@ ...", _configPath);
                NSOutputStream *ostr = [NSOutputStream outputStreamToFileAtPath:_configPath append:NO];
                [ostr open];
                [spec writeToJSON:ostr];
                [ostr close];
            }
            @catch (NSException *ex) {
                NSLog(@"WARNING: unable to save configuration to %@: %@", _configPath, [ex description]);
                printf("--- dumping configuration to stdout ---\n");
                NSOutputStream *ostr = [NSOutputStream outputStreamToFileAtPath:@"/dev/stdout" append:YES];
                [ostr open];
                [spec writeToJSON:ostr];
                [ostr close];
                printf("\n\n");
            }
        }
#endif

        if (self.useGUI) {
            NSLog(@"Create GUI");
            view = [[VZVirtualMachineView alloc] init];
            view.capturesSystemKeys = YES;
            view.virtualMachine = vz;
            NSRect rect = NSMakeRect(10, 10, 1024, 768);
            window = [[NSWindow alloc] initWithContentRect: rect
                                                 styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|
                      NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable//|NSTexturedBackgroundWindowMask
                                                   backing:NSBackingStoreBuffered defer:NO];
            [window setOpaque:NO];
            [window setDelegate: self];
            [window setContentView: view];
            [window setInitialFirstResponder: view];
            [window setTitle: @"VirtualMac"];

            if (![NSApp mainMenu]) { /* normally, there is no menu so we have to create it */
                NSLog(@"Create menu ...");
                NSMenu *menu, *mainMenu = [[NSMenu alloc] init];
                NSMenuItem *menuItem;

                menu = [[NSMenu alloc] initWithTitle:@"Window"];
                menuItem = [[NSMenuItem alloc] initWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"]; [menu addItem:menuItem];
                menuItem = [[NSMenuItem alloc] initWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""]; [menu addItem:menuItem];
                menuItem = [[NSMenuItem alloc] initWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"]; [menu addItem:menuItem];

               menuItem = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"]; [menu addItem:menuItem];
               menuItem = [[NSMenuItem alloc] initWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"]; [menu addItem:menuItem];

                menuItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
                [menuItem setSubmenu:menu];

                [mainMenu addItem:menuItem];
                [NSApp setMainMenu:mainMenu];
            }

            NSLog(@"Activate window...");
            [window makeKeyAndOrderFront: view];

            if (![[NSRunningApplication currentApplication] isActive]) {
                NSLog(@"Make application active");
                [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateAllWindows];
            }

            { /* we have to make us foreground process so we can receive keyboard
                 events - I know of no way that doesn't involve deprecated API .. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                void CPSEnableForegroundOperation(ProcessSerialNumber* psn);
                ProcessSerialNumber myProc;
                if (GetCurrentProcess(&myProc) == noErr)
                    CPSEnableForegroundOperation(&myProc);
#pragma clang diagnostic pop
            }
        }

#ifdef MACOS_GUEST
        if (spec.restoreImage && _restorePath) {
            NSLog(@"Restore requested, starting macOS installer from %@", _restorePath);
            NSLog(@"Installing macOS version %d.%d.%d (build %@)",
                  (int) spec.restoreImage.operatingSystemVersion.majorVersion,
                  (int) spec.restoreImage.operatingSystemVersion.minorVersion,
                  (int) spec.restoreImage.operatingSystemVersion.patchVersion,
                  spec.restoreImage.buildVersion);
            dispatch_async(vm->queue, ^{
                [self installMacOS:self];
            });
        } else {
#endif
            NSLog(@"Starting instnace...");
            [vm start];
#ifdef MACOS_GUEST
        }
#endif
    }
    @catch (NSException *ex){
        NSLog(@"Exception in VM init: %@", ex);
        [NSApp terminate:self];
    }
#ifdef TEST_STOP
    [self performSelector:@selector(timer:) withObject:self afterDelay:15.0];
#endif
    NSLog(@" - start done");
}

#ifdef TEST_STOP /* testing */
- (void) timer: (id) foo {
    dispatch_sync(vm->queue, ^{
    NSLog(@"INFO: canStart: %@, canPause: %@, canResume: %@, canRequestStop: %@, state: %d",
          vm.virtualMachine.canStart ? @"YES": @"NO",
          vm.virtualMachine.canPause ? @"YES" : @"NO",
          vm.virtualMachine.canResume ? @"YES" : @"NO",
          vm.virtualMachine.canRequestStop? @"YES" : @"NO",
          (int) vm.virtualMachine.state
          );
    });
    NSLog(@"timer triggered, requesting stop");
    [vm stop];
}
#endif

@end

static double parse_size(const char *val) {
    const char *eov;
    double vf = atof(val);
    if (vf < 0) {
        fprintf(stderr, "ERROR: invalid size '%s', may not be negative\n", val);
        return -1.0;
    }
    eov = val;
    while ((*eov >= '0' && *eov <= '9') || *eov == '.') eov++;
    switch (*eov) {
    case 'g': vf *= 1024.0;
    case 'm': vf *= 1024.0;
    case 'k': vf *= 1024.0; break;
    case 0: break;
    default:
        fprintf(stderr, "ERROR: invalid size qualifier '%c', must be k, m or g\n", *eov);
        return -1.0;
    }
    return vf;
}

#include <stdio.h>
#include <sys/stat.h>

/* simple low-level registry of files to unlink on exit */
#define MAX_UNLINKS 32
static char *unlink_me[MAX_UNLINKS];
void add_unlink_on_exit(const char *fn) {
    int i = 0;
    while (i < MAX_UNLINKS) {
        if (!unlink_me[i]) {
            unlink_me[i] = strdup(fn);
            return;
        }
        i++;
    }
    fprintf(stderr, "ERROR: too many ephemeral files, aborting\n");
    exit(1);
}
static void cleanup() {
    int i = 0;
    while (i < MAX_UNLINKS) {
        if (unlink_me[i]) {
            printf("INFO: removing ephemeral clone %s\n", unlink_me[i]);
            unlink(unlink_me[i]);
            free(unlink_me[i]);
            unlink_me[i] = 0;
        }
        i++;
    }
}

#include <signal.h>

static sig_t orig_INT;
static sig_t orig_TERM;
static sig_t orig_KILL;

static void sig_handler(int sig) {
    cleanup();
    /* restore original behavior */
    signal(sig, (sig == SIGINT) ? orig_INT : ((sig == SIGTERM) ? orig_TERM : ((sig == SIGKILL) ? orig_KILL : SIG_DFL)));
    raise(sig);
}

static void setup_unlink_handling() {
    /* regular termination */
    atexit(cleanup);
    /* signal termination */
    orig_INT = signal(SIGINT, sig_handler);
    orig_TERM= signal(SIGTERM, sig_handler);
    orig_KILL= signal(SIGKILL, sig_handler);
}

int main(int ac, char**av) {
    App *main = [[App alloc] init];
    VMSpec *spec = [[VMSpec alloc] init];
    main->spec = spec;
    BOOL create = NO, ephemeral = NO;
    NSString *configPath = nil;
    NSString *macOverride = nil;

    spec->use_serial = YES; /* we default to registering a serial console */
    /* FIXME: the parameters are a mess, in particular the config overrides
       everything that is defined there which is probably not a good idea.
       It would be better to have the parameters create a config and merge
       them instead in some way ... */
    int i = 0;
    while (++i < ac)
        if (av[i][0] == '-') {
            if (av[i][1] == 'g' || !strcmp(av[i], "--gui")) {
                main.useGUI = YES; continue;
            }
            if (!strcmp(av[i], "--ephemeral")) {
                ephemeral = YES; continue;
            }
            if (!strcmp(av[i], "--restore")) {
                if (++i >= ac) {
                    fprintf(stderr, "ERROR: %s missing file name", av[i-1]);
                    return 1;
                }
                printf("INFO: restore from %s\n", av[i]);
                main.restorePath = [NSString stringWithUTF8String:av[i]];
                if (![[NSFileManager defaultManager] fileExistsAtPath:main.restorePath]) {
                    fprintf(stderr, "ERROR: restore image '%s' not found\n", av[i]);
                    return 1;
                }
                create = YES; continue;
            }
            if (!strcmp(av[i], "--init")) {
                create = YES; continue;
            }
	    if (!strcmp(av[i], "--pty")) {
		spec->use_serial = spec->pty = YES; continue;
	    }
	    if (!strcmp(av[i], "--no-serial")) {
		spec->use_serial = NO; continue;
	    }
	    if (!strcmp(av[i], "--mac")) {
                if (++i >= ac) {
                    fprintf(stderr, "ERROR: %s missing MAC address", av[i-1]);
                    return 1;
                }
                macOverride = [NSString stringWithUTF8String: av[i]];
	    }
            if (!strcmp(av[i], "--vol")) {
                BOOL readOnly = NO, autoMount = NO;
                char *dop, *path = 0, *vol = 0;
                if (++i >= ac) {
                    fprintf(stderr, "ERROR: %s missing share specification", av[i-1]);
                    return 1;
                }
                path = av[i]; /* first is path */
                dop = strchr(path, ',');
                while (dop) {
                    *dop = 0; dop++;
                    if (!strncmp(dop, "name=", 5))
                        vol = dop + 5;
                    else if (!strncmp(dop, "automount", 9))
                        autoMount = YES;
                    else if (!strncmp(dop, "ro", 2))
                        readOnly = YES;
		    else if (!strncmp(dop, "rw", 2))
                        readOnly = NO;
		    else {
                        fprintf(stderr, "ERROR: invalid share option: '%s'\n", dop);
                        return 1;
		    }
                    dop = strchr(dop, ',');
                }
                if (autoMount)
                    [spec addAutomountDirectoryShare: [NSString stringWithUTF8String: path]
                                            readOnly: readOnly];
                else
                    [spec addDirectoryShare: [NSString stringWithUTF8String: path]
                                     volume: vol ? [NSString stringWithUTF8String:vol] : @"macosvm"
                                   readOnly: readOnly];
            }
            if (!strcmp(av[i], "--disk") || !strcmp(av[i], "--aux") || !strcmp(av[i], "--initrd")) {
                BOOL readOnly = NO;
                BOOL keep = NO;
                size_t create_size = 0;
                char *c, *dop;
                if (++i >= ac) {
                    fprintf(stderr, "ERROR: %s missing file name", av[i-1]);
                    return 1;
                }
                c = av[i];
                dop = strchr(c, ',');
                while (dop) {
                    *dop = 0; dop++;
                    if (!strncmp(dop, "ro", 2))
                        readOnly = YES;
                    else if (!strncmp(dop, "keep", 2))
                        keep = YES;
                    else if (!strncmp(dop, "size=", 5)) {
                        double sz = parse_size(dop + 5);
                        if (sz < 0)
                            return 1;
                        if (sz < 1024.0*1024.0*32.0) {
                            fprintf(stderr, "ERROR: invalid disk size, must be at least 32m\n");
                            return 1;
                        }
                        create_size = (size_t) sz;
                    } else {
                        fprintf(stderr, "ERROR: invalid disk option: '%s'\n", dop);
                        return 1;
                    }
                    dop = strchr(dop, ',');
                }
                if (create_size) {
                    FILE *f;
                    struct stat fst;
                    if (!stat(av[i], &fst)) {
                        fprintf(stderr, "ERROR: create size specified but file '%s' already exists\n",
                                av[i]);
                        return 1;
                    }
                    printf("INFO: creating new disk image %s with size %lu bytes\n", av[i], create_size);
                    f = fopen(av[i], "wb");
                    if (!f ||
                        fseek(f, create_size - 1, SEEK_SET) ||
                        fwrite("", 1, 1, f) != 1) {
                        fprintf(stderr, "ERROR: canot create disk file %s\n", av[i]);
                        return 1;
                    }
                    fclose(f);
                }
                NSMutableArray *options = [[NSMutableArray alloc] init];
                printf("INFO: add storage '%s' type '%s' %s %s\n", av[i],
                       av[i - 1] + 2, readOnly ? "read-only" : "read-write", keep ? "keep" : "");
                if (readOnly) [options addObject:@"readOnly"];
                if (keep) [options addObject:@"keep"];
                [spec addFileStorage:[NSString stringWithUTF8String:av[i]]
                                type:[NSString stringWithUTF8String:av[i - 1] + 2]
                             options:options];
                continue;
            }
            if (!strcmp(av[i], "--version")) {
                printf("macosvm %s\n\nCopyright (C) 2021 Simon Urbanek\nThere is NO warranty.\nLicenses: GPLv2 or GPLv3\n", version);
                return 0;
            }
            if (!strcmp(av[i], "--net")) {
                NSString *ifName = nil;
                NSString *type = nil;
                NSString *mac = nil;
                char *c, *dop;
                if (++i >= ac) {
                    fprintf(stderr, "ERROR: %s missing network specification", av[i-1]);
                    return 1;
                }
                c = av[i];
                dop = strchr(c, ':');
                if (dop) {
                    *dop = 0; dop++;
                    ifName = [NSString stringWithUTF8String:dop];
                }
                if (!strcmp(av[i], "nat")) {
                    type = @"nat";
                    if (ifName) {
                        mac = ifName;
                        ifName = nil;
                    }
                    printf("INFO: add NAT network %s%s\n",
                           mac ? "with MAC address " : "(random MAC address)",
                           mac ? [mac UTF8String] : "");
                } else if (!strncmp(av[i], "br", 2)) {
                    type = @"bridge";
                    printf("INFO: add bridged network %s%s\n",
                           ifName ? "on interface " : "(no interface specified!)",
                           ifName ? [ifName UTF8String] : "");
                } else {
                    fprintf(stderr, "ERROR: invalid network specification '%s'\n", av[i]);
                    return 1;
                }

                if (ifName)
                    [spec addNetwork:type interface:ifName];
		else if (mac)
		    [spec addNetwork:type mac:mac];
                else
                    [spec addNetwork:type];
                continue;
            }
            switch(av[i][1]) {
                case 'h': printf("\n\
 Usage: %s [-g|--[no-]gui] [--[no-]audio] [--restore <path>] [--ephemeral]\n\
           [--disk <path>[,ro][,size=<spec>][,keep]] [--aux <path>]\n\
           [--vol <path>[,ro][,{name=<name>|automount}]]\n\
           [--net <spec>] [--mac <addr>] [-c <cpu>] [-m <ram>]\n\
           [--no-serial] [--pty]   <config.json>\n\
        %s --version\n\
        %s -h\n\
\n\
 --restore requires path to ipsw image and will create aux as well as the configuration file.\n\
 If no CPU/RAM is specified then image's minimal settings are used.\n\
\n\
 If no --restore is performed then settings are read from the configuration file\n\
 and only --gui / --audio options are honored.\n\
 Size specifications allow suffix k, m and g for the powers of 1024.\n\
\n\
 Network specification is <type>[:<options>] where <type> is either\n\
 nat or br. For nat <options> is a MAC address to assign to the interface,\n\
 for br it is the interface to bridge (requires special entitlement!).\n\
 Note that the --mac option is special and will override the first interface\n\
 from the configuration file and/or --net (typically used with --ephemeral).\n\
\n\
 Examples:\n\
 # create a new VM with 32Gb disk image and macOS 12:\n\
 %s --disk disk.img,size=32g --aux aux.img --restore UniversalMac_12.0.1_21A559_Restore.ipsw vm.json\n\
 # start the created image with GUI:\n\
 %s -g vm.json\n\
\n\
 Experimental, use at your own risk!\n\
\n", av[0], av[0], av[0], av[0], av[0]); return 0;
                case 'c':
                    if (av[i][2]) spec->cpus = atoi(av[i] + 2); else {
                        if (++i >= ac) {
                            fprintf(stderr, "ERROR: %s missing CPU count\n", av[i - 1]);
                            return 1;
                        }
                        spec->cpus = atoi(av[i]);
                        printf("INFO: CPUs: %d\n", spec->cpus);
                    }
                    if (spec->cpus < 1) {
                        fprintf(stderr, "ERROR: invaild number of CPUs\n");
                        return 1;
                    }
                    break;
                case 'r':
                {
                    char *val;
                    if (av[i][2]) val = av[i] + 2; else {
                        if (++i >= ac) {
                            fprintf(stderr, "ERROR: %s missing RAM specification\n", av[i - 1]);
                            return 1;
                        }
                        val = av[i];
                    }
                    double vf = parse_size(val);
                    if (vf < 0)
                        return 1;
                    if (vf < 1024.0*1024.0*64.0) {
                        fprintf(stderr, "ERROR: invalid RAM size, must be at least 64m\n");
                        return 1;
                    }
                    spec->ram = (unsigned long) vf;
                    printf("INFO: RAM %lu\n", spec->ram);
                    break;
                } /* -r */
            }
            if (av[i][1] == '-') {
                if (!strcmp(av[i], "--no-gui")) { main.useGUI = NO; continue; }
                if (!strcmp(av[i], "--no-audio")) { spec->audio = NO; continue; }
                if (!strcmp(av[i], "--audio")) { spec->audio = YES; continue; }
            }
        } else {
            if (configPath) {
                fprintf(stderr, "ERROR: configuration path can only be specified once\n");
                return 1;
            }
            configPath = [NSString stringWithUTF8String:av[i]];
            @try {
                NSInputStream *istr = [NSInputStream inputStreamWithFileAtPath:configPath];
                [istr open];
                if ([istr streamError]) {
                    if (!create) {
                        NSLog(@"Cannot open '%@': %@", configPath, [istr streamError]);
                        @throw [NSException exceptionWithName:@"ConfigError" reason:[[istr streamError] description] userInfo:nil];
                    }
                } else {
                    [spec readFromJSON:istr];
                }
                [istr close];
            }
            @catch (NSException *ex) {
                NSLog(@"ERROR: %@", [ex description]);
                return 1;
            }
        }

    if (create && !configPath) {
        fprintf(stderr, "\nERROR: no configuration path supplied, try -h for help\n");
        return 1;
    }
    main.configPath = configPath;

    if (macOverride)
	[spec setPrimaryMAC: macOverride];

    if (ephemeral) {
        /* register the callback first such that if soemthing fails in the middle
           the already created clones can be unlinked */
        setup_unlink_handling();
        [spec cloneAllStorage];
    }

    [NSApplication sharedApplication];
    NSApp.delegate = main;

    [NSApp run];
    return 0;
}
