#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

#define kBaseWindowWidth 300.0
#define kBaseWindowHeight 450.0
#define kPhraseIntervalMin 10.0
#define kPhraseIntervalMax 25.0
#define kFrameRate 12.0
#define kAutoActionInterval 10.0
#define kMinScale 0.4
#define kMaxScale 2.0

static NSArray *kPhrases;
static NSArray *kActionNames;

@interface FloatingWindow : NSWindow
@end

@implementation FloatingWindow {
    NSPoint _dragStartMouse;
    NSPoint _dragStartOrigin;
}

- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return YES; }

- (void)mouseDown:(NSEvent *)event {
    _dragStartMouse = [event locationInWindow];
    _dragStartOrigin = self.frame.origin;
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint current = [event locationInWindow];
    NSPoint delta = NSMakePoint(current.x - _dragStartMouse.x, current.y - _dragStartMouse.y);
    [self setFrameOrigin:NSMakePoint(_dragStartOrigin.x + delta.x, _dragStartOrigin.y + delta.y)];
}

- (void)rightMouseDown:(NSEvent *)event {
    NSMenu *menu = [[self contentView] menu];
    if (menu) {
        [NSMenu popUpContextMenu:menu withEvent:event forView:[self contentView]];
    }
}

@end

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (strong) FloatingWindow *window;
@property (strong) NSImageView *imageView;
@property (strong) NSTextField *bubbleLabel;
@property (strong) NSTimer *phraseTimer;
@property (strong) NSTimer *frameTimer;
@property (strong) NSTimer *autoActionTimer;

@property (copy) NSString *currentAction;
@property (strong) NSArray<NSImage *> *currentFrames;
@property (assign) NSInteger currentFrameIndex;
@property (assign) NSInteger manualLoopCount;
@property (strong) NSDictionary<NSString *, NSArray<NSImage *> *> *actionFrames;

@property (nonatomic, assign) CGFloat windowScale;
@property (assign) BOOL isHiding;
@property (assign) NSPoint normalOrigin;
@property (assign) NSSize normalSize;
@property (assign) BOOL manualActionPending;

