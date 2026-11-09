// KKit's Now Playing helper.
//
// Since macOS 15.4, MediaRemote only gives Now Playing information to Apple's own
// processes. This library is loaded into /usr/bin/perl (an Apple process) by the
// one-line script in MediaRemoteNowPlayingService.swift, which calls
// `kkit_mediaremote_stream`. It then:
//
//   - writes one JSON object per line to stdout whenever what's playing changes:
//       {"type":"ready"}                       MediaRemote loaded
//       {"type":"unavailable","reason":"…"}    it didn't (then exits)
//       {"type":"none"}                        nothing is playing
//       {"type":"info","title":…, …}           see `writeInfo`
//   - reads commands, one per line, from stdin: play, pause, toggle, next, previous,
//     seek <seconds>
//   - exits when stdin closes (KKit quit or stopped listening).
//
// It never touches KKit's process; KKit only reads its output.

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef void (*MRRegisterFunction)(dispatch_queue_t queue);
typedef void (*MRGetInfoFunction)(dispatch_queue_t queue, void (^handler)(CFDictionaryRef info));
typedef void (*MRGetIsPlayingFunction)(dispatch_queue_t queue, void (^handler)(Boolean playing));
typedef void (*MRGetPIDFunction)(dispatch_queue_t queue, void (^handler)(int pid));
typedef void (*MRGetClientFunction)(dispatch_queue_t queue, void (^handler)(id client));
typedef CFStringRef (*MRClientStringFunction)(id client);
typedef Boolean (*MRSendCommandFunction)(int command, CFDictionaryRef options);
typedef void (*MRSetElapsedTimeFunction)(double seconds);

// MRMediaRemoteCommand values.
enum {
    KKMRCommandPlay = 0,
    KKMRCommandPause = 1,
    KKMRCommandTogglePlayPause = 2,
    KKMRCommandNextTrack = 4,
    KKMRCommandPreviousTrack = 5,
};

static MRRegisterFunction kkRegister;
static MRGetInfoFunction kkGetInfo;
static MRGetIsPlayingFunction kkGetIsPlaying;
static MRGetPIDFunction kkGetPID;
static MRGetClientFunction kkGetClient;
static MRClientStringFunction kkClientBundleID;
static MRClientStringFunction kkClientParentBundleID;
static MRSendCommandFunction kkSendCommand;
static MRSetElapsedTimeFunction kkSetElapsedTime;
static void *kkMediaRemote;

static BOOL kkRefreshPending = NO;
static NSData *kkLastArtwork = nil;
static NSMutableData *kkInput = nil;
static dispatch_source_t kkInputSource = nil;

/// A MediaRemote string constant, or its name (they're the same string) if the symbol is missing.
static NSString *KKConstant(const char *name) {
    if (kkMediaRemote != NULL) {
        CFStringRef *symbol = (CFStringRef *)dlsym(kkMediaRemote, name);
        if (symbol != NULL && *symbol != NULL) {
            return (__bridge NSString *)*symbol;
        }
    }
    return [NSString stringWithUTF8String:name];
}

