// ICQ Reborn — traffic forwarder tweak for the 2010 AIM-based ICQ clients
// (com.icq.icqpaid "ICQ Premium" and com.icq.icqfree "ICQ").
//
// These apps talk to AOL/ICQ's WIM HTTP API over NSURLConnection:
//   auth : https://api.login.icq.net/auth/clientLogin ...
//   api  : http://api.icq.net/{aim,im,presence,buddylist,...}
// The original servers are dead. This tweak rewrites every outgoing
// NSURLConnection request whose host belongs to the ICQ/AOL API to point
// at the server you configure in Settings, preserving the full path and
// query string. That is all a compatible "reborn" server needs to receive
// the exact same protocol traffic the app would have sent to ICQ.
//
// Target: iOS 6 (armv7), Cydia Substrate + PreferenceLoader.

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

// ---------------------------------------------------------------------------
// Settings (written by the Settings pane to com.icqreborn.tweak)
// ---------------------------------------------------------------------------
static NSString * const kPrefsDomain = @"com.icqreborn.tweak";
static NSString * const kPrefsPath   = @"/var/mobile/Library/Preferences/com.icqreborn.tweak.plist";
static NSString * const kPrefsNotify = @"com.icqreborn.tweak/prefsChanged";

static BOOL       gEnabled       = NO;   // master switch
static BOOL       gRedirectICQ   = YES;  // *.icq.net / *.icq.com
static BOOL       gRedirectAOL   = NO;   // *.aol.com / *.aim.com
static BOOL       gRedirectAll   = NO;   // every http(s) host
static BOOL       gAcceptAnyCert = YES;  // accept self-signed cert on your server
static BOOL       gLog           = NO;   // NSLog each rewrite
static NSString * gScheme        = @"http";
static NSString * gServerKind    = @"wim"; // "wim" | "oscar" (informational)
static NSString * gHost          = nil;  // your server host / IP
static NSString * gPort          = nil;  // optional port
static NSString * gDeviceId      = nil;  // device id issued by the bridge

// ---------------------------------------------------------------------------
// Prefs loading (works from inside the sandbox on jailbroken iOS 6:
// direct plist read first, CFPreferences as a fallback)
// ---------------------------------------------------------------------------
static NSDictionary *ICQRReadPrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    if (d) return d;

    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    NSArray *keys = [NSArray arrayWithObjects:
        @"Enabled", @"RedirectICQ", @"RedirectAOL", @"RedirectAll",
        @"AcceptAnyCert", @"LogTraffic", @"ServerHost", @"ServerPort",
        @"ServerScheme", nil];
    CFPreferencesAppSynchronize((CFStringRef)kPrefsDomain);
    for (NSString *k in keys) {
        CFPropertyListRef v = CFPreferencesCopyAppValue((CFStringRef)k, (CFStringRef)kPrefsDomain);
        if (v) { [m setObject:(id)v forKey:k]; CFRelease(v); }
    }
    return m;
}

static BOOL ICQRBool(NSDictionary *d, NSString *k, BOOL def) {
    id v = [d objectForKey:k];
    return v ? [v boolValue] : def;
}