// Photo frame (相框) support
@property (strong) NSView *photoFrameView;      // container: border + shadow
@property (strong) NSImageView *photoView;      // photo inside the frame
@property (strong) NSTimer *photoTimer;
@property (strong) NSArray<NSString *> *photoPaths;
@property (assign) NSInteger photoIndex;
@property (copy) NSString *photoFolder;
@property (assign) BOOL isShowingPhotos;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    kPhrases = @[@"爸爸妈妈在干啥～", @"我要睡觉啦", @"我要出去玩"];
    kActionNames = @[@"idle", @"crawl", @"stroll"];

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    self.windowScale = 1.0;
    self.isHiding = NO;
    self.manualActionPending = NO;
    self.isShowingPhotos = NO;
    self.photoFolder = [[NSUserDefaults standardUserDefaults] stringForKey:@"photoFolder"];

    NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
    CGFloat startX = NSMidX(screenFrame) - (kBaseWindowWidth / 2.0);
    CGFloat startY = NSMidY(screenFrame) - (kBaseWindowHeight / 2.0);

    self.window = [[FloatingWindow alloc]
        initWithContentRect:NSMakeRect(startX, startY, kBaseWindowWidth, kBaseWindowHeight)
                  styleMask:NSWindowStyleMaskBorderless
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [self.window setBackgroundColor:[NSColor clearColor]];
    [self.window setOpaque:NO];
    [self.window setHasShadow:NO];
    [self.window setLevel:NSFloatingWindowLevel];
    [self.window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary];

    NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kBaseWindowWidth, kBaseWindowHeight)];
    [self.window setContentView:contentView];

    // Image view
    NSImageView *imageView = [[NSImageView alloc] initWithFrame:[contentView bounds]];
    [imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
    [imageView setWantsLayer:YES];
    [contentView addSubview:imageView];
    self.imageView = imageView;

    // Load frame sequences
    [self loadActionFrames];

    // Speech bubble
    NSTextField *bubble = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
    [bubble setEditable:NO];
    [bubble setSelectable:NO];
    [bubble setBordered:NO];
    [bubble setAlignment:NSTextAlignmentCenter];
    [bubble setFont:[NSFont systemFontOfSize:14 weight:NSFontWeightMedium]];
    [bubble setTextColor:[NSColor blackColor]];
    [bubble setBackgroundColor:[NSColor clearColor]];
    [bubble setWantsLayer:YES];
    [[bubble layer] setBackgroundColor:[[NSColor whiteColor] CGColor]];
    [[bubble layer] setCornerRadius:14.0];
    [[bubble layer] setMasksToBounds:YES];
    [[bubble layer] setBorderColor:[[NSColor systemGrayColor] CGColor]];
    [[bubble layer] setBorderWidth:0.5];
    [bubble setAlphaValue:0.0];
    self.bubbleLabel = bubble;
    [contentView addSubview:bubble];

    // Photo frame (hidden until user triggers 举相框)
    // Container view provides the white frame border + drop shadow;
    // a child image view holds the photo so we can cross-fade it alone.
    NSView *photoFrame = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
    [photoFrame setWantsLayer:YES];
    [[photoFrame layer] setBackgroundColor:[[NSColor whiteColor] CGColor]];
    [[photoFrame layer] setBorderColor:[[NSColor colorWithWhite:0.85 alpha:1.0] CGColor]];
    [[photoFrame layer] setBorderWidth:9.0];
    [[photoFrame layer] setCornerRadius:8.0];
    [[photoFrame layer] setMasksToBounds:NO];
    [[photoFrame layer] setShadowOpacity:0.35];
    [[photoFrame layer] setShadowRadius:14.0];
    [[photoFrame layer] setShadowOffset:CGSizeMake(0, -5)];
    [[photoFrame layer] setShadowColor:[[NSColor blackColor] CGColor]];
    [photoFrame setHidden:YES];
    self.photoFrameView = photoFrame;
    [contentView addSubview:photoFrame];

    NSImageView *photoView = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 0, 0)];
    [photoView setImageScaling:NSImageScaleProportionallyUpOrDown];
    [photoView setWantsLayer:YES];
    [photoView setAlphaValue:0.0];
    [[photoView layer] setCornerRadius:3.0];
    [[photoView layer] setMasksToBounds:YES];
    self.photoView = photoView;
    [photoFrame addSubview:photoView];

    // Right-click menu
    NSMenu *menu = [[NSMenu alloc] init];

    NSMenu *actionMenu = [[NSMenu alloc] initWithTitle:@"切换动作"];
    [actionMenu addItem:[self actionItem:@"待机" action:@"idle"]];
    [actionMenu addItem:[self actionItem:@"爬行" action:@"crawl"]];
    [actionMenu addItem:[self actionItem:@"散步" action:@"stroll"]];
    NSMenuItem *actionItem = [[NSMenuItem alloc] initWithTitle:@"切换动作" action:nil keyEquivalent:@""];
    [actionItem setSubmenu:actionMenu];
    [menu addItem:actionItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *scaleUpItem = [[NSMenuItem alloc] initWithTitle:@"变大"
                                                         action:@selector(scaleUp)
                                                  keyEquivalent:@""];
    [scaleUpItem setTarget:self];
    [menu addItem:scaleUpItem];

    NSMenuItem *scaleDownItem = [[NSMenuItem alloc] initWithTitle:@"变小"
                                                           action:@selector(scaleDown)
                                                    keyEquivalent:@""];
    [scaleDownItem setTarget:self];
    [menu addItem:scaleDownItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *hideItem = [[NSMenuItem alloc] initWithTitle:@"躲起来"
                                                      action:@selector(toggleHide)
                                               keyEquivalent:@""];
    [hideItem setTarget:self];
    [hideItem setTag:100];
    [menu addItem:hideItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *albumItem = [[NSMenuItem alloc] initWithTitle:@"设置相册文件夹…"
                                                       action:@selector(choosePhotoFolder)
                                                keyEquivalent:@""];
    [albumItem setTarget:self];
    [menu addItem:albumItem];

    NSMenuItem *frameItem = [[NSMenuItem alloc] initWithTitle:@"举相框"
                                                       action:@selector(showPhotoFrame)
                                                keyEquivalent:@""];
    [frameItem setTarget:self];
    [menu addItem:frameItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *speakItem = [[NSMenuItem alloc] initWithTitle:@"说句话"
                                                       action:@selector(showPhrase)
                                                keyEquivalent:@""];
    [speakItem setTarget:self];
    [menu addItem:speakItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出"
                                                      action:@selector(quitApp)
                                               keyEquivalent:@"q"];
    [quitItem setTarget:self];
    [menu addItem:quitItem];
    [contentView setMenu:menu];

    // Start idle animation
    [self switchAction:@"idle"];

    // Start phrases
    [self scheduleNextPhrase];

    // Start auto action loop
    [self scheduleAutoAction];

    [self.window makeKeyAndOrderFront:nil];
}

- (NSMenuItem *)actionItem:(NSString *)title action:(NSString *)actionName {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                  action:@selector(switchActionFromMenu:)
                                           keyEquivalent:@""];
    [item setTarget:self];
    [item setRepresentedObject:actionName];
    return item;
}

- (void)loadActionFrames {
    NSMutableDictionary *frames = [NSMutableDictionary dictionary];

    // Idle uses the AI character static image
    NSString *idlePath = [[NSBundle mainBundle] pathForResource:@"baby" ofType:@"png"];
    if (idlePath) {
        NSImage *idleImage = [[NSImage alloc] initWithContentsOfFile:idlePath];
        if (idleImage) {
            frames[@"idle"] = @[idleImage];
        }
    }

    // Crawl frames
    [self loadFramesForAction:@"crawl" folder:@"frames_crawl" into:frames];

    // Stroll = use stroll frames only (previously interleaved walk+stroll
    // which caused per-frame jitter because the two videos show different motions)
    NSArray *strollOriginalFrames = [self loadFramesFromFolder:@"frames_stroll"];
    if ([strollOriginalFrames count] > 0) {
        frames[@"stroll"] = [strollOriginalFrames copy];
    }

    self.actionFrames = [frames copy];
}

- (void)loadFramesForAction:(NSString *)action folder:(NSString *)folder into:(NSMutableDictionary *)frames {
    NSArray *images = [self loadFramesFromFolder:folder];
    if ([images count] > 0) {
        frames[action] = images;
    }
}

- (NSArray<NSImage *> *)loadFramesFromFolder:(NSString *)folder {
    NSString *resPath = [[NSBundle mainBundle] resourcePath];
    NSString *folderPath = [resPath stringByAppendingPathComponent:folder];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folderPath error:nil];
    NSArray *pngs = [files filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self ENDSWITH '.png'"]];
    pngs = [pngs sortedArrayUsingSelector:@selector(localizedStandardCompare:)];

    NSMutableArray *images = [NSMutableArray array];
    for (NSString *name in pngs) {
        NSString *path = [folderPath stringByAppendingPathComponent:name];
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:path];
        if (img) [images addObject:img];
    }
    return [images copy];
}

- (void)switchActionFromMenu:(NSMenuItem *)sender {
    NSString *action = [sender representedObject];
    if (action) {
        self.manualActionPending = YES;
        [self switchAction:action];
        [self scheduleAutoAction];  // Reset auto timer; manual action plays until one full loop completes
    }
}

- (void)switchAction:(NSString *)action {
    NSArray *frames = self.actionFrames[action];
    if (!frames || [frames count] == 0) {
        NSLog(@"No frames for action %@", action);
        return;
    }

    [self.frameTimer invalidate];
    self.currentAction = action;
    self.currentFrames = frames;
    self.currentFrameIndex = 0;
    self.manualLoopCount = 0;

    [self.imageView.layer removeAllAnimations];
    [self.imageView setImage:frames[0]];

    if ([action isEqualToString:@"idle"]) {
        [self addBreathingAnimation:self.imageView.layer];
        [self addFloatingAnimation:self.imageView.layer];
    } else {
        self.frameTimer = [NSTimer scheduledTimerWithTimeInterval:(1.0 / kFrameRate)
                                                           target:self
                                                         selector:@selector(advanceFrame)
                                                         userInfo:nil
                                                          repeats:YES];
    }
}

- (void)advanceFrame {
    if (!self.currentFrames || [self.currentFrames count] == 0) return;
    self.currentFrameIndex = (self.currentFrameIndex + 1) % [self.currentFrames count];
    [self.imageView setImage:self.currentFrames[self.currentFrameIndex]];

    // If we just completed one full loop of a manually-chosen action,
    // switch to a random next action automatically
    if (self.currentFrameIndex == 0 && self.manualActionPending) {
        self.manualActionPending = NO;
        [self performAutoAction];
    }
}

- (void)scheduleAutoAction {
    [self.autoActionTimer invalidate];
    self.autoActionTimer = [NSTimer scheduledTimerWithTimeInterval:kAutoActionInterval
                                                            target:self
                                                          selector:@selector(performAutoAction)
                                                          userInfo:nil
                                                           repeats:NO];
}

- (void)performAutoAction {
    if (self.isHiding) {
        return;  // No actions while hiding; timer restarted on comeOut
    }

    NSString *nextAction = [self randomActionDifferentFrom:self.currentAction];
    [self switchAction:nextAction];
    [self scheduleAutoAction];
}

- (NSString *)randomActionDifferentFrom:(NSString *)current {
    NSMutableArray *candidates = [kActionNames mutableCopy];
    if (current) [candidates removeObject:current];
    if ([candidates count] == 0) candidates = [kActionNames mutableCopy];
    uint32_t idx = arc4random_uniform((uint32_t)[candidates count]);
    return candidates[idx];
}

- (void)addBreathingAnimation:(CALayer *)layer {
    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    anim.fromValue = @1.0;
    anim.toValue = @1.03;
    anim.duration = 2.8;
    anim.autoreverses = YES;
    anim.repeatCount = HUGE_VALF;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:anim forKey:@"breathing"];
}

