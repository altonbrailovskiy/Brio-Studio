#import <Cocoa/Cocoa.h>
// RGB values from the rendered preview, not sensor RAW values.
@interface FrameAnalysis : NSObject
@property NSImage *image;
@property NSImage *warnings;
@property NSArray<NSNumber *> *histogram;
@property double highlightPercent;
@property double shadowPercent;
+ (instancetype)analyzeBGRA:(const unsigned char *)bytes width:(NSUInteger)width height:(NSUInteger)height stride:(NSUInteger)stride;
@end
@interface AnalysisOverlay : NSView
@property NSImage *beforeImage;
@property NSImage *warnings;
@property BOOL showBefore;
@property CGRect faceRect;
@property BOOL showWarnings;
@end
@interface HistogramView : NSView
@property NSArray<NSNumber *> *bins;
@end
BOOL PresetMatches(NSDictionary *saved, NSDictionary *current);
