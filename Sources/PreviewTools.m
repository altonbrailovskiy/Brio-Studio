#import "PreviewTools.h"
@implementation FrameAnalysis
+ (instancetype)analyzeBGRA:(const unsigned char *)bytes width:(NSUInteger)width height:(NSUInteger)height stride:(NSUInteger)stride {
 FrameAnalysis *result=[self new]; if(!bytes || !width || !height)return result;
 NSBitmapImageRep *frame=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
 NSBitmapImageRep *mask=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
 NSUInteger bins[64]={0},high=0,low=0;
 for(NSUInteger y=0;y<height;y++)for(NSUInteger x=0;x<width;x++) {
 const unsigned char *p=bytes+y*stride+x*4; unsigned char r=p[2],g=p[1],b=p[0];
 unsigned char *f=frame.bitmapData+y*frame.bytesPerRow+x*4; f[0]=r;f[1]=g;f[2]=b;f[3]=255;
 int luma=(54*r+183*g+19*b)>>8; bins[MIN(63,luma/4)]++;
 BOOL bright=MAX(r,MAX(g,b))>=250, dark=luma<=8; if(bright)high++; if(dark)low++;
 unsigned char *m=mask.bitmapData+y*mask.bytesPerRow+x*4; unsigned char alpha=(bright||dark)&&((x+y)%10<5)?160:0; m[0]=(bright?255:30)*alpha/255;m[1]=(bright?55:145)*alpha/255;m[2]=(bright?40:255)*alpha/255;m[3]=alpha;
 }
 NSMutableArray *hist=[NSMutableArray new]; for(int i=0;i<64;i++)[hist addObject:@(bins[i])]; result.histogram=hist;
 result.highlightPercent=100.0*high/(width*height); result.shadowPercent=100.0*low/(width*height);
 result.image=[[NSImage alloc]initWithSize:NSMakeSize(width,height)]; [result.image addRepresentation:frame];
 result.warnings=[[NSImage alloc]initWithSize:NSMakeSize(width,height)]; [result.warnings addRepresentation:mask]; return result;
}
@end
@implementation AnalysisOverlay
- (BOOL)isFlipped { return YES; }
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (void)drawRect:(NSRect)dirtyRect {
 NSSize size=self.beforeImage?self.beforeImage.size:self.warnings.size; if(size.width<=0)return;
 CGFloat scale=MIN(self.bounds.size.width/size.width,self.bounds.size.height/size.height);
 NSRect rect=NSMakeRect((self.bounds.size.width-size.width*scale)/2,(self.bounds.size.height-size.height*scale)/2,size.width*scale,size.height*scale);
 if(self.showWarnings && self.warnings)[self.warnings drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil];
 if(!CGRectIsEmpty(self.faceRect)){
 NSRect f=NSMakeRect(rect.origin.x+self.faceRect.origin.x*rect.size.width,rect.origin.y+self.faceRect.origin.y*rect.size.height,self.faceRect.size.width*rect.size.width,self.faceRect.size.height*rect.size.height);
 [NSColor.systemTealColor setStroke];NSBezierPath *box=[NSBezierPath bezierPathWithRect:f];box.lineWidth=2;[box stroke];
 }
 if(self.showBefore && self.beforeImage) {
 [NSGraphicsContext saveGraphicsState]; NSRectClip(NSMakeRect(rect.origin.x,rect.origin.y,rect.size.width/2,rect.size.height));
 [self.beforeImage drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1 respectFlipped:YES hints:nil]; [NSGraphicsContext restoreGraphicsState];
 [NSColor.whiteColor setFill]; NSRectFill(NSMakeRect(NSMidX(rect)-1,rect.origin.y,2,rect.size.height));
 NSDictionary *attributes=@{NSFontAttributeName:[NSFont boldSystemFontOfSize:12],NSForegroundColorAttributeName:NSColor.whiteColor,NSBackgroundColorAttributeName:[NSColor colorWithWhite:0 alpha:.7]};
 [@" BEFORE · FROZEN " drawAtPoint:NSMakePoint(rect.origin.x+8,rect.origin.y+8) withAttributes:attributes];
 [@" AFTER · LIVE " drawAtPoint:NSMakePoint(NSMidX(rect)+8,rect.origin.y+8) withAttributes:attributes];
 }
}
@end
@implementation HistogramView
- (void)drawRect:(NSRect)dirtyRect {
 [[NSColor colorWithWhite:.08 alpha:1]setFill]; [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6 yRadius:6]fill];
 double peak=1; for(NSNumber *n in self.bins)peak=MAX(peak,n.doubleValue);
 CGFloat width=self.bounds.size.width/64.;
 [NSColor.systemTealColor setFill]; for(NSUInteger i=0;i<self.bins.count;i++){CGFloat h=(self.bounds.size.height-5)*sqrt(self.bins[i].doubleValue/peak); NSRectFill(NSMakeRect(i*width,0,MAX(1,width-1),h));}
}
@end
BOOL PresetMatches(NSDictionary *saved, NSDictionary *current) {
 if(!saved.count || !current.count)return NO;
 for(NSString *key in saved) {
 if(([key isEqual:@"exposure"] || [key isEqual:@"gain"]) && [saved[@"autoExposure"] intValue]!=1)continue;
 if([key isEqual:@"whiteBalance"] && [saved[@"autoWB"] boolValue])continue;
 if([key isEqual:@"focus"] && [saved[@"autoFocus"] boolValue])continue;
 if(![saved[key] isEqual:current[key]])return NO;
 } return YES;
}