- (void)addFloatingAnimation:(CALayer *)layer {
    CABasicAnimation *anim = [CABasicAnimation animationWithKeyPath:@"transform.translation.y"];
    anim.fromValue = @0;
    anim.toValue = @(-8);
    anim.duration = 3.2;
    anim.autoreverses = YES;
    anim.repeatCount = HUGE_VALF;
    anim.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:anim forKey:@"floating"];
}

- (void)scaleUp {
    [self setWindowScale:MIN(self.windowScale + 0.15, kMaxScale)];
}

- (void)scaleDown {
    [self setWindowScale:MAX(self.windowScale - 0.15, kMinScale)];
}

- (void)setWindowScale:(CGFloat)scale {
    _windowScale = scale;  // direct ivar; self.windowScale = would recurse infinitely
    NSRect frame = [self.window frame];
    CGFloat newWidth = kBaseWindowWidth * scale;
    CGFloat newHeight = kBaseWindowHeight * scale;
    CGFloat newX = frame.origin.x + (frame.size.width - newWidth) / 2.0;
    CGFloat newY = frame.origin.y + (frame.size.height - newHeight) / 2.0;
    [self.window setFrame:NSMakeRect(newX, newY, newWidth, newHeight) display:YES animate:YES];

    NSView *contentView = [self.window contentView];
    [self.imageView setFrame:[contentView bounds]];
    [self.bubbleLabel setFrame:NSMakeRect(0, 0, 0, 0)];

    // Keep a visible photo frame correctly laid out after rescaling
    if (self.isShowingPhotos && ![self.photoFrameView isHidden]) {
        [self.photoFrameView setFrame:[self photoFrameTargetRect]];
        [self.photoView setFrame:NSInsetRect([self.photoFrameView bounds], 9.0, 9.0)];
    }
}

