// Runs inside /usr/bin/perl (an Apple platform binary), which macOS still lets read the system
// Now Playing info. NotchDeck launches `perl mediaremote.pl <this dylib> stream|send …` and reads
// one JSON object per line from stdout.
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <dlfcn.h>
#include <CommonCrypto/CommonDigest.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef NSString *(*ClientBundleFn)(id);
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*SendFn)(int, NSDictionary *);
typedef void (*SetElapsedFn)(double);

static void *mr;
static GetInfoFn getInfo;
static GetPlayingFn getPlaying;
static GetClientFn getClient;
static ClientBundleFn clientBundle;
static ClientBundleFn clientParentBundle;
static NSString *lastArtworkHash;

static void load(void) {
    mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    getInfo = (GetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getPlaying = (GetPlayingFn)dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getClient = (GetClientFn)dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    clientBundle = (ClientBundleFn)dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    clientParentBundle = (ClientBundleFn)dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
}

static void emit(NSDictionary *object) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static NSString *sha(NSData *data) {
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *s = [NSMutableString string];
    for (int i = 0; i < 8; i++) [s appendFormat:@"%02x", digest[i]];
    return s;
}

static void report(void) {
    dispatch_queue_t q = dispatch_get_main_queue();
    getInfo(q, ^(NSDictionary *info) {
        getPlaying(q, ^(Boolean playing) {
            void (^finish)(NSString *, NSString *) = ^(NSString *bundle, NSString *parent) {
                NSMutableDictionary *out = [NSMutableDictionary dictionary];
                out[@"playing"] = @(playing);
                if (bundle) out[@"bundle"] = bundle;
                // A web page playing media reports the browser as its parent.
                if (parent) out[@"parentBundle"] = parent;
                if (info) {
                    id v;
                    if ((v = info[@"kMRMediaRemoteNowPlayingInfoTitle"])) out[@"title"] = v;
                    if ((v = info[@"kMRMediaRemoteNowPlayingInfoArtist"])) out[@"artist"] = v;
                    if ((v = info[@"kMRMediaRemoteNowPlayingInfoAlbum"])) out[@"album"] = v;
                    if ((v = info[@"kMRMediaRemoteNowPlayingInfoDuration"])) out[@"duration"] = v;
                    if ((v = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"])) out[@"elapsed"] = v;
                    if ((v = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"])) out[@"rate"] = v;
                    // What kind of media it is, for telling a song from a film.
                    if ((v = info[@"kMRMediaRemoteNowPlayingInfoMediaType"])) out[@"mediaType"] = [v description];
                    if ((v = info[@"kMRMediaRemoteNowPlayingInfoIsMusicApp"])) out[@"isMusicApp"] = v;
                    if ((v = info[@"kMRMediaRemoteNowPlayingInfoGenre"])) out[@"genre"] = v;
                    NSDate *stamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                    if ([stamp isKindOfClass:[NSDate class]]) out[@"timestamp"] = @(stamp.timeIntervalSince1970);
                    NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                    if ([art isKindOfClass:[NSData class]] && art.length > 0) {
                        NSString *h = sha(art);
                        out[@"artworkHash"] = h;
                        if (![h isEqualToString:lastArtworkHash]) {
                            out[@"artwork"] = [art base64EncodedStringWithOptions:0];
                            lastArtworkHash = h;
                        }
                    }
                }
                emit(out);
            };
            if (getClient && clientBundle) {
                getClient(q, ^(id client) {
                    finish(client ? clientBundle(client) : nil,
                           client && clientParentBundle ? clientParentBundle(client) : nil);
                });
            } else {
                finish(nil, nil);
            }
        });
    });
}

// Perl XS entry points: perl calls these as `xsub(interpreter, cv)`; the arguments are unused.
void notchdeck_stream(void *perl, void *cv) {
    load();
    if (!getInfo || !getPlaying) { emit(@{@"error": @"MediaRemote unavailable"}); return; }
    ((RegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications"))(dispatch_get_main_queue());
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                      usingBlock:^(NSNotification *n) { report(); }];
    }
    report();
    // Exit when NotchDeck goes away (stdin closes).
    dispatch_source_t eof = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0, dispatch_get_main_queue());
    dispatch_source_set_event_handler(eof, ^{
        char buf[64];
        if (read(STDIN_FILENO, buf, sizeof buf) <= 0) exit(0);
    });
    dispatch_resume(eof);
    [[NSRunLoop mainRunLoop] run];
}

void notchdeck_send(void *perl, void *cv) {
    load();
    NSString *command = [[NSProcessInfo processInfo].environment objectForKey:@"NOTCHDECK_COMMAND"];
    NSDictionary *codes = @{@"play": @0, @"pause": @1, @"toggle": @2, @"next": @4, @"previous": @5};
    if ([command hasPrefix:@"seek:"]) {
        SetElapsedFn set = (SetElapsedFn)dlsym(mr, "MRMediaRemoteSetElapsedTime");
        if (set) set([[command substringFromIndex:5] doubleValue]);
    } else if (codes[command]) {
        SendFn send = (SendFn)dlsym(mr, "MRMediaRemoteSendCommand");
        if (send) send([codes[command] intValue], nil);
    }
    // Give MediaRemote a moment to deliver the command before perl exits.
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.15]];
}
