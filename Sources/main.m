#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import "Camera.h"
#import "PreviewTools.h"
#import <CoreImage/CoreImage.h>
#import <Vision/Vision.h>
#import "Optimizer.h"

@interface PreviewView : NSView
@property AVCaptureVideoPreviewLayer *preview;
@end
@implementation PreviewView
- (void)layout { [super layout]; self.preview.frame=self.bounds; }
@end

@interface App : NSObject <NSApplicationDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>
@property NSWindow *window;
@property Camera *camera;
@property NSStackView *controls;
@property NSTextField *status;
@property NSTextField *previewMessage;
@property PreviewView *previewView;
@property AVCaptureSession *session;
@property NSButton *previewButton;
@property NSPopUpButton *presets;
@property NSMutableDictionary *saved;
@property dispatch_queue_t queue;
@property dispatch_queue_t videoQueue;
@property BOOL busy;
@property BOOL previewActive;
@property AnalysisOverlay *overlay;
@property HistogramView *histogram;
@property NSTextField *analysisLabel;
@property NSTextField *presetState;
@property NSButton *compareButton;
@property NSButton *captureButton;
@property NSButton *warningButton;
@property NSButton *restoreButton;
@property NSImage *latestFrame;
@property dispatch_queue_t analysisQueue;
@property CIContext *imageContext;
@property double lastAnalysisTime;
@property BOOL framePending;
@property NSString *appliedPreset;
@property BOOL devicePresent;
@property NSTimer *deviceTimer;
@property NSButton *optimizeButton;
@property NSButton *undoOptimizeButton;
@property NSTextField *optimizeLabel;
@property NSSlider *targetSlider;
@property NSButton *backlitButton;
@property BOOL optimizerBacklit;
@property BOOL optimizing;
@property NSUInteger optimizerGeneration;
@property NSDictionary *optimizerUndo;
@property NSTimer *optimizerTimeout;
@property double optimizerReadyAt;
@property NSInteger optimizerSteps;
@property NSInteger optimizerSamples;
@property double meterSum, meterHigh, meterClipped;
@property CGRect previousFace;
@property double targetBrightness;
@property double optimizerBestScore;
@property NSDictionary *optimizerBestValues;
@property NSInteger optimizerLastDirection;
@property NSInteger optimizerReversals;
@property NSString *optimizerFinishMessage;
@end
@implementation App
- (NSTextField *)label:(NSString *)text size:(CGFloat)size {
 NSTextField *l=[NSTextField wrappingLabelWithString:text]; l.font=[NSFont systemFontOfSize:size]; return l;
}
- (NSButton *)button:(NSString *)title action:(SEL)selector {
 return [NSButton buttonWithTitle:title target:self action:selector];
}
- (NSStackView *)stack:(NSArray *)views vertical:(BOOL)vertical {
 NSStackView *s=[NSStackView stackViewWithViews:views]; s.orientation=vertical?NSUserInterfaceLayoutOrientationVertical:NSUserInterfaceLayoutOrientationHorizontal;
 s.alignment=vertical?NSLayoutAttributeLeading:NSLayoutAttributeCenterY; s.spacing=12; return s;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
 self.queue=dispatch_queue_create("studio.brio.usb",DISPATCH_QUEUE_SERIAL);
 self.videoQueue=dispatch_queue_create("studio.brio.video",DISPATCH_QUEUE_SERIAL);
 self.analysisQueue=dispatch_queue_create("studio.brio.analysis",DISPATCH_QUEUE_SERIAL);
 self.imageContext=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@NO}];
 self.camera=[Camera new]; self.saved=[[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"presets"] mutableCopy]?:[NSMutableDictionary new];
 NSMenu *menu=[NSMenu new]; NSMenuItem *appItem=[NSMenuItem new]; [menu addItem:appItem]; NSMenu *appMenu=[NSMenu new]; appItem.submenu=appMenu;
 [appMenu addItemWithTitle:@"Quit Brio Studio" action:@selector(terminate:) keyEquivalent:@"q"];
 NSMenuItem *editItem=[NSMenuItem new]; editItem.title=@"Edit"; [menu addItem:editItem]; NSMenu *edit=[NSMenu new]; editItem.submenu=edit;
 [edit addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"]; [edit addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"]; [edit addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"]; [edit addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"]; NSApp.mainMenu=menu;
 self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,1160,920) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
 self.window.title=@"Brio Studio"; self.window.minSize=NSMakeSize(1080,880); self.window.appearance=[NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
 NSView *root=self.window.contentView; root.wantsLayer=YES; root.layer.backgroundColor=[NSColor colorWithSRGBRed:0.065 green:0.075 blue:0.09 alpha:1].CGColor;
 NSTextField *title=[self label:@"Brio Studio" size:28]; title.font=[NSFont systemFontOfSize:28 weight:NSFontWeightSemibold];
 NSTextField *subtitle=[self label:@"YOUR CAMERA. YOUR LIGHT." size:11]; subtitle.textColor=NSColor.secondaryLabelColor;
 NSStackView *heading=[self stack:@[subtitle,title] vertical:YES]; heading.spacing=5;
 NSButton *lock=[self button:@"Lock current look" action:@selector(lockLook:)]; lock.bezelColor=NSColor.systemTealColor;
 NSStackView *toolbar=[self stack:@[lock,[self button:@"Refresh" action:@selector(refresh:)],[self button:@"Reconnect" action:@selector(reconnect:)]] vertical:NO];
 self.status=[self label:@"Connecting to Brio 100…" size:12]; self.status.textColor=NSColor.secondaryLabelColor;
 self.previewView=[PreviewView new]; self.previewView.wantsLayer=YES; self.previewView.layer.backgroundColor=NSColor.blackColor.CGColor; self.previewView.layer.cornerRadius=14; self.previewView.layer.masksToBounds=YES;
 self.previewMessage=[self label:@"See your adjustments live\n\nStart preview to turn on the camera." size:17]; self.previewMessage.alignment=NSTextAlignmentCenter;
 self.previewMessage.translatesAutoresizingMaskIntoConstraints=NO; [self.previewView addSubview:self.previewMessage];
 [NSLayoutConstraint activateConstraints:@[[self.previewMessage.centerXAnchor constraintEqualToAnchor:self.previewView.centerXAnchor],[self.previewMessage.centerYAnchor constraintEqualToAnchor:self.previewView.centerYAnchor],[self.previewMessage.widthAnchor constraintLessThanOrEqualToAnchor:self.previewView.widthAnchor constant:-40]]];
 self.overlay=[[AnalysisOverlay alloc]initWithFrame:self.previewView.bounds]; self.overlay.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable; [self.previewView addSubview:self.overlay positioned:NSWindowBelow relativeTo:self.previewMessage];
 self.previewButton=[self button:@"Start preview" action:@selector(togglePreview:)];
 NSTextField *hint=[self label:@"Changes are sent directly to your Brio 100. Other apps using this camera can see the adjusted image. They may also override your settings." size:13]; hint.textColor=NSColor.secondaryLabelColor;
 self.captureButton=[self button:@"Capture before" action:@selector(captureBefore:)]; self.captureButton.enabled=NO;
 self.compareButton=[NSButton checkboxWithTitle:@"Compare" target:self action:@selector(compare:)]; self.compareButton.enabled=NO;
 self.warningButton=[NSButton checkboxWithTitle:@"Exposure warnings" target:self action:@selector(warnings:)];
 NSStackView *previewBar=[self stack:@[self.previewButton,self.captureButton,self.compareButton] vertical:NO];
 self.histogram=[HistogramView new]; [self.histogram.heightAnchor constraintEqualToConstant:44].active=YES;
 self.analysisLabel=[self label:@"Start preview for exposure analysis · shadows ← brightness → highlights" size:11]; self.analysisLabel.textColor=NSColor.secondaryLabelColor;
 self.presets=[[NSPopUpButton alloc]initWithFrame:NSZeroRect pullsDown:NO]; self.presets.target=self; self.presets.action=@selector(selectPreset:); [self updatePresets];
 NSString *last=[[NSUserDefaults standardUserDefaults]stringForKey:@"lastPreset"]; if(self.saved[last]) [self.presets selectItemWithTitle:last];
 NSStackView *presetBar=[self stack:@[self.presets,[self button:@"Apply" action:@selector(applyPreset:)],[self button:@"Save…" action:@selector(savePreset:)],[self button:@"Delete" action:@selector(deletePreset:)]] vertical:NO];
 self.presetState=[self label:@"Choose a saved look to compare settings." size:11];
 self.restoreButton=[NSButton checkboxWithTitle:@"Restore last applied look on launch / reconnect" target:self action:@selector(restorePreference:)];
 self.restoreButton.state=[[NSUserDefaults standardUserDefaults]boolForKey:@"restorePreset"]?NSControlStateValueOn:NSControlStateValueOff;
 self.optimizeButton=[self button:@"Optimize once" action:@selector(optimize:)];
 self.undoOptimizeButton=[self button:@"Undo optimization" action:@selector(undoOptimization:)]; self.undoOptimizeButton.enabled=NO;
 self.targetSlider=[NSSlider sliderWithValue:60 minValue:35 maxValue:70 target:self action:@selector(targetChanged:)]; self.targetSlider.continuous=NO;
 [self.targetSlider.widthAnchor constraintEqualToConstant:100].active=YES;
 NSStackView *optimizerBar=[self stack:@[self.optimizeButton,self.undoOptimizeButton,[self label:@"Face brightness" size:11],self.targetSlider] vertical:NO];
 self.optimizeLabel=[self label:@"Start preview, face the camera, then optimize · Color stays locked" size:11]; self.optimizeLabel.textColor=NSColor.secondaryLabelColor;
 self.backlitButton=[NSButton checkboxWithTitle:@"Backlit · Brighter face, more noise" target:nil action:nil]; self.backlitButton.state=NSControlStateValueOn;
 NSStackView *analysisOptions=[self stack:@[self.warningButton,self.backlitButton] vertical:NO];
 NSStackView *left=[self stack:@[self.previewView,previewBar,analysisOptions,self.histogram,self.analysisLabel,optimizerBar,self.optimizeLabel,[self label:@"Saved looks" size:18],presetBar,self.presetState,self.restoreButton,hint] vertical:YES]; left.spacing=10;
 [self.optimizeLabel.widthAnchor constraintEqualToAnchor:left.widthAnchor].active=YES;
 [self.histogram.widthAnchor constraintEqualToAnchor:left.widthAnchor].active=YES;
 [self.analysisLabel.widthAnchor constraintEqualToAnchor:left.widthAnchor].active=YES;
 [self.presetState.widthAnchor constraintEqualToAnchor:left.widthAnchor].active=YES;
 self.controls=[self stack:@[] vertical:YES]; self.controls.spacing=16; self.controls.edgeInsets=NSEdgeInsetsMake(20,20,20,20);
 NSScrollView *scroll=[NSScrollView new]; scroll.hasVerticalScroller=YES; scroll.drawsBackground=NO; scroll.documentView=self.controls; self.controls.translatesAutoresizingMaskIntoConstraints=NO;
 [NSLayoutConstraint activateConstraints:@[[self.controls.leadingAnchor constraintEqualToAnchor:scroll.contentView.leadingAnchor],[self.controls.trailingAnchor constraintEqualToAnchor:scroll.contentView.trailingAnchor],[self.controls.topAnchor constraintEqualToAnchor:scroll.contentView.topAnchor]]];
 NSButton *reset=[self button:@"Restore camera defaults…" action:@selector(reset:)];
 for(NSView *view in @[heading,toolbar,self.status,left,scroll,reset]) { view.translatesAutoresizingMaskIntoConstraints=NO; [root addSubview:view]; }
 self.previewView.translatesAutoresizingMaskIntoConstraints=NO;
 [NSLayoutConstraint activateConstraints:@[
 [heading.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:28],[heading.topAnchor constraintEqualToAnchor:root.topAnchor constant:24],
 [toolbar.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-28],[toolbar.centerYAnchor constraintEqualToAnchor:heading.centerYAnchor],
 [self.status.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:12],[self.status.leadingAnchor constraintEqualToAnchor:heading.leadingAnchor],[self.status.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-28],
 [left.leadingAnchor constraintEqualToAnchor:heading.leadingAnchor],[left.topAnchor constraintEqualToAnchor:self.status.bottomAnchor constant:24],[left.widthAnchor constraintEqualToAnchor:root.widthAnchor multiplier:0.55 constant:-28],
 [self.previewView.widthAnchor constraintEqualToAnchor:left.widthAnchor],[self.previewView.heightAnchor constraintEqualToAnchor:self.previewView.widthAnchor multiplier:9.0/16.0],
 [hint.widthAnchor constraintEqualToAnchor:left.widthAnchor],
 [scroll.leadingAnchor constraintEqualToAnchor:left.trailingAnchor constant:20],[scroll.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-12],[scroll.topAnchor constraintEqualToAnchor:left.topAnchor],[scroll.bottomAnchor constraintEqualToAnchor:reset.topAnchor constant:-12],
 [reset.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-28],[reset.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-20]]];
 [self.window center]; [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES]; [self reconnect:nil];
 self.deviceTimer=[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(checkConnection:) userInfo:nil repeats:YES];
}
- (void)updatePresets {
 NSString *selected=self.presets.titleOfSelectedItem; [self.presets removeAllItems];
 NSArray *names=[[self.saved allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
 [self.presets addItemsWithTitles:names.count?names:@[@"No saved looks"]]; self.presets.enabled=names.count>0;
 if(selected && self.saved[selected]) [self.presets selectItemWithTitle:selected];
}
- (NSMutableDictionary *)control:(NSString *)key { for(NSMutableDictionary *c in self.camera.controls)if([c[@"key"] isEqual:key])return c; return nil; }
- (void)perform:(BOOL (^)(void))work message:(NSString *)message {
 if(self.busy || self.optimizing)return; self.busy=YES; self.status.stringValue=@"Updating camera…";
 dispatch_async(self.queue,^{ BOOL ok=work(); NSString *error=[self.camera.error copy];
 dispatch_async(dispatch_get_main_queue(),^{ self.busy=NO; [self renderControls]; [self updatePresetState]; self.status.stringValue=ok?message:(error.length?error:@"The camera could not apply this change."); self.status.textColor=ok?NSColor.secondaryLabelColor:NSColor.systemOrangeColor; }); });
}
- (void)reconnect:(id)sender {
 NSString *name=[[NSUserDefaults standardUserDefaults]stringForKey:@"appliedPreset"];
 NSDictionary *values=self.restoreButton.state==NSControlStateValueOn?[self.saved[name] copy]:nil;
 [self perform:^BOOL{ if(![self.camera connect])return NO;
 if(values && ![self applyValues:values])return NO;
 dispatch_async(dispatch_get_main_queue(),^{self.devicePresent=YES; if(values){self.appliedPreset=name; [self.presets selectItemWithTitle:name];}}); return YES;
 } message:values?@"Brio 100 connected · Last applied look restored":@"Brio 100 connected · Hardware controls ready"];
}
- (void)refresh:(id)sender { [self perform:^BOOL{ return [self.camera refresh]; } message:@"Current camera values refreshed"]; }
- (void)renderControls {
 for(NSView *v in self.controls.arrangedSubviews) { [self.controls removeArrangedSubview:v]; [v removeFromSuperview]; }
 if(!self.camera.controls.count) { [self.controls addArrangedSubview:[self label:@"Connect your Brio 100 to see its available controls." size:15]]; return; }
 for(NSUInteger i=0;i<self.camera.controls.count;i++) {
 NSDictionary *c=self.camera.controls[i]; NSString *key=c[@"key"];
 if([@[@"autoExposure",@"autoWB",@"brightness"] containsObject:key]) {
 NSString *section=[key isEqual:@"autoExposure"]?@"EXPOSURE":[key isEqual:@"autoWB"]?@"COLOR TEMPERATURE":@"IMAGE";
 NSTextField *h=[self label:section size:11]; h.textColor=NSColor.systemTealColor; h.font=[NSFont systemFontOfSize:11 weight:NSFontWeightSemibold]; [self.controls addArrangedSubview:h];
 }
 int kind=[c[@"kind"] intValue],value=[c[@"value"] intValue]; BOOL enabled=!self.optimizing && [c[@"writable"] boolValue] && !([c[@"info"] intValue]&4);
 if([key isEqual:@"exposure"] || [key isEqual:@"gain"]) enabled=enabled && [[self control:@"autoExposure"][@"value"] intValue]==1;
 if([key isEqual:@"whiteBalance"])enabled=enabled && ![[self control:@"autoWB"][@"value"] boolValue];
 NSStackView *row=[self stack:@[] vertical:YES]; row.spacing=6;
 if(kind==1) { NSButton *b=[NSButton checkboxWithTitle:c[@"label"] target:self action:@selector(change:)]; b.state=value?NSControlStateValueOn:NSControlStateValueOff; b.tag=i; b.enabled=enabled; [row addArrangedSubview:b]; }
 else if(kind==2 || kind==3) {
 [row addArrangedSubview:[self label:c[@"label"] size:13]];
 NSPopUpButton *popup=[[NSPopUpButton alloc]initWithFrame:NSZeroRect pullsDown:NO]; popup.target=self; popup.action=@selector(change:); popup.tag=i; popup.enabled=enabled;
 NSArray *names=kind==2?@[@"Manual",@"Auto",@"Shutter priority",@"Auto exposure (aperture priority)"]:@[@"Off",@"50 Hz",@"60 Hz",@"Auto"];
 for(int j=0;j<(int)names.count;j++) { int val=kind==2?1<<j:j; if(kind==2 && !([c[@"step"] intValue]&val))continue; if(kind==3 && val>[c[@"max"] intValue])continue; [popup addItemWithTitle:names[j]]; popup.lastItem.representedObject=@(val); if(value==val)[popup selectItem:popup.lastItem]; }
 [row addArrangedSubview:popup];
 } else {
 NSString *caption=[NSString stringWithFormat:@"%@  ·  %@",c[@"label"],c[@"value"]];
 if([key isEqual:@"exposure"])caption=[NSString stringWithFormat:@"Exposure  ·  %.1f ms",value/10.0];
 [row addArrangedSubview:[self label:caption size:13]];
 NSSlider *slider=[NSSlider sliderWithValue:value minValue:[c[@"min"] doubleValue] maxValue:[c[@"max"] doubleValue] target:self action:@selector(change:)]; slider.continuous=NO; slider.tag=i; slider.enabled=enabled;
 NSTextField *number=[[NSTextField alloc]initWithFrame:NSZeroRect]; number.stringValue=c[@"value"]? [c[@"value"] stringValue]:@""; number.target=self; number.action=@selector(change:); number.tag=i; number.enabled=enabled;
 [number.widthAnchor constraintEqualToConstant:62].active=YES;
 NSStackView *line=[self stack:@[slider,number] vertical:NO]; [row addArrangedSubview:line];
 [line.widthAnchor constraintEqualToAnchor:row.widthAnchor].active=YES;
 NSString *range=[NSString stringWithFormat:@"%@ – %@%@",c[@"min"],c[@"max"],enabled?@"":(self.optimizing?@" · optimization in progress":@" · switch off automatic mode to adjust")];
 NSTextField *rangeLabel=[self label:range size:10]; rangeLabel.textColor=NSColor.tertiaryLabelColor; [row addArrangedSubview:rangeLabel];
 }
 [self.controls addArrangedSubview:row]; [row.widthAnchor constraintEqualToAnchor:self.controls.widthAnchor constant:-40].active=YES;
 }
}
- (void)change:(NSControl *)sender {
 if(self.busy || self.optimizing)return; NSMutableDictionary *c=self.camera.controls[sender.tag]; int value=0;
 if([sender isKindOfClass:NSPopUpButton.class]) value=[[(NSPopUpButton *)sender selectedItem].representedObject intValue];
 else if([sender isKindOfClass:NSButton.class])value=[(NSButton *)sender state]==NSControlStateValueOn;
 else if([sender isKindOfClass:NSTextField.class]) { NSScanner *scan=[NSScanner scannerWithString:sender.stringValue]; if(![scan scanInt:&value] || !scan.isAtEnd) { self.status.stringValue=@"Enter a whole number within the displayed range."; [self renderControls]; return; } }
 else value=(int)llround(sender.doubleValue);
 [self perform:^BOOL{ if(![self.camera setControl:c value:value])return NO; return [self.camera refresh]; } message:@"Applied to Brio 100"];
}
- (BOOL)applyValues:(NSDictionary *)values {
 // Disable automatic controls before manual writes, then restore the requested modes.
 NSMutableArray *errors=[NSMutableArray new];
 NSDictionary *manual=@{@"autoExposure":@1,@"autoWB":@0,@"autoFocus":@0};
 NSMutableDictionary *original=[NSMutableDictionary new];
 for(NSString *key in manual) { NSMutableDictionary *c=[self control:key]; if(c && values[key]) { original[key]=c[@"value"]; if(![self.camera setControl:c value:[manual[key] intValue]])[errors addObject:c[@"label"]]; } }
 [self.camera refresh];
 for(NSMutableDictionary *c in self.camera.controls) { NSString *key=c[@"key"]; if(manual[key] || !values[key])continue;
 if(![self.camera setControl:c value:[values[key] intValue]]) [errors addObject:c[@"label"]]; }
 for(NSString *key in original) { NSMutableDictionary *c=[self control:key]; if(![self.camera setControl:c value:[values[key] intValue]])[errors addObject:c[@"label"]]; }
 BOOL refreshed=[self.camera refresh];
 if(errors.count) { self.camera.error=[NSString stringWithFormat:@"Some settings could not be applied: %@. Current values are shown.",[errors componentsJoinedByString:@", "]]; return NO; }
 return refreshed;
}
- (void)lockLook:(id)sender {
 [self perform:^BOOL{
 if(![self.camera refresh])return NO; NSMutableDictionary *values=[NSMutableDictionary new];
 for(NSString *key in @[@"exposure",@"gain",@"whiteBalance"]) { NSDictionary *c=[self control:key]; if(c)values[key]=c[@"value"]; }
 if([self control:@"autoExposure"]) values[@"autoExposure"]=@1;
 if([self control:@"autoWB"]) values[@"autoWB"]=@0;
 return [self applyValues:values]; } message:@"Current exposure and color locked · Fine-tune the sliders to taste"];
}
- (void)savePreset:(id)sender {
 if(self.busy || self.optimizing || !self.camera.controls.count)return;
 NSAlert *a=[NSAlert new]; a.messageText=@"Save this look"; a.informativeText=@"Save the camera’s current settings so you can reapply them later.";
 NSTextField *name=[[NSTextField alloc]initWithFrame:NSMakeRect(0,0,280,26)]; name.placeholderString=@"For example: Desk · Evening"; a.accessoryView=name;
 [a addButtonWithTitle:@"Save"]; [a addButtonWithTitle:@"Cancel"];
 if([a runModal]!=NSAlertFirstButtonReturn)return; NSString *key=[name.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; if(!key.length)return;
 if(self.saved[key]) { NSAlert *overwrite=[NSAlert new]; overwrite.messageText=@"Replace this saved look?"; [overwrite addButtonWithTitle:@"Replace"]; [overwrite addButtonWithTitle:@"Cancel"]; if([overwrite runModal]!=NSAlertFirstButtonReturn)return; }
 [self perform:^BOOL{ if(![self.camera refresh])return NO; NSMutableDictionary *values=[NSMutableDictionary new]; for(NSDictionary *c in self.camera.controls)if([c[@"writable"] boolValue])values[c[@"key"]]=c[@"value"];
 dispatch_async(dispatch_get_main_queue(),^{ self.saved[key]=values; [[NSUserDefaults standardUserDefaults]setObject:self.saved forKey:@"presets"]; [self updatePresets]; [self.presets selectItemWithTitle:key]; [self rememberApplied:key]; }); return YES; } message:@"Look saved on this Mac"];
}
- (void)applyPreset:(id)sender { NSString *name=self.presets.titleOfSelectedItem; NSDictionary *values=[self.saved[name] copy]; if(!values)return; [self perform:^BOOL{ if(![self applyValues:values])return NO; dispatch_async(dispatch_get_main_queue(),^{[self rememberApplied:name];}); return YES; } message:@"Saved look applied"]; }
- (void)deletePreset:(id)sender { NSString *name=self.presets.titleOfSelectedItem; if(!self.saved[name])return; NSAlert *a=[NSAlert new]; a.messageText=[NSString stringWithFormat:@"Delete “%@”?",name]; [a addButtonWithTitle:@"Delete"]; [a addButtonWithTitle:@"Cancel"]; if([a runModal]!=NSAlertFirstButtonReturn)return; [self.saved removeObjectForKey:name]; if([self.appliedPreset isEqual:name])self.appliedPreset=nil;
 if([[[NSUserDefaults standardUserDefaults]stringForKey:@"appliedPreset"] isEqual:name])[[NSUserDefaults standardUserDefaults]removeObjectForKey:@"appliedPreset"]; [[NSUserDefaults standardUserDefaults]setObject:self.saved forKey:@"presets"]; [self updatePresets]; [self selectPreset:nil]; }
- (void)reset:(id)sender {
 if(self.busy || self.optimizing)return; NSAlert *a=[NSAlert new]; a.messageText=@"Restore camera defaults?"; a.informativeText=@"This replaces your current settings with the defaults reported by the webcam. Save a look first if you want to keep your adjustments.";
 [a addButtonWithTitle:@"Restore defaults"]; [a addButtonWithTitle:@"Cancel"]; if([a runModal]!=NSAlertFirstButtonReturn)return;
 [self perform:^BOOL{ NSMutableDictionary *values=[NSMutableDictionary new]; for(NSDictionary *c in self.camera.controls)if([c[@"hasDefault"] boolValue] && [c[@"writable"] boolValue])values[c[@"key"]]=c[@"default"]; return [self applyValues:values]; } message:@"Camera defaults restored"];
}
- (void)togglePreview:(id)sender {
 if(self.previewActive) { self.previewActive=NO; [self clearAnalysis]; self.previewButton.enabled=NO; AVCaptureSession *s=self.session;
 dispatch_async(self.videoQueue,^{ [s stopRunning]; dispatch_async(dispatch_get_main_queue(),^{ [self.previewView.preview removeFromSuperlayer]; self.previewView.preview=nil; self.session=nil; self.previewMessage.hidden=NO; self.previewMessage.stringValue=@"Preview stopped\n\nHardware settings remain applied."; self.previewButton.title=@"Start preview"; self.previewButton.enabled=YES; }); }); return; }
 self.previewButton.enabled=NO;
 [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted){ dispatch_async(dispatch_get_main_queue(),^{
 if(!granted) { self.previewMessage.stringValue=@"Camera access is off.\nAllow Brio Studio in System Settings → Privacy & Security → Camera."; self.previewButton.enabled=YES; return; }
 [self startPreview]; }); }];
}
- (void)startPreview {
 dispatch_async(self.videoQueue,^{
 AVCaptureDeviceDiscoverySession *discovery=[AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeExternal] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
 AVCaptureDevice *device=nil; for(AVCaptureDevice *d in discovery.devices)if([d.localizedName localizedCaseInsensitiveContainsString:@"Brio 100"]){device=d;break;}
 NSError *error=nil; AVCaptureDeviceInput *input=device?[AVCaptureDeviceInput deviceInputWithDevice:device error:&error]:nil;
 AVCaptureSession *session=[AVCaptureSession new];
 if(!input || ![session canAddInput:input]) { dispatch_async(dispatch_get_main_queue(),^{self.previewMessage.stringValue=error.localizedDescription?:@"Brio 100 is unavailable. Reconnect it and try again."; self.previewButton.enabled=YES;}); return; }
 [session beginConfiguration]; [session addInput:input]; if([session canSetSessionPreset:AVCaptureSessionPreset1920x1080])session.sessionPreset=AVCaptureSessionPreset1920x1080; AVCaptureVideoDataOutput *output=[AVCaptureVideoDataOutput new]; output.alwaysDiscardsLateVideoFrames=YES;
 output.videoSettings=@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)};
 [output setSampleBufferDelegate:self queue:self.analysisQueue];
 if([session canAddOutput:output])[session addOutput:output];
 [session commitConfiguration];
 dispatch_async(dispatch_get_main_queue(),^{ [self.previewView.preview removeFromSuperlayer];
 if(self.session)[[NSNotificationCenter defaultCenter]removeObserver:self name:AVCaptureSessionRuntimeErrorNotification object:self.session];
 self.session=session; AVCaptureVideoPreviewLayer *layer=[AVCaptureVideoPreviewLayer layerWithSession:session]; layer.videoGravity=AVLayerVideoGravityResizeAspect; layer.frame=self.previewView.bounds; self.previewView.preview=layer; [self.previewView.layer insertSublayer:layer atIndex:0];
 [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(previewError:) name:AVCaptureSessionRuntimeErrorNotification object:session];
 dispatch_async(self.videoQueue,^{ [session startRunning]; BOOL running=session.running; dispatch_async(dispatch_get_main_queue(),^{ self.previewActive=running; self.previewMessage.hidden=running; self.previewButton.enabled=YES; self.previewButton.title=running?@"Stop preview":@"Start preview"; if(!running)self.previewMessage.stringValue=@"Preview could not start. Close other camera apps and try again."; }); }); });
 });
}
- (void)previewError:(NSNotification *)notification { dispatch_async(dispatch_get_main_queue(),^{ self.previewMessage.hidden=NO; self.previewMessage.stringValue=[notification.userInfo[AVCaptureSessionErrorKey] localizedDescription]?:@"Camera preview disconnected."; self.previewActive=NO; [self clearAnalysis]; self.previewButton.title=@"Start preview"; }); }
- (NSDictionary *)currentValues {
 NSMutableDictionary *values=[NSMutableDictionary new]; for(NSDictionary *c in self.camera.controls)values[c[@"key"]]=c[@"value"]; return values;
}
- (void)rememberApplied:(NSString *)name {
 self.appliedPreset=name; NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
 [d setObject:name forKey:@"lastPreset"]; [d setObject:name forKey:@"appliedPreset"]; [self updatePresetState];
}
- (void)selectPreset:(id)sender {
 NSString *name=self.presets.titleOfSelectedItem; if(self.saved[name])[[NSUserDefaults standardUserDefaults]setObject:name forKey:@"lastPreset"];
 if(!self.busy)[self updatePresetState];
}
- (void)updatePresetState {
 NSDictionary *saved=self.saved[self.presets.titleOfSelectedItem];
 if(!self.camera.controls.count){self.presetState.stringValue=@"Camera disconnected · Saved looks stay on this Mac.";return;}
 if(!saved){self.presetState.stringValue=@"Save your current settings as a look.";return;}
 BOOL matches=PresetMatches(saved,[self currentValues]);
 self.presetState.stringValue=matches?@"Matches saved look":@"Modified / different from selected look · Save to keep changes, Apply to restore.";
 self.presetState.textColor=matches?NSColor.systemTealColor:NSColor.systemOrangeColor;
}
- (void)restorePreference:(id)sender { [[NSUserDefaults standardUserDefaults]setBool:self.restoreButton.state==NSControlStateValueOn forKey:@"restorePreset"]; }
- (void)checkConnection:(id)sender {
 if(self.busy)return;
 BOOL present=NO; AVCaptureDeviceDiscoverySession *discovery=[AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeExternal] mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionUnspecified];
 for(AVCaptureDevice *d in discovery.devices)if([d.localizedName localizedCaseInsensitiveContainsString:@"Brio 100"]){present=YES;break;}
 if(!present && self.devicePresent) {
 self.devicePresent=NO; self.status.stringValue=@"Brio 100 disconnected · Waiting for reconnection";
 self.previewActive=NO; [self clearAnalysis]; self.previewMessage.hidden=NO; self.previewMessage.stringValue=@"Camera disconnected"; self.previewButton.title=@"Start preview";
 [self perform:^BOOL{ [self.camera connect]; return NO; } message:@""];
 } else if(present && !self.devicePresent) { self.devicePresent=YES; [self reconnect:nil]; }
}
- (void)captureBefore:(id)sender {
 if(!self.latestFrame)return; self.overlay.beforeImage=self.latestFrame; self.compareButton.enabled=YES; self.compareButton.state=NSControlStateValueOn; [self compare:nil];
 self.captureButton.title=@"Recapture before";
}
- (void)compare:(id)sender { self.overlay.showBefore=self.compareButton.state==NSControlStateValueOn; [self.overlay setNeedsDisplay:YES]; }
- (void)warnings:(id)sender { self.overlay.showWarnings=self.warningButton.state==NSControlStateValueOn; [self.overlay setNeedsDisplay:YES]; }
- (void)clearAnalysis {
 if(self.optimizing)[self finishOptimization:@"Optimization stopped · Preview is unavailable. Undo remains available."];
 self.latestFrame=nil; self.overlay.beforeImage=nil; self.overlay.warnings=nil; self.overlay.showBefore=NO;
 self.compareButton.state=NSControlStateValueOff; self.compareButton.enabled=NO; self.captureButton.enabled=NO; self.captureButton.title=@"Capture before";
 self.histogram.bins=nil; [self.histogram setNeedsDisplay:YES]; [self.overlay setNeedsDisplay:YES];
 self.analysisLabel.stringValue=@"Start preview for exposure analysis · shadows ← brightness → highlights";
}
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sample fromConnection:(AVCaptureConnection *)connection {
 double now=CFAbsoluteTimeGetCurrent(); if(now-self.lastAnalysisTime<.2)return; self.lastAnalysisTime=now;
 @synchronized(self){if(self.framePending)return; self.framePending=YES;}
 CVPixelBufferRef pixel=CMSampleBufferGetImageBuffer(sample);
 if(!pixel){@synchronized(self){self.framePending=NO;}return;}
 CIImage *source=[CIImage imageWithCVPixelBuffer:pixel]; CGFloat scale=640.0/source.extent.size.width; CIImage *small=[source imageByApplyingTransform:CGAffineTransformMakeScale(scale,scale)];
 NSUInteger width=640,height=(NSUInteger)llround(source.extent.size.height*scale); NSMutableData *data=[NSMutableData dataWithLength:width*height*4];
 CGColorSpaceRef color=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
 [self.imageContext render:small toBitmap:data.mutableBytes rowBytes:width*4 bounds:CGRectMake(0,0,width,height) format:kCIFormatBGRA8 colorSpace:color]; CGColorSpaceRelease(color);
 FrameAnalysis *result=[FrameAnalysis analyzeBGRA:data.bytes width:width height:height stride:width*4];
 FaceMeter meter={0}; CGRect face=CGRectZero; NSInteger faceCount=0;
 if(self.optimizing) {
 NSBitmapImageRep *rep=(NSBitmapImageRep *)result.image.representations.firstObject;
 VNDetectFaceRectanglesRequest *request=[VNDetectFaceRectanglesRequest new];
 VNImageRequestHandler *handler=[[VNImageRequestHandler alloc]initWithCGImage:rep.CGImage options:@{}];
 NSError *error=nil;
 if([handler performRequests:@[request] error:&error]) {
 for(VNFaceObservation *candidate in request.results)if(candidate.confidence>=.7 && candidate.boundingBox.size.width*candidate.boundingBox.size.height>=.012){
 faceCount++; CGRect r=candidate.boundingBox; face=CGRectMake(r.origin.x,1-CGRectGetMaxY(r),r.size.width,r.size.height);
 }
 if(faceCount==1)meter=MeasureFace(data.bytes,width,height,width*4,face);
 }
 }

 dispatch_async(dispatch_get_main_queue(),^{
 if(self.previewActive && [self.session.outputs containsObject:output]) {
 if(self.optimizing)[self processMeter:meter face:face count:faceCount capturedAt:now];
 self.latestFrame=result.image; self.overlay.warnings=result.warnings; [self.overlay setNeedsDisplay:YES];
 self.histogram.bins=result.histogram; [self.histogram setNeedsDisplay:YES]; self.captureButton.enabled=YES;
 self.analysisLabel.stringValue=[NSString stringWithFormat:@"Near clipping: %.1f%% highlights (red) · %.1f%% shadows (blue)\nWhole frame · warnings are preview-only · histogram: dark → bright",result.highlightPercent,result.shadowPercent];
 }
 @synchronized(self){self.framePending=NO;}
 });
}
- (void)targetChanged:(id)sender {
 self.optimizeLabel.stringValue=[NSString stringWithFormat:@"Face brightness target: %.0f%% · Use Optimize once to apply",self.targetSlider.doubleValue];
}
- (void)finishOptimization:(NSString *)message {
 self.optimizing=NO; self.optimizerGeneration++; [self.optimizerTimeout invalidate]; self.optimizerTimeout=nil;
 self.optimizeButton.title=@"Optimize once"; self.targetSlider.enabled=YES; self.backlitButton.enabled=YES;
 self.undoOptimizeButton.enabled=self.optimizerUndo!=nil && !self.busy;
 self.optimizeLabel.stringValue=message; self.overlay.faceRect=CGRectZero; [self.overlay setNeedsDisplay:YES];
 if(!self.busy){[self renderControls];[self updatePresetState];}
}
- (void)optimizationExpired:(id)sender { if(self.optimizing)[self completeBestOptimization:@"Time limit reached · Best measured settings kept. Undo is available."]; }
- (void)optimize:(id)sender {
 if(self.optimizing){[self finishOptimization:@"Stopped · Current settings kept. Use Undo to restore the previous look."];return;}
 if(self.busy)return;
 if(!self.previewActive || !self.latestFrame){self.optimizeLabel.stringValue=@"Start the live preview before optimizing.";return;}
 for(NSString *key in @[@"autoExposure",@"exposure",@"gain"]){if(![[self control:key][@"writable"] boolValue]){self.optimizeLabel.stringValue=@"This camera does not expose the controls needed for optimization.";return;}}
 self.optimizing=YES; self.optimizerGeneration++;self.optimizerSteps=0;self.optimizerSamples=0;self.previousFace=CGRectZero;self.optimizerReadyAt=0;self.optimizerBestScore=INFINITY;self.optimizerBestValues=nil;self.optimizerLastDirection=0;self.optimizerReversals=0;self.optimizerFinishMessage=nil;
 self.targetBrightness=self.targetSlider.doubleValue/100.; self.targetSlider.enabled=NO; self.optimizerBacklit=self.backlitButton.state==NSControlStateValueOn; self.backlitButton.enabled=NO;
 self.optimizeButton.title=@"Stop optimizing";self.undoOptimizeButton.enabled=NO;
 self.optimizeLabel.stringValue=@"Looking for one face · Keep your head reasonably still";
 // Capture reference without enabling comparison, so the full metering area stays visible.
 self.overlay.beforeImage=self.latestFrame;self.compareButton.enabled=YES;self.captureButton.title=@"Recapture before";
 self.optimizerTimeout=[NSTimer scheduledTimerWithTimeInterval:45 target:self selector:@selector(optimizationExpired:) userInfo:nil repeats:NO];
 [self renderControls];
}
- (void)processMeter:(FaceMeter)meter face:(CGRect)face count:(NSInteger)count capturedAt:(double)timestamp {
 if(!self.optimizing || self.busy || timestamp<self.optimizerReadyAt)return;
 self.overlay.faceRect=meter.valid?face:CGRectZero;
 if(!meter.valid || count!=1){self.optimizerSamples=0;self.previousFace=CGRectZero;self.optimizeLabel.stringValue=count>1?@"Paused · Keep just one face in view":@"Paused · Face the camera so your face can be measured";return;}
 if(!CGRectIsEmpty(self.previousFace)){
 CGRect intersection=CGRectIntersection(face,self.previousFace); double overlap=CGRectIsNull(intersection)?0:intersection.size.width*intersection.size.height;
 double total=face.size.width*face.size.height+self.previousFace.size.width*self.previousFace.size.height-overlap;
 if(total<=0 || overlap/total<.7){self.optimizerSamples=0;self.previousFace=face;self.optimizeLabel.stringValue=@"Waiting for a stable face position…";return;}
 }
 self.previousFace=face;
 if(self.optimizerSamples==0){self.meterSum=0;self.meterHigh=0;self.meterClipped=0;}
 self.meterSum+=meter.median;self.meterHigh+=meter.high;self.meterClipped+=meter.clipped;self.optimizerSamples++;
 if(self.optimizerSamples<3)return;
 meter.median=self.meterSum/3;meter.high=self.meterHigh/3;meter.clipped=self.meterClipped/3;self.optimizerSamples=0;
 if(self.optimizerSteps==0){[self initializeOptimization];return;}
 double score=ExposureScore(meter,self.targetBrightness);
 if(score<self.optimizerBestScore){
 self.optimizerBestScore=score;NSMutableDictionary *best=[NSMutableDictionary new];
 for(NSString *key in @[@"autoExposure",@"exposure",@"gain",@"autoWB",@"whiteBalance"]){NSDictionary *c=[self control:key];if([c[@"writable"] boolValue])best[key]=c[@"value"];}
 self.optimizerBestValues=best;
 }
 if(ExposureAcceptable(meter,self.targetBrightness) && [[self control:@"exposure"][@"value"] intValue]<=333){
 [self finishOptimization:[NSString stringWithFormat:@"Optimized & locked · Face brightness %.0f%% · Save a look to keep it",meter.median*100]];return;
 }
 if(self.optimizerSteps>=24){[self completeBestOptimization:@"Best measured exposure kept · Adjust face brightness to taste."];return;}
 NSDictionary *exposure=[self control:@"exposure"],*gain=[self control:@"gain"];
 NSDictionary *step=ExposureAdjustmentWithGainLimit(meter,self.targetBrightness,[exposure[@"value"] intValue],[gain[@"value"] intValue],[exposure[@"min"] intValue],[exposure[@"max"] intValue],[exposure[@"step"] intValue],[gain[@"min"] intValue],[gain[@"max"] intValue],[gain[@"step"] intValue],self.optimizerBacklit?255:120);
 if(!step){[self completeBestOptimization:@"Best measured exposure kept · More light may help. Undo is available."];return;}
 NSMutableDictionary *control=[self control:step[@"key"]];
 NSInteger direction=[step[@"value"] intValue]>[control[@"value"] intValue]?1:-1;
 if(self.optimizerLastDirection && direction!=self.optimizerLastDirection)self.optimizerReversals++;
 self.optimizerLastDirection=direction;
 if(self.optimizerReversals>=2){[self completeBestOptimization:@"Best measured exposure kept · Stopped fine-tuning to avoid brightness oscillation."];return;}
 [self optimizerWrite:^BOOL{return [self.camera setControl:control value:[step[@"value"] intValue]] && [self.camera refresh];} message:step[@"reason"]];
}
- (void)initializeOptimization {
 // Snapshot immediately before the first hardware write, after a stable face is found.
 [self optimizerWrite:^BOOL{
 if(![self.camera refresh])return NO;
 NSMutableDictionary *original=[NSMutableDictionary new];
 for(NSString *key in @[@"autoExposure",@"exposure",@"gain",@"autoWB",@"whiteBalance"]){NSDictionary *c=[self control:key];if([c[@"writable"] boolValue])original[key]=c[@"value"];}
 self.optimizerUndo=[original copy];
 NSMutableDictionary *locked=[original mutableCopy];locked[@"autoExposure"]=@1;if(locked[@"autoWB"])locked[@"autoWB"]=@0;
 return [self applyValues:locked];
 } message:@"Automatic exposure disabled · Current white balance locked"];
}
- (void)optimizerWrite:(BOOL (^)(void))work message:(NSString *)message {
 if(!self.optimizing || self.busy)return;
 NSUInteger generation=self.optimizerGeneration; self.busy=YES;self.undoOptimizeButton.enabled=NO;self.optimizeLabel.stringValue=message;
 dispatch_async(self.queue,^{BOOL ok=work();NSString *error=[self.camera.error copy];
 dispatch_async(dispatch_get_main_queue(),^{
 self.busy=NO;[self renderControls];[self updatePresetState];
 if(!self.optimizing || generation!=self.optimizerGeneration){self.undoOptimizeButton.enabled=self.optimizerUndo!=nil;return;}
 if(!ok){[self finishOptimization:[NSString stringWithFormat:@"Stopped: %@ · Undo is available",error.length?error:@"Camera rejected an adjustment"]];return;}
 if(self.optimizerFinishMessage){NSString *finished=self.optimizerFinishMessage;self.optimizerFinishMessage=nil;[self finishOptimization:finished];return;}
 self.optimizerSteps++;self.optimizerReadyAt=CFAbsoluteTimeGetCurrent()+1.0;
 self.optimizeLabel.stringValue=[NSString stringWithFormat:@"%@ · Measuring after adjustment %ld",message,(long)self.optimizerSteps];
 });});
}
- (void)completeBestOptimization:(NSString *)message {
 [self.optimizerTimeout invalidate];self.optimizerTimeout=nil;
 if(!self.optimizerBestValues || self.busy){[self finishOptimization:message];return;}
 NSDictionary *best=[self.optimizerBestValues copy];self.optimizerFinishMessage=message;
 [self optimizerWrite:^BOOL{return [self applyValues:best];} message:@"Restoring best measured exposure…"];
}
- (void)undoOptimization:(id)sender {
 if(self.busy || self.optimizing || !self.optimizerUndo)return;
 NSDictionary *values=[self.optimizerUndo copy];
 [self perform:^BOOL{BOOL ok=[self applyValues:values];if(ok)dispatch_async(dispatch_get_main_queue(),^{self.optimizerUndo=nil;self.undoOptimizeButton.enabled=NO;self.optimizeLabel.stringValue=@"Previous exposure, gain, and white balance restored.";});return ok;} message:@"Optimization undone"];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
@end
int main(int argc,const char *argv[]) { @autoreleasepool { NSApplication *app=NSApplication.sharedApplication; [app setActivationPolicy:NSApplicationActivationPolicyRegular]; App *delegate=[App new]; app.delegate=delegate; [app run]; } return 0; }