- (void)toggleHide {
    if (self.isHiding) {
        [self comeOut];
    } else {
        [self hideAway];
    }
}

- (void)hideAway {
    if (self.isHiding) return;

    // Stop all action timers — baby stays still while hiding
    [self.frameTimer invalidate];
    [self.autoActionTimer invalidate];

    // Collapse photo frame if it was showing
    if (self.isShowingPhotos) {
        [self.photoTimer invalidate];
        self.photoTimer = nil;
        self.isShowingPhotos = NO;
        [self.photoFrameView setHidden:YES];
        [self.photoView setImage:nil];
        [self.photoView setAlphaValue:0.0];
    }

    NSRect frame = [self.window frame];
    self.normalOrigin = frame.origin;
    self.normalSize = frame.size;

    NSRect screenFrame = [[NSScreen mainScreen] visibleFrame];
    CGFloat peekHeight = frame.size.height * 0.18; // show only eyes and above
    CGFloat newY = screenFrame.origin.y;
    CGFloat newX = screenFrame.origin.x + screenFrame.size.width - frame.size.width * 0.45;

    [self.window setFrame:NSMakeRect(newX, newY, frame.size.width, peekHeight) display:YES animate:YES];

    // Adjust image view so only the top of the head is visible in the clipped window
    NSView *contentView = [self.window contentView];
    NSRect bounds = [contentView bounds];
    [self.imageView setFrame:NSMakeRect(0, -frame.size.height + peekHeight, bounds.size.width, frame.size.height)];

    self.isHiding = YES;
    [self updateHideMenuItem];
}