static NSString *ICQRTrimmedString(id v) {
    if ([v isKindOfClass:[NSString class]]) {
        NSString *s = [(NSString *)v stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        return s.length ? s : nil;
    }
    if ([v isKindOfClass:[NSNumber class]]) return [v stringValue];
    return nil;
}

static void ICQRLoadPrefs(void) {
    NSDictionary *d = ICQRReadPrefs();

    gEnabled       = ICQRBool(d, @"Enabled",        NO);
    gRedirectICQ   = ICQRBool(d, @"RedirectICQ",    YES);
    gRedirectAOL   = ICQRBool(d, @"RedirectAOL",    NO);
    gRedirectAll   = ICQRBool(d, @"RedirectAll",    NO);
    gAcceptAnyCert = ICQRBool(d, @"AcceptAnyCert",  YES);
    gLog           = ICQRBool(d, @"LogTraffic",     NO);

    NSString *host = ICQRTrimmedString([d objectForKey:@"ServerHost"]);
    [gHost release]; gHost = [host copy];

    NSString *port = ICQRTrimmedString([d objectForKey:@"ServerPort"]);
    [gPort release]; gPort = [port copy];

    // Protocol: the UseHTTPS switch is authoritative; fall back to the
    // legacy ServerScheme string, then default to http.
    NSString *scheme;
    id useHTTPS = [d objectForKey:@"UseHTTPS"];
    if (useHTTPS != nil) {
        scheme = [useHTTPS boolValue] ? @"https" : @"http";
    } else {
        NSString *legacy = ICQRTrimmedString([d objectForKey:@"ServerScheme"]);
        scheme = [[legacy lowercaseString] isEqualToString:@"https"] ? @"https" : @"http";
    }
    [gScheme release];
    gScheme = [scheme copy];

    // Server kind is informational: the app always speaks WIM/HTTP. "oscar"
    // just means the configured host is a WIM<->OSCAR bridge in front of your
    // OSCAR server; the tweak forwards HTTP either way.
    NSString *kind = ICQRTrimmedString([d objectForKey:@"ServerKind"]);
    [gServerKind release];
    gServerKind = [([[kind lowercaseString] isEqualToString:@"oscar"] ? @"oscar" : @"wim") copy];

    NSString *devId = ICQRTrimmedString([d objectForKey:@"DeviceId"]);
    [gDeviceId release]; gDeviceId = [devId copy];

    if (gLog) {
        NSLog(@"[ICQReborn] prefs: enabled=%d host=%@ port=%@ scheme=%@ kind=%@ "
              @"icq=%d aol=%d all=%d anycert=%d",
              gEnabled, gHost, gPort, gScheme, gServerKind,
              gRedirectICQ, gRedirectAOL, gRedirectAll, gAcceptAnyCert);
    }
}

// ---------------------------------------------------------------------------
// Host matching + URL surgery
// ---------------------------------------------------------------------------
static BOOL ICQRHostHasSuffix(NSString *host, NSArray *suffixes) {
    NSString *h = [host lowercaseString];
    for (NSString *s in suffixes) {
        if ([h isEqualToString:s] ||
            [h hasSuffix:[@"." stringByAppendingString:s]]) return YES;
    }
    return NO;
}

static BOOL ICQRShouldRedirectHost(NSString *host) {
    if (host.length == 0) return NO;
    // never touch our own server (avoids loops / double rewrites)
    if (gHost.length && [[host lowercaseString] isEqualToString:[gHost lowercaseString]])
        return NO;
    if (gRedirectAll) return YES;
    if (gRedirectICQ &&
        ICQRHostHasSuffix(host, [NSArray arrayWithObjects:@"icq.net", @"icq.com", nil]))
        return YES;
    if (gRedirectAOL &&
        ICQRHostHasSuffix(host, [NSArray arrayWithObjects:@"aol.com", @"aim.com", nil]))
        return YES;
    return NO;
}

// Replace only scheme://authority, keep path + query + fragment verbatim.
static NSString *ICQRRewriteURLString(NSString *orig) {
    NSRange r = [orig rangeOfString:@"://"];
    if (r.location == NSNotFound) return nil;

    NSUInteger authStart = r.location + r.length;
    NSUInteger n = orig.length;
    NSUInteger i = authStart;
    while (i < n) {
        unichar c = [orig characterAtIndex:i];
        if (c == '/' || c == '?' || c == '#') break;
        i++;
    }
    NSString *tail = (i < n) ? [orig substringFromIndex:i] : @"/";
    if (tail.length == 0) tail = @"/";

    NSMutableString *base = [NSMutableString stringWithFormat:@"%@://%@", gScheme, gHost];
    if (gPort.length) [base appendFormat:@":%@", gPort];
    return [base stringByAppendingString:tail];
}

static NSURL *ICQRRewriteURL(NSURL *u) {
    if (!gEnabled || gHost.length == 0 || u == nil) return nil;
    NSString *scheme = [[u scheme] lowercaseString];
    if (!([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) return nil;
    if (!ICQRShouldRedirectHost([u host])) return nil;

    NSString *newStr = ICQRRewriteURLString([u absoluteString]);
    if (!newStr) return nil;
    NSURL *newURL = [NSURL URLWithString:newStr];
    if (newURL && gLog)
        NSLog(@"[ICQReborn] %@  ->  %@", [u absoluteString], newStr);
    return newURL;
}

// Returns a possibly-rewritten request. Preserves method, headers and body.
static NSURLRequest *ICQRRewriteRequest(NSURLRequest *req) {
    if (!gEnabled || req == nil) return req;
    NSURL *newURL = ICQRRewriteURL([req URL]);
    if (!newURL) return req;

    NSMutableURLRequest *m = [[req mutableCopy] autorelease];
    [m setURL:newURL];
    // Tag the request so a multi-tenant bridge knows which device (and thus
    // which OSCAR server) this traffic belongs to.
    if (gDeviceId.length) [m setValue:gDeviceId forHTTPHeaderField:@"X-ICQR-Device"];
    return m;
}

// ---------------------------------------------------------------------------
// TLS: let the app accept a self-signed certificate on YOUR server.
// The clients do not implement any custom auth-challenge handling, so
// CFNetwork consults this private classmethod for NSURLConnection.
// We only vouch for the configured server host, nothing else.
// ---------------------------------------------------------------------------
@interface NSURLRequest (ICQReborn)
@end
@implementation NSURLRequest (ICQReborn)
+ (BOOL)allowsAnyHTTPSCertificateForHost:(NSString *)host {
    if (!(gEnabled && gAcceptAnyCert)) return NO;
    if (gRedirectAll) return YES;
    if (gHost.length && [[host lowercaseString] isEqualToString:[gHost lowercaseString]])
        return YES;
    return NO;
}
@end

// ---------------------------------------------------------------------------
// Hooks — every NSURLConnection entry point used by the app
// ---------------------------------------------------------------------------
%hook NSURLConnection

+ (NSURLConnection *)connectionWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    return %orig(ICQRRewriteRequest(request), delegate);
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate {
    return %orig(ICQRRewriteRequest(request), delegate);
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate startImmediately:(BOOL)startImmediately {
    return %orig(ICQRRewriteRequest(request), delegate, startImmediately);
}

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSURLResponse **)response
                             error:(NSError **)error {
    return %orig(ICQRRewriteRequest(request), response, error);
}

+ (void)sendAsynchronousRequest:(NSURLRequest *)request
                          queue:(NSOperationQueue *)queue
              completionHandler:(void (^)(NSURLResponse *, NSData *, NSError *))handler {
    %orig(ICQRRewriteRequest(request), queue, handler);
}

%end

// Backstop: catch requests whose URL is set on a mutable request that the
// app hands to some other transport. Idempotent w.r.t. the hooks above.
%hook NSMutableURLRequest

- (void)setURL:(NSURL *)URL {
    NSURL *newURL = ICQRRewriteURL(URL);
    %orig(newURL ? newURL : URL);
}

%end

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------
static void ICQRPrefsChanged(CFNotificationCenterRef center, void *observer,
                             CFStringRef name, const void *object,
                             CFDictionaryRef userInfo) {
    ICQRLoadPrefs();
}

%ctor {
    @autoreleasepool {
        ICQRLoadPrefs();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, ICQRPrefsChanged,
                                        (CFStringRef)kPrefsNotify, NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);
        // structural changes (protocol / bridge location / language) use a
        // separate notification; reload on those too.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, ICQRPrefsChanged,
                                        CFSTR("com.icqreborn.tweak/menuChanged"), NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);
        %init;
    }
}
