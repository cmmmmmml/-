#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <SystemConfiguration/SystemConfiguration.h>
#import <objc/runtime.h>
#import "AislingVerify.h"
#define XLMB_WATERMARK   @"小兰动态模糊倒卖司马"
#define kBStrength       @"XLMBStrength"
#define kBEnabled        @"XLMBEnabled"
#define kBCardKey        @"XLMBCardKey"
static UIWindow *gOverlayWin;
static UIWindow *gControlWin;
static UIWindow *gPanelWin;
static UIWindow *gGateWin;
static UIView   *gHostView;
static UIView   *gTrailLayer;
static UILabel  *gWatermark;
static UISlider *gSlider;
static UISwitch *gSwitch;
static UILabel  *gCardLabel;
static CADisplayLink *gLink;
static CGFloat  gStrength = 0.5;
static BOOL     gEnabled = YES;
static BOOL     gAuthorized = NO;
static BOOL     gWatchdogArmed = NO;
static BOOL     gPrevOnline = YES;
static NSInteger gOfflineHits = 0;
#pragma mark - helpers
static void XLMBHardFail(void) {
    NSLog(@"[XLMB] network watchdog trip");
    __builtin_trap();
}
static BOOL XLMBOnline(void) {
    SCNetworkReachabilityRef ref = SCNetworkReachabilityCreateWithName(NULL, "www.apple.com");
    if (!ref) return YES;
    SCNetworkReachabilityFlags f = 0;
    BOOL ok = SCNetworkReachabilityGetFlags(ref, &f);
    CFRelease(ref);
    if (!ok) return YES;
    return (f & kSCNetworkReachabilityFlagsReachable) != 0;
}
static UIView *XLMBLargestView(UIView *root) {
    if (!root) return nil;
    UIView *best = nil;
    CGFloat bestArea = 0;
    NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
    CGRect bounds = root.bounds;
    CGFloat limit = bounds.size.width * bounds.size.height * 0.30;
    while (stack.count) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if (v.hidden || v.alpha < 0.01) continue;
        CGRect f = [v convertRect:v.bounds toView:root];
        CGFloat area = f.size.width * f.size.height;
        if (area > bestArea && area >= limit && ![v isKindOfClass:[UILabel class]]) {
            bestArea = area;
            best = v;
        }
        for (UIView *sub in v.subviews) [stack addObject:sub];
    }
    return best ?: root;
}
static UIWindow *XLMBKeyWindow(void) {
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.isKeyWindow) return w;
    }
    return [UIApplication sharedApplication].windows.firstObject;
}
@interface XLMBCore : NSObject
+ (instancetype)shared;
- (void)boot;
- (void)gatePassed;
@end
XLMBCore *XLMBShared(void);
#pragma mark - 卡密验证界面
@interface XLMBGateVC : UIViewController <UITextFieldDelegate>
@property (nonatomic, strong) UITextField *field;
@property (nonatomic, strong) UIButton *button;
@property (nonatomic, strong) UILabel *status;
@property (nonatomic, assign) BOOL busy;
@end
@implementation XLMBGateVC
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:0.97];
    UILabel *title = [UILabel new];
    title.text = @"卡密验证";
    title.font = [UIFont boldSystemFontOfSize:24];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];
    UILabel *hint = [UILabel new];
    hint.text = @"请输入卡密后进入";
    hint.font = [UIFont systemFontOfSize:13];
    hint.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    hint.textAlignment = NSTextAlignmentCenter;
    hint.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:hint];
    self.field = [UITextField new];
    self.field.placeholder = @"卡密";
    self.field.textColor = UIColor.whiteColor;
    self.field.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    self.field.layer.cornerRadius = 10;
    self.field.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    self.field.autocorrectionType = UITextAutocorrectionTypeNo;
    self.field.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.field.delegate = self;
    self.field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    self.field.leftViewMode = UITextFieldViewModeAlways;
    self.field.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.field];
    self.button = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.button setTitle:@"验证并进入" forState:UIControlStateNormal];
    [self.button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.button.backgroundColor = [UIColor colorWithRed:0.36 green:0.42 blue:0.95 alpha:1];
    self.button.layer.cornerRadius = 10;
    [self.button addTarget:self action:@selector(submit) forControlEvents:UIControlEventTouchUpInside];
    self.button.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.button];
    self.status = [UILabel new];
    self.status.text = @"";
    self.status.font = [UIFont systemFontOfSize:12];
    self.status.textColor = [UIColor colorWithRed:1 green:0.45 blue:0.45 alpha:1];
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.numberOfLines = 0;
    self.status.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.status];
    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:g.topAnchor constant:120],
        [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [hint.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:8],
        [hint.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.field.topAnchor constraintEqualToAnchor:hint.bottomAnchor constant:28],
        [self.field.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:36],
        [self.field.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-36],
        [self.field.heightAnchor constraintEqualToConstant:46],
        [self.button.topAnchor constraintEqualToAnchor:self.field.bottomAnchor constant:14],
        [self.button.leadingAnchor constraintEqualToAnchor:self.field.leadingAnchor],
        [self.button.trailingAnchor constraintEqualToAnchor:self.field.trailingAnchor],
        [self.button.heightAnchor constraintEqualToConstant:46],
        [self.status.topAnchor constraintEqualToAnchor:self.button.bottomAnchor constant:14],
        [self.status.leadingAnchor constraintEqualToAnchor:self.field.leadingAnchor],
        [self.status.trailingAnchor constraintEqualToAnchor:self.field.trailingAnchor],
    ]];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kBCardKey];
    if (saved.length && !gAuthorized && !self.busy) {
        self.field.text = saved;
        [self submit];
    }
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self submit];
    return YES;
}
- (void)submit {
    if (self.busy) return;
    NSString *code = [self.field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (code.length == 0) {
        self.status.textColor = [UIColor colorWithRed:1 green:0.45 blue:0.45 alpha:1];
        self.status.text = @"请输入卡密";
        return;
    }
    self.busy = YES;
    self.button.enabled = NO;
    self.status.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    self.status.text = @"正在验证…";
    __weak typeof(self) weakSelf = self;
    [[AislingVerify shared] verifyKey:code completion:^(BOOL success, NSString *message, NSString *expiry) {
        __strong typeof(weakSelf) self2 = weakSelf;
        if (!self2) return;
        self2.busy = NO;
        self2.button.enabled = YES;
        if (success) {
            [[NSUserDefaults standardUserDefaults] setObject:code forKey:kBCardKey];
            [[NSUserDefaults standardUserDefaults] synchronize];
            self2.status.textColor = [UIColor colorWithRed:0.4 green:0.9 blue:0.5 alpha:1];
            self2.status.text = expiry.length ? [NSString stringWithFormat:@"验证成功 · 到期 %@", expiry] : @"验证成功";
            gAuthorized = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [XLMBShared() gatePassed];
            });
        } else {
            self2.status.textColor = [UIColor colorWithRed:1 green:0.45 blue:0.45 alpha:1];
            self2.status.text = message.length ? message : @"卡密错误";
            gAuthorized = NO;
        }
    }];
}
@end
#pragma mark - 主体
static XLMBCore *gCore;
XLMBCore *XLMBShared(void) {
    return gCore;
}
@implementation XLMBCore
+ (instancetype)shared {
    static XLMBCore *once = nil;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ once = [[XLMBCore alloc] init]; });
    return once;
}
- (void)boot {
    if (gCore) return;
    gCore = self;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    gStrength = [ud objectForKey:kBStrength] ? [ud doubleForKey:kBStrength] : 0.5;
    gEnabled  = [ud objectForKey:kBEnabled]  ? [ud boolForKey:kBEnabled]    : YES;
    [self buildOverlay];
    [self buildControl];
    [self buildGate];
    [self armWatchdog];
}
- (void)buildOverlay {
    gOverlayWin = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    gOverlayWin.windowLevel = UIWindowLevelNormal + 1;
    gOverlayWin.backgroundColor = UIColor.clearColor;
    gOverlayWin.userInteractionEnabled = NO;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    vc.view.userInteractionEnabled = NO;
    gOverlayWin.rootViewController = vc;
    gOverlayWin.hidden = NO;
    gTrailLayer = [UIView new];
    gTrailLayer.frame = gOverlayWin.bounds;
    gTrailLayer.userInteractionEnabled = NO;
    gTrailLayer.backgroundColor = UIColor.clearColor;
    gTrailLayer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:gTrailLayer];
    gWatermark = [UILabel new];
    gWatermark.text = XLMB_WATERMARK;
    gWatermark.font = [UIFont boldSystemFontOfSize:12];
    gWatermark.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
    gWatermark.layer.shadowColor = UIColor.blackColor.CGColor;
    gWatermark.layer.shadowOpacity = 0.9;
    gWatermark.layer.shadowRadius = 2;
    gWatermark.layer.shadowOffset = CGSizeMake(0, 1);
    gWatermark.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:gWatermark];
    UILayoutGuide *safe = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [gWatermark.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:10],
        [gWatermark.topAnchor constraintEqualToAnchor:safe.topAnchor constant:6],
    ]];
    gLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    gLink.preferredFramesPerSecond = 60;
    [gLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
- (void)buildControl {
    CGFloat side = 46;
    CGRect frame = CGRectMake([UIScreen mainScreen].bounds.size.width - side - 12, 140, side, side);
    gControlWin = [[UIWindow alloc] initWithFrame:frame];
    gControlWin.windowLevel = UIWindowLevelAlert + 2;
    gControlWin.backgroundColor = UIColor.clearColor;
    gControlWin.layer.cornerRadius = side / 2;
    gControlWin.clipsToBounds = YES;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    gControlWin.rootViewController = vc;
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.frame = CGRectMake(0, 0, side, side);
    [btn setTitle:@"模" forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:17];
    btn.backgroundColor = [UIColor colorWithRed:0.2 green:0.24 blue:0.5 alpha:0.85];
    [btn addTarget:self action:@selector(togglePanel) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:btn];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
    [btn addGestureRecognizer:pan];
    gControlWin.hidden = NO;
}
- (void)drag:(UIPanGestureRecognizer *)g {
    CGPoint p = [g translationInView:gControlWin];
    CGPoint c = gControlWin.center;
    CGSize scr = [UIScreen mainScreen].bounds.size;
    CGFloat half = gControlWin.bounds.size.width / 2;
    c.x = MIN(MAX(c.x + p.x, half + 4), scr.width - half - 4);
    c.y = MIN(MAX(c.y + p.y, half + 40), scr.height - half - 4);
    gControlWin.center = c;
    [g setTranslation:CGPointZero inView:gControlWin];
}
- (void)togglePanel {
    if (gPanelWin && !gPanelWin.hidden) {
        gPanelWin.hidden = YES;
        return;
    }
    if (!gPanelWin) [self buildPanel];
    gPanelWin.hidden = NO;
}
- (void)buildPanel {
    CGFloat w = 226, h = 152;
    CGRect r = CGRectMake(16, [UIScreen mainScreen].bounds.size.height - h - 90, w, h);
    gPanelWin = [[UIWindow alloc] initWithFrame:r];
    gPanelWin.windowLevel = UIWindowLevelAlert + 3;
    gPanelWin.backgroundColor = [UIColor colorWithWhite:0.09 alpha:0.94];
    gPanelWin.layer.cornerRadius = 14;
    gPanelWin.clipsToBounds = YES;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    gPanelWin.rootViewController = vc;
    UILabel *title = [UILabel new];
    title.text = @"动态模糊";
    title.font = [UIFont boldSystemFontOfSize:14];
    title.textColor = UIColor.whiteColor;
    title.frame = CGRectMake(14, 10, 120, 18);
    [vc.view addSubview:title];
    gSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(w - 62, 6, 51, 31)];
    gSwitch.on = gEnabled;
    [gSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    [vc.view addSubview:gSwitch];
    UILabel *label = [UILabel new];
    label.text = [NSString stringWithFormat:@"强度 %.0f%%", gStrength * 100];
    label.tag = 0x584C;
    label.font = [UIFont systemFontOfSize:12];
    label.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    label.frame = CGRectMake(14, 36, 160, 16);
    [vc.view addSubview:label];
    gSlider = [[UISlider alloc] initWithFrame:CGRectMake(14, 58, w - 28, 30)];
    gSlider.minimumValue = 0.05;
    gSlider.maximumValue = 1.0;
    gSlider.value = gStrength;
    [gSlider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    [vc.view addSubview:gSlider];
    gCardLabel = [UILabel new];
    gCardLabel.text = @"";
    gCardLabel.font = [UIFont systemFontOfSize:11];
    gCardLabel.textColor = [UIColor colorWithWhite:1 alpha:0.45];
    gCardLabel.frame = CGRectMake(14, 96, w - 28, 40);
    gCardLabel.numberOfLines = 2;
    [vc.view addSubview:gCardLabel];
    NSString *saved = [[NSUserDefaults standardUserDefaults] stringForKey:kBCardKey];
    gCardLabel.text = [NSString stringWithFormat:@"卡密 %@", saved.length ? saved : @"未验证"];
    gPanelWin.hidden = YES;
}
- (void)switchChanged:(UISwitch *)s {
    gEnabled = s.on;
    [[NSUserDefaults standardUserDefaults] setBool:gEnabled forKey:kBEnabled];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (!gEnabled) [gTrailLayer.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
}
- (void)sliderChanged:(UISlider *)s {
    gStrength = s.value;
    [[NSUserDefaults standardUserDefaults] setDouble:gStrength forKey:kBStrength];
    [[NSUserDefaults standardUserDefaults] synchronize];
    UILabel *label = [gPanelWin.rootViewController.view viewWithTag:0x584C];
    label.text = [NSString stringWithFormat:@"强度 %.0f%%", gStrength * 100];
}
#pragma mark 帧回调
- (void)tick:(CADisplayLink *)link {
    if (!gAuthorized || !gEnabled || gStrength <= 0.06) return;
    UIWindow *key = XLMBKeyWindow();
    UIView *root = key.rootViewController.view;
    if (!root) return;
    if (!gHostView || !gHostView.window) gHostView = XLMBLargestView(root);
    if (!gHostView) return;
    UIView *snap = [gHostView snapshotViewAfterScreenUpdates:NO];
    if (!snap) return;
    snap.frame = gTrailLayer.bounds;
    snap.userInteractionEnabled = NO;
    snap.alpha = 0.15 + 0.55 * gStrength;
    [gTrailLayer addSubview:snap];
    CGFloat life = 0.12 + 0.30 * gStrength;
    [UIView animateWithDuration:life delay:0
                        options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ snap.alpha = 0.0; }
                     completion:^(BOOL finished) { [snap removeFromSuperview]; }];
}
#pragma mark 卡密门
- (void)buildGate {
    gGateWin = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    gGateWin.windowLevel = UIWindowLevelAlert + 10;
    gGateWin.backgroundColor = UIColor.clearColor;
    gGateWin.rootViewController = [[XLMBGateVC alloc] init];
    gGateWin.hidden = NO;
    gWatermark.hidden = YES;
    gControlWin.hidden = YES;
}
- (void)gatePassed {
    gAuthorized = YES;
    gWatermark.hidden = NO;
    gControlWin.hidden = NO;
    gGateWin.hidden = YES;
    gGateWin = nil;
    [self armWatchdog];
}
#pragma mark 断网 / 联网闪退
- (void)armWatchdog {
    if (gWatchdogArmed) return;
    gWatchdogArmed = YES;
    gPrevOnline = XLMBOnline();
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                              (uint64_t)(0.5 * NSEC_PER_SEC),
                              (uint64_t)(0.1 * NSEC_PER_SEC));
    dispatch_source_set_event_handler(timer, ^{
        BOOL online = XLMBOnline();
        if (!online) {
            if (++gOfflineHits >= 2) XLMBHardFail();
        } else {
            gOfflineHits = 0;
            if (!gPrevOnline) XLMBHardFail();
        }
        gPrevOnline = online;
    });
    dispatch_resume(timer);
}
@end
#pragma mark - 入口
__attribute__((constructor)) static void xlmb_entry(void) {
    if (NSClassFromString(@"UIApplication") == nil) return;
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[XLMBCore shared] boot];
        });
    }];
}