- (void)comeOut {
    if (!self.isHiding) return;

    [self.window setFrame:NSMakeRect(self.normalOrigin.x, self.normalOrigin.y, self.normalSize.width, self.normalSize.height) display:YES animate:YES];

    NSView *contentView = [self.window contentView];
    [self.imageView setFrame:[contentView bounds]];

    self.isHiding = NO;
    [self updateHideMenuItem];

    // Restart current action and auto timer
    [self switchAction:self.currentAction ? self.currentAction : @"idle"];
    [self scheduleAutoAction];
}

- (void)updateHideMenuItem {
    NSView *contentView = [self.window contentView];
    NSMenu *menu = [contentView menu];
    NSMenuItem *item = [menu itemWithTag:100];
    if (item) {
        [item setTitle:self.isHiding ? @"出来" : @"躲起来"];
    }
}

#pragma mark - Photo frame (相框)

- (void)choosePhotoFolder {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setPrompt:@"选择相册文件夹"];
    [panel setMessage:@"选择存放照片的文件夹（支持 jpg/png/heic 等图片）"];
    if ([panel runModal] == NSModalResponseOK) {
        NSURL *url = [[panel URLs] firstObject];
        if (url) {
            self.photoFolder = [url path];
            [[NSUserDefaults standardUserDefaults] setObject:self.photoFolder forKey:@"photoFolder"];
            NSLog(@"photo folder set: %@", self.photoFolder);
        }
    }
}

- (NSArray<NSString *> *)imageFilesInFolder:(NSString *)folder {
    NSArray *exts = @[@"jpg", @"jpeg", @"png", @"gif", @"heic", @"heif", @"bmp", @"tiff", @"webp"];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:nil];
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *name in files) {
        NSString *ext = [[name pathExtension] lowercaseString];
        if ([exts containsObject:ext]) {
            NSString *path = [folder stringByAppendingPathComponent:name];
            BOOL isDir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && !isDir) {
                [result addObject:path];
            }
        }
    }
    return [result copy];
}

