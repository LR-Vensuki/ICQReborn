#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

@interface ICQRebornPrefsListController : PSListController {
    UIView   *_banner;
    UILabel  *_bannerLabel;
    BOOL      _busy;
    BOOL      _observing;
}
- (NSString *)menuLang;
- (NSString *)L:(NSString *)ru en:(NSString *)en;
- (void)onMenuChanged;
- (void)refresh;
- (void)ensureBanner;
- (void)doConnect:(PSSpecifier *)spec;
@end
