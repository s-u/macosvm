#import <Foundation/Foundation.h>
#import <Virtualization/Virtualization.h>

@interface VMSpec : VZVirtualMachineConfiguration {
    NSData  *machineIdentifierData, *hardwareModelData;
    NSArray *storage;
    /* type: disk / aux / initrd
       file: / url:
       readOnly: true/false */
    NSArray *displays;
    /* width:  height:  dpi: */
    NSArray *networks;
    /* type: */
    NSString *os;
    /* macos / linux */
    NSDictionary *bootInfo;
    /* Linux: kernel, parameters */

    NSString *ptyPath; /* internally generated */
@public
    int cpus;
    unsigned long ram;
    BOOL audio, use_serial, pty, use_pl011, recovery, dfu;
}

@property (strong) VZMacOSRestoreImage *restoreImage;

- (instancetype) init;
- (NSError *) readFromJSON: (NSInputStream*) jsonStream;
- (NSError*) writeToJSON: (NSOutputStream*) jsonStream;
- (void) addFileStorage: (NSString*) path type: (NSString*) type readOnly: (BOOL) ro;
- (void) addFileStorage: (NSString*) path type: (NSString*) type options: (NSArray*) options;
- (void) addDefaults;
- (void) addDisplayWithWidth: (int) width height: (int) height dpi: (int) dpi;
- (void) addNetwork: (NSString*) type;
- (void) addNetwork: (NSString*) type interface: (NSString*) iface;
- (instancetype) configure;
- (void) cloneAllStorage;

@end

@interface _VZVirtualMachineStartOptions : NSObject

@property BOOL restartAction;
@property BOOL panicAction;
@property BOOL stopInIBootStage1;
@property BOOL stopInIBootStage2;
@property BOOL bootMacOSRecovery;
@property BOOL forceDFU;

@end

@interface VMInstance : NSObject
{
    @public
    dispatch_queue_t queue;
//    VZMacOSInstaller *installer;
}

@property (strong) VZVirtualMachine *virtualMachine;
@property (strong) VMSpec *spec;
@property (strong) _VZVirtualMachineStartOptions *options;

- (instancetype) initWithSpec: (VMSpec*) spec;
- (void) start;
- (BOOL) stop;
- (void) performVM: (id) target selector: (SEL) aSelector withObject:(nullable id)anArgument;

@end

@interface _VZPL011SerialPortConfiguration : VZSerialPortConfiguration
- (instancetype _Nonnull)init;
@end

@interface VZVirtualMachine()
- (void)_startWithOptions:(_VZVirtualMachineStartOptions *_Nonnull)options completionHandler:(void (^_Nonnull)(NSError * _Nullable errorOrNil))completionHandler;
@end