- (NSArray *)shuffledArray:(NSArray *)array {
    NSMutableArray *copy = [array mutableCopy];
    for (NSUInteger i = [copy count] - 1; i > 0; i--) {
        NSUInteger j = arc4random_uniform((uint32_t)(i + 1));
        [copy exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
    return [copy copy];
}

- (void)showPhotoFrame {
    if (self.isShowingPhotos || self.isHiding) return;

    if (!self.photoFolder) {
        [self choosePhotoFolder];
        if (!self.photoFolder) return;
    }

    NSArray *images = [self imageFilesInFolder:self.photoFolder];
    if ([images count] == 0) {
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText:@"相册里没有找到照片"];
        [alert setInformativeText:@"请选择包含 jpg/png/heic 等图片的文件夹。"];
        [alert addButtonWithTitle:@"好"];
        [alert runModal];
        return;
    }

    // Random pick up to 3 photos
    NSArray *shuffled = [self shuffledArray:images];
    NSUInteger count = MIN(3, [shuffled count]);
    self.photoPaths = [shuffled subarrayWithRange:NSMakeRange(0, count)];
    self.photoIndex = 0;

    // Baby stands still while showing the frame
    self.manualActionPending = NO;
    [self switchAction:@"idle"];
    [self.autoActionTimer invalidate];

    self.isShowingPhotos = YES;

    // 1) Baby gets excited — a little anticipation hop
    [self babyHop];

    // 2) Frame rises from below with an ease-out overshoot, then settles.
    //    Two-stage motion reads as "being lifted up" instead of popping in.
    NSRect target = [self photoFrameTargetRect];
    [self.photoFrameView setHidden:NO];
    [self.photoFrameView setAlphaValue:1.0];
    [self.photoFrameView setFrame:NSMakeRect(target.origin.x, -target.size.height, target.size.width, target.size.height)];
    [self.photoView setFrame:NSInsetRect([self.photoFrameView bounds], 9.0, 9.0)];
    [self.photoView setAlphaValue:0.0];

    CGFloat overshootY = target.origin.y + 18.0;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.45;
        context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [self.photoFrameView.animator setFrame:NSMakeRect(target.origin.x, overshootY, target.size.width, target.size.height)];
    } completionHandler:^{
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.22;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
            [self.photoFrameView.animator setFrame:NSMakeRect(target.origin.x, target.origin.y, target.size.width, target.size.height)];
        } completionHandler:^{
            // 3) Hold: gentle wobble as if held by little hands
            [self startFrameWobble];

            // 4) First photo fades in
            [self setPhotoImageAtIndex:0 animated:YES];
            self.photoTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                               target:self
                                                             selector:@selector(advancePhoto)
                                                             userInfo:nil
                                                              repeats:YES];
        }];
    }];
}

- (NSRect)photoFrameTargetRect {
    NSRect b = [[self.window contentView] bounds];
    CGFloat fw = MIN(170.0, b.size.width * 0.58);
    CGFloat fh = fw * 1.3;
    // Center the frame over the baby's torso/body (the blue-box area)
    CGFloat tx = (b.size.width - fw) / 2.0;
    CGFloat ty = b.size.height * 0.32;
    return NSMakeRect(tx, ty, fw, fh);
}

- (void)babyHop {
    CALayer *babyLayer = self.imageView.layer;
    if (!babyLayer) return;

    // Pause the idle floating animation so the hop doesn't fight it
    [babyLayer removeAnimationForKey:@"floating"];

    CAKeyframeAnimation *hop = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
    hop.values = @[@0.0, @(-22.0), @0.0];
    hop.keyTimes = @[@0.0, @0.4, @1.0];
    hop.duration = 0.5;
    hop.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

    [CATransaction begin];
    [CATransaction setCompletionBlock:^{
        // Resume idle floating
        [self addFloatingAnimation:self.imageView.layer];
    }];
    [babyLayer addAnimation:hop forKey:@"hop"];
    [CATransaction commit];
}

- (void)startFrameWobble {
    CABasicAnimation *wobble = [CABasicAnimation animationWithKeyPath:@"transform.rotation"];
    wobble.fromValue = @(-2.5 * M_PI / 180.0);
    wobble.toValue = @(2.5 * M_PI / 180.0);
    wobble.duration = 2.4;
    wobble.autoreverses = YES;
    wobble.repeatCount = HUGE_VALF;
    wobble.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [self.photoFrameView.layer addAnimation:wobble forKey:@"frameWobble"];
}

