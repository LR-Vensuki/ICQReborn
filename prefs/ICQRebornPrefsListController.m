#import "ICQRebornPrefsListController.h"

// Settings pane for ICQ Reborn:
//  - RU/EN menu language (two plists, switched live);
//  - "Host" is always shown; the OSCAR-server field appears only in
//    OSCAR + "on server" mode (conditional specifiers);
//  - a colored status banner with the tweak logo;
//  - a "Connect" button that registers the device with the bridge.

static NSString * const kDomain = @"com.icqreborn.tweak";
static NSString * const kMenuNote = @"com.icqreborn.tweak/menuChanged";

static NSString *RBGet(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((CFStringRef)key, (CFStringRef)kDomain);
    if (!v) return nil;
    NSString *out = nil;
    CFTypeID t = CFGetTypeID(v);
    if (t == CFStringGetTypeID()) out = [[(NSString *)v copy] autorelease];
    else if (t == CFBooleanGetTypeID()) out = CFBooleanGetValue((CFBooleanRef)v) ? @"1" : @"0";
    else if (t == CFNumberGetTypeID()) { out = [[(NSNumber *)v stringValue] copy]; [out autorelease]; }
    CFRelease(v);
    return out;
}

static BOOL RBBool(NSString *key) { NSString *s = RBGet(key); return s ? [s boolValue] : NO; }

static void RBSet(NSString *key, NSString *val) {
    if (!val) return;
    CFPreferencesSetAppValue((CFStringRef)key, (CFStringRef)val, (CFStringRef)kDomain);
    CFPreferencesAppSynchronize((CFStringRef)kDomain);
}

static void MenuChangedCB(CFNotificationCenterRef c, void *observer, CFStringRef name,
                          const void *obj, CFDictionaryRef info) {
    [(ICQRebornPrefsListController *)observer performSelectorOnMainThread:@selector(onMenuChanged)
                                                              withObject:nil waitUntilDone:NO];
}

@implementation ICQRebornPrefsListController

- (NSString *)menuLang {
    NSString *l = RBGet(@"MenuLang");
    return [l isEqualToString:@"en"] ? @"en" : @"ru";
}

- (NSString *)L:(NSString *)ru en:(NSString *)en {
    return [[self menuLang] isEqualToString:@"en"] ? en : ru;
}

// ---- specifiers with language + conditional visibility -----------------
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *plist = [[self menuLang] isEqualToString:@"en"] ? @"Root_en" : @"Root";
        NSArray *all = [self loadSpecifiersFromPlistName:plist target:self];

        NSString *kind = RBGet(@"ServerKind") ?: @"wim";
        NSString *loc  = RBGet(@"BridgeLocation") ?: @"server";
        BOOL oscar = [kind isEqualToString:@"oscar"];
        BOOL srv   = [loc isEqualToString:@"server"];

        NSMutableArray *out = [NSMutableArray array];
        for (PSSpecifier *s in all) {
            NSString *g = [s propertyForKey:@"rbGroup"];
            if ([g isEqualToString:@"oscar"]    && !oscar)        continue;
            if ([g isEqualToString:@"oscarsrv"] && !(oscar && srv)) continue;
            [out addObject:s];
        }
        _specifiers = [out copy];
    }
    return _specifiers;
}

- (void)onMenuChanged {
    [_specifiers release];
    _specifiers = nil;
    [self reloadSpecifiers];
    [self refresh];
}

// ---- lifecycle ---------------------------------------------------------
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (!_observing) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        self, MenuChangedCB, (CFStringRef)kMenuNote,
                                        NULL, CFNotificationSuspensionBehaviorCoalesce);
        _observing = YES;
    }
    [self ensureBanner];
    [self refresh];
}

- (void)dealloc {
    if (_observing) {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                           self, (CFStringRef)kMenuNote, NULL);
    }
    [_banner release];
    [_bannerLabel release];
    [super dealloc];
}

// ---- banner (logo + status) -------------------------------------------
- (void)ensureBanner {
    if (_banner) return;
    CGFloat w = self.table ? self.table.bounds.size.width : 320.0;
    _banner = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 56)];
    _banner.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIImageView *logo = [[[UIImageView alloc] initWithFrame:CGRectMake(14, 8, 40, 40)] autorelease];
    logo.contentMode = UIViewContentModeScaleAspectFit;
    NSBundle *b = [NSBundle bundleForClass:[self class]];
    NSString *p = [b pathForResource:@"ICQReborn@2x" ofType:@"png"];
    if (!p) p = [b pathForResource:@"ICQReborn" ofType:@"png"];
    if (p) logo.image = [UIImage imageWithContentsOfFile:p];
    [_banner addSubview:logo];

    _bannerLabel = [[UILabel alloc] initWithFrame:CGRectMake(64, 6, w - 76, 44)];
    _bannerLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _bannerLabel.backgroundColor = [UIColor clearColor];
    _bannerLabel.textColor = [UIColor whiteColor];
    _bannerLabel.font = [UIFont boldSystemFontOfSize:15];
    _bannerLabel.numberOfLines = 2;
    _bannerLabel.textAlignment = NSTextAlignmentLeft;
    [_banner addSubview:_bannerLabel];
}

- (void)showColor:(UIColor *)color text:(NSString *)text {
    void (^apply)(void) = ^{
        [self ensureBanner];
        _banner.backgroundColor = color;
        _bannerLabel.text = text;
        if (self.table && self.table.tableHeaderView != _banner) self.table.tableHeaderView = _banner;
    };
    if ([NSThread isMainThread]) apply(); else dispatch_async(dispatch_get_main_queue(), apply);
}

- (void)hideBanner {
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.table) self.table.tableHeaderView = nil; });
}