static void KKWriteLine(NSDictionary *object) {
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (data == nil) {
        return;
    }
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static NSString *KKString(id value) {
    if ([value isKindOfClass:[NSString class]] && [(NSString *)value length] > 0) {
        return value;
    }
    return nil;
}

static NSNumber *KKNumber(id value) {
    if ([value isKindOfClass:[NSNumber class]]) {
        return value;
    }
    return nil;
}

static void KKWriteInfo(NSDictionary *info, BOOL playing, int pid, NSString *bundleID) {
    NSString *title = KKString(info[KKConstant("kMRMediaRemoteNowPlayingInfoTitle")]);
    if (title == nil) {
        kkLastArtwork = nil;
        KKWriteLine(@{ @"type": @"none" });
        return;
    }
    NSMutableDictionary *line = [NSMutableDictionary dictionary];
    line[@"type"] = @"info";
    line[@"title"] = title;
    line[@"playing"] = @(playing);
    NSString *artist = KKString(info[KKConstant("kMRMediaRemoteNowPlayingInfoArtist")]);
    if (artist != nil) {
        line[@"artist"] = artist;
    }
    NSString *album = KKString(info[KKConstant("kMRMediaRemoteNowPlayingInfoAlbum")]);
    if (album != nil) {
        line[@"album"] = album;
    }
    NSNumber *duration = KKNumber(info[KKConstant("kMRMediaRemoteNowPlayingInfoDuration")]);
    if (duration != nil) {
        line[@"duration"] = duration;
    }
    NSNumber *elapsed = KKNumber(info[KKConstant("kMRMediaRemoteNowPlayingInfoElapsedTime")]);
    if (elapsed != nil) {
        line[@"elapsed"] = elapsed;
    }
    NSNumber *rate = KKNumber(info[KKConstant("kMRMediaRemoteNowPlayingInfoPlaybackRate")]);
    if (rate != nil) {
        line[@"rate"] = rate;
    }
    id timestamp = info[KKConstant("kMRMediaRemoteNowPlayingInfoTimestamp")];
    if ([timestamp isKindOfClass:[NSDate class]]) {
        line[@"timestamp"] = @([(NSDate *)timestamp timeIntervalSince1970]);
    } else {
        line[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    }
    if (pid > 0) {
        line[@"pid"] = @(pid);
    }
    if (bundleID != nil) {
        line[@"bundleID"] = bundleID;
    }
    id artwork = info[KKConstant("kMRMediaRemoteNowPlayingInfoArtworkData")];
    if ([artwork isKindOfClass:[NSData class]] && [(NSData *)artwork length] > 0) {
        if (kkLastArtwork != nil && [kkLastArtwork isEqualToData:artwork]) {
            // KKit keeps the artwork it already has.
            line[@"artworkUnchanged"] = @YES;
        } else {
            kkLastArtwork = [artwork copy];
            line[@"artwork"] = [(NSData *)artwork base64EncodedStringWithOptions:0];
        }
    } else {
        kkLastArtwork = nil;
    }
    KKWriteLine(line);
}

static void KKRefresh(void) {
    kkRefreshPending = NO;
    dispatch_queue_t queue = dispatch_get_main_queue();
    kkGetInfo(queue, ^(CFDictionaryRef cfInfo) {
        NSDictionary *info = cfInfo != NULL ? [(__bridge NSDictionary *)cfInfo copy] : @{};
        void (^finish)(BOOL, int) = ^(BOOL playing, int pid) {
            if (kkGetClient == NULL) {
                KKWriteInfo(info, playing, pid, nil);
                return;
            }
            kkGetClient(queue, ^(id client) {
                NSString *bundleID = nil;
                if (client != nil) {
                    // A browser's web content reports for the browser.
                    if (kkClientParentBundleID != NULL) {
                        bundleID = KKString((__bridge NSString *)kkClientParentBundleID(client));
                    }
                    if (bundleID == nil && kkClientBundleID != NULL) {
                        bundleID = KKString((__bridge NSString *)kkClientBundleID(client));
                    }
                }
                KKWriteInfo(info, playing, pid, bundleID);
            });
        };
        void (^withPlaying)(BOOL) = ^(BOOL playing) {
            if (kkGetPID == NULL) {
                finish(playing, 0);
                return;
            }
            kkGetPID(queue, ^(int pid) {
                finish(playing, pid);
            });
        };
        if (kkGetIsPlaying == NULL) {
            NSNumber *rate = KKNumber(info[KKConstant("kMRMediaRemoteNowPlayingInfoPlaybackRate")]);
            withPlaying(rate != nil && rate.doubleValue > 0);
            return;
        }
        kkGetIsPlaying(queue, ^(Boolean playing) {
            withPlaying(playing ? YES : NO);
        });
    });
}

/// Notifications come in bursts; refresh once per burst.
static void KKScheduleRefresh(void) {
    if (kkRefreshPending) {
        return;
    }
    kkRefreshPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        KKRefresh();
    });
}