- (void)setPhotoImageAtIndex:(NSInteger)index animated:(BOOL)animated {
    if (index < 0 || index >= [self.photoPaths count]) return;
    NSImage *img = [[NSImage alloc] initWithContentsOfFile:self.photoPaths[index]];
    if (!img) return;

    if (!animated) {
        [self.photoView setImage:img];
        [self.photoView setAlphaValue:1.0];
        return;
    }

    if (self.photoView.alphaValue < 0.05) {
        // First reveal: fade the photo in over the empty frame
        [self.photoView setImage:img];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.35;
            self.photoView.animator.alphaValue = 1.0;
        }];
    } else {
        // Cross-fade: old photo out, new photo in
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.2;
            self.photoView.animator.alphaValue = 0.0;
        } completionHandler:^{
            [self.photoView setImage:img];
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.3;
                self.photoView.animator.alphaValue = 1.0;
            }];
        }];
    }
}

- (void)advancePhoto {
    self.photoIndex++;
    // After 3 photos (or fewer if folder has less), retract the frame
    if (self.photoIndex >= 3 || self.photoIndex >= [self.photoPaths count]) {
        [self dismissPhotoFrame];
        return;
    }
    [self setPhotoImageAtIndex:self.photoIndex animated:YES];
}

- (void)dismissPhotoFrame {
    [self.photoTimer invalidate];
    self.photoTimer = nil;
    self.isShowingPhotos = NO;

    // Photo fades out first — the frame goes dark, then drops
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.25;
        self.photoView.animator.alphaValue = 0.0;
    } completionHandler:^{
        [self.photoFrameView.layer removeAnimationForKey:@"frameWobble"];
        NSRect f = [self.photoFrameView frame];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.4;
            context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
            [self.photoFrameView.animator setFrame:NSMakeRect(f.origin.x, -f.size.height, f.size.width, f.size.height)];
        } completionHandler:^{
            [self.photoFrameView setHidden:YES];
            [self.photoView setImage:nil];
            // Happy little hop after putting the frame away
            [self babyHop];
            // Back to standing, then resume auto actions
            [self switchAction:@"idle"];
            [self scheduleAutoAction];
        }];
    }];
}

- (void)showPhrase {
    // Allow phrases even when hiding — baby peeks out and says something
    NSString *text = kPhrases[arc4random_uniform((uint32_t)[kPhrases count])];
    [self.bubbleLabel setStringValue:text];
    [self.bubbleLabel sizeToFit];

    CGFloat padding = 16.0;
    NSRect contentFrame = [[self.window contentView] bounds];
    CGFloat bubbleWidth = MIN(self.bubbleLabel.frame.size.width + padding * 2, contentFrame.size.width - 20);
    CGFloat bubbleHeight = self.bubbleLabel.frame.size.height + 12;
    CGFloat bubbleY = contentFrame.size.height - bubbleHeight - 4;
    [self.bubbleLabel setFrame:NSMakeRect((contentFrame.size.width - bubbleWidth) / 2.0,
                                          bubbleY,
                                          bubbleWidth,
                                          bubbleHeight)];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.3;
        self.bubbleLabel.animator.alphaValue = 1.0;
    } completionHandler:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
                context.duration = 0.3;
                self.bubbleLabel.animator.alphaValue = 0.0;
            }];
        });
    }];

    [self scheduleNextPhrase];
}

- (void)scheduleNextPhrase {
    [self.phraseTimer invalidate];
    NSTimeInterval interval = kPhraseIntervalMin + (drand48() * (kPhraseIntervalMax - kPhraseIntervalMin));
    self.phraseTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                        target:self
                                                      selector:@selector(showPhrase)
                                                      userInfo:nil
                                                       repeats:NO];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return NO;
}

- (void)quitApp {
    [NSApp terminate:nil];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        [app setDelegate:delegate];
        [app run];
    }
    return 0;
}