static UIColor *cBlue(void)  { return [UIColor colorWithRed:0.18 green:0.44 blue:0.95 alpha:1.0]; }
static UIColor *cGreen(void) { return [UIColor colorWithRed:0.18 green:0.66 blue:0.31 alpha:1.0]; }
static UIColor *cRed(void)   { return [UIColor colorWithRed:0.82 green:0.01 blue:0.11 alpha:1.0]; }
static UIColor *cGrey(void)  { return [UIColor colorWithWhite:0.45 alpha:1.0]; }

// ---- banner state (no network here; that runs on the Connect button) ---
- (void)refresh {
    if (!RBBool(@"Enabled")) { [self hideBanner]; return; }
    NSString *kind = RBGet(@"ServerKind") ?: @"wim";
    NSString *loc  = RBGet(@"BridgeLocation") ?: @"server";

    if ([kind isEqualToString:@"wim"]) {
        [self showColor:cGreen() text:[self L:@"WIM напрямую — регистрация не требуется"
                                          en:@"WIM direct — no registration needed"]];
        return;
    }
    if ([loc isEqualToString:@"device"]) {
        [self showColor:cGrey() text:[self L:@"Мост на устройстве — в разработке"
                                        en:@"On-device bridge — work in progress"]];
        return;
    }
    if (RBGet(@"DeviceId").length) {
        [self showColor:cGreen() text:[self L:@"OK — устройство зарегистрировано"
                                          en:@"OK — device registered"]];
    } else {
        [self showColor:cGrey() text:[self L:@"Нажмите «Подключиться и проверить»"
                                        en:@"Tap “Connect & check”"]];
    }
}

// ---- Connect button: register with the bridge --------------------------
- (void)doConnect:(PSSpecifier *)spec {
    if (_busy) return;
    NSString *base = [self bridgeBase];
    if (!base) { [self showColor:cRed() text:[self L:@"Укажите адрес моста (Хост)" en:@"Enter the bridge host"]]; return; }
    if (!RBGet(@"OscarHost").length) { [self showColor:cRed() text:[self L:@"Укажите OSCAR хост" en:@"Enter the OSCAR host"]]; return; }

    _busy = YES;
    [self showColor:cBlue() text:[self L:@"Регистрация устройства…" en:@"Registering device…"]];
    NSString *body = [NSString stringWithFormat:@"fingerprint=%@", [self enc:[self fingerprint]]];
    [self post:[base stringByAppendingString:@"/reborn/register"] body:body key:nil done:^(NSDictionary *json, NSString *err) {
        if (err || ![json objectForKey:@"deviceId"]) {
            _busy = NO;
            [self showColor:cRed() text:[NSString stringWithFormat:[self L:@"Ошибка регистрации: %@" en:@"Registration error: %@"], err ?: @"?"]];
            return;
        }
        RBSet(@"DeviceId", [json objectForKey:@"deviceId"]);
        RBSet(@"DeviceKey", [json objectForKey:@"deviceKey"]);
        [self configure:base];
    }];
}

- (void)configure:(NSString *)base {
    [self showColor:cBlue() text:[self L:@"Настройка OSCAR-сервера…" en:@"Configuring OSCAR server…"]];
    NSString *body = [NSString stringWithFormat:@"oscarHost=%@&oscarPort=%@",
                      [self enc:RBGet(@"OscarHost")], [self enc:(RBGet(@"OscarPort") ?: @"5190")]];
    [self post:[base stringByAppendingString:@"/reborn/config"] body:body key:RBGet(@"DeviceKey") done:^(NSDictionary *json, NSString *err) {
        _busy = NO;
        if (err || ![[json objectForKey:@"ok"] boolValue]) {
            [self showColor:cRed() text:[NSString stringWithFormat:[self L:@"Ошибка настройки: %@" en:@"Config error: %@"], err ?: @"?"]];
            return;
        }
        [self showColor:cGreen() text:[self L:@"OK — устройство зарегистрировано" en:@"OK — device registered"]];
    }];
}

// ---- helpers -----------------------------------------------------------
- (NSString *)bridgeBase {
    NSString *host = RBGet(@"ServerHost");
    if (!host.length) return nil;
    NSString *scheme = RBBool(@"UseHTTPS") ? @"https" : @"http";
    NSString *port = RBGet(@"ServerPort");
    if (port.length) return [NSString stringWithFormat:@"%@://%@:%@", scheme, host, port];
    return [NSString stringWithFormat:@"%@://%@", scheme, host];
}

- (NSString *)fingerprint {
    NSString *fp = RBGet(@"DeviceFingerprint");
    if (!fp.length) {
        CFUUIDRef u = CFUUIDCreate(NULL);
        CFStringRef s = CFUUIDCreateString(NULL, u);
        fp = [[(NSString *)s copy] autorelease];
        CFRelease(s); CFRelease(u);
        RBSet(@"DeviceFingerprint", fp);
    }
    return fp;
}

- (NSString *)enc:(NSString *)s {
    return [s stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ?: @"";
}

- (void)post:(NSString *)urlStr body:(NSString *)body key:(NSString *)key
        done:(void (^)(NSDictionary *json, NSString *err))done {
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) { done(nil, @"bad url"); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setHTTPMethod:@"POST"];
    [req setTimeoutInterval:15.0];
    [req setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    if (key) [req setValue:key forHTTPHeaderField:@"x-icqr-key"];
    [req setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
    [NSURLConnection sendAsynchronousRequest:req
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *resp, NSData *data, NSError *error) {
        if (error) { done(nil, [error localizedDescription]); return; }
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        if (![json isKindOfClass:[NSDictionary class]]) { done(nil, @"bad response"); return; }
        done(json, nil);
    }];
}

@end