static void KKHandleCommand(NSString *line) {
    NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return;
    }
    if ([trimmed hasPrefix:@"seek "]) {
        if (kkSetElapsedTime != NULL) {
            kkSetElapsedTime([[trimmed substringFromIndex:5] doubleValue]);
        }
        KKScheduleRefresh();
        return;
    }
    int command = -1;
    if ([trimmed isEqualToString:@"play"]) {
        command = KKMRCommandPlay;
    } else if ([trimmed isEqualToString:@"pause"]) {
        command = KKMRCommandPause;
    } else if ([trimmed isEqualToString:@"toggle"]) {
        command = KKMRCommandTogglePlayPause;
    } else if ([trimmed isEqualToString:@"next"]) {
        command = KKMRCommandNextTrack;
    } else if ([trimmed isEqualToString:@"previous"]) {
        command = KKMRCommandPreviousTrack;
    } else if ([trimmed isEqualToString:@"refresh"]) {
        KKScheduleRefresh();
        return;
    }
    if (command >= 0 && kkSendCommand != NULL) {
        kkSendCommand(command, NULL);
    }
}

static void KKReadInput(void) {
    char buffer[1024];
    ssize_t count = read(STDIN_FILENO, buffer, sizeof(buffer));
    if (count <= 0) {
        // KKit closed the pipe.
        exit(0);
    }
    [kkInput appendBytes:buffer length:(NSUInteger)count];
    while (YES) {
        const char *bytes = kkInput.bytes;
        NSUInteger length = kkInput.length;
        const char *newline = memchr(bytes, '\n', length);
        if (newline == NULL) {
            break;
        }
        NSUInteger lineLength = (NSUInteger)(newline - bytes);
        NSString *line = [[NSString alloc] initWithBytes:bytes length:lineLength encoding:NSUTF8StringEncoding];
        [kkInput replaceBytesInRange:NSMakeRange(0, lineLength + 1) withBytes:NULL length:0];
        if (line != nil) {
            KKHandleCommand(line);
        }
    }
}

static BOOL KKLoadMediaRemote(void) {
    kkMediaRemote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (kkMediaRemote == NULL) {
        return NO;
    }
    kkRegister = (MRRegisterFunction)dlsym(kkMediaRemote, "MRMediaRemoteRegisterForNowPlayingNotifications");
    kkGetInfo = (MRGetInfoFunction)dlsym(kkMediaRemote, "MRMediaRemoteGetNowPlayingInfo");
    kkGetIsPlaying = (MRGetIsPlayingFunction)dlsym(kkMediaRemote, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    kkGetPID = (MRGetPIDFunction)dlsym(kkMediaRemote, "MRMediaRemoteGetNowPlayingApplicationPID");
    kkGetClient = (MRGetClientFunction)dlsym(kkMediaRemote, "MRMediaRemoteGetNowPlayingClient");
    kkClientBundleID = (MRClientStringFunction)dlsym(kkMediaRemote, "MRNowPlayingClientGetBundleIdentifier");
    kkClientParentBundleID = (MRClientStringFunction)dlsym(kkMediaRemote, "MRNowPlayingClientGetParentAppBundleIdentifier");
    kkSendCommand = (MRSendCommandFunction)dlsym(kkMediaRemote, "MRMediaRemoteSendCommand");
    kkSetElapsedTime = (MRSetElapsedTimeFunction)dlsym(kkMediaRemote, "MRMediaRemoteSetElapsedTime");
    return kkRegister != NULL && kkGetInfo != NULL;
}

/// Called by perl as an XSUB (`void f(PerlInterpreter *, CV *)`). Never returns.
__attribute__((visibility("default")))
void kkit_mediaremote_stream(void *interpreter, void *cv) {
    (void)interpreter;
    (void)cv;
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        if (!KKLoadMediaRemote()) {
            KKWriteLine(@{ @"type": @"unavailable", @"reason": @"MediaRemote isn't available on this Mac." });
            exit(0);
        }
        kkInput = [NSMutableData data];

        kkInputSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(kkInputSource, ^{
            KKReadInput();
        });
        dispatch_resume(kkInputSource);

        NSArray<NSString *> *names = @[
            KKConstant("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            KKConstant("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
            KKConstant("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
        ];
        for (NSString *name in names) {
            [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification *note) {
                (void)note;
                KKScheduleRefresh();
            }];
        }
        kkRegister(dispatch_get_main_queue());
        KKWriteLine(@{ @"type": @"ready" });
        KKScheduleRefresh();

        // Keeps the main run loop (and with it the main queue) alive.
        [[NSRunLoop mainRunLoop] addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
    }
    CFRunLoopRun();
    exit(0);
}
