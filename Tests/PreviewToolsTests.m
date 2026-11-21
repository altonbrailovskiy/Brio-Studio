#import "../Sources/PreviewTools.h"
int main(void){@autoreleasepool{
 unsigned char pixels[]={0,0,0,255, 255,255,255,255, 0,0,255,255, 128,128,128,255};
 FrameAnalysis *a=[FrameAnalysis analyzeBGRA:pixels width:4 height:1 stride:16];
 NSCAssert(a.highlightPercent==50, @"White and clipped red must be flagged");
 NSCAssert(a.shadowPercent==25,@"Only black should be shadow clipped");
 NSBitmapImageRep *mask=(NSBitmapImageRep *)a.warnings.representations.firstObject;
 NSCAssert(mask.bitmapData[12]==0 && mask.bitmapData[13]==0 && mask.bitmapData[14]==0 && mask.bitmapData[15]==0,@"Unflagged pixels must be transparent black for premultiplied alpha");
 NSUInteger sum=0;for(NSNumber *n in a.histogram)sum+=n.unsignedIntegerValue;NSCAssert(sum==4,@"Histogram must count every pixel");
 NSCAssert([a.histogram[0]intValue]==1 && [a.histogram[63]intValue]==1,@"Endpoint histogram bins");
 NSDictionary *manual=@{@"autoExposure":@1,@"exposure":@333,@"gain":@75,@"autoWB":@0,@"whiteBalance":@4200};
 NSCAssert(PresetMatches(manual,manual),@"Exact preset");
 NSMutableDictionary *changed=[manual mutableCopy];changed[@"gain"]=@76;NSCAssert(!PresetMatches(manual,changed),@"Manual edits must be detected");
 NSMutableDictionary *automatic=[manual mutableCopy];automatic[@"autoExposure"]=@8;automatic[@"autoWB"]=@1;
 changed=[automatic mutableCopy];changed[@"exposure"]=@200;changed[@"whiteBalance"]=@5100;NSCAssert(PresetMatches(automatic,changed),@"Automatic fluctuations are not edits");
 changed[@"autoWB"]=@0;NSCAssert(!PresetMatches(automatic,changed),@"Mode edits must be detected");
 NSCAssert(!PresetMatches(manual,@{}),@"Disconnected device cannot match");
 puts("PASS: clipping analysis, histogram, manual/auto preset matching, disconnected state");
}}
