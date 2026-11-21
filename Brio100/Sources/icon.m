#import <Cocoa/Cocoa.h>
static NSColor *rgb(CGFloat r,CGFloat g,CGFloat b){return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1];}
static void roundrect(NSRect r,CGFloat radius,NSColor *color){[color setFill];[[NSBezierPath bezierPathWithRoundedRect:r xRadius:radius yRadius:radius]fill];}
int main(int argc,const char *argv[]) { @autoreleasepool {
 if(argc!=2)return 1;
 NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc]initWithBitmapDataPlanes:NULL pixelsWide:1024 pixelsHigh:1024 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
 [NSGraphicsContext saveGraphicsState]; [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
 NSBezierPath *tile=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(52,52,920,920) xRadius:210 yRadius:210];
 NSGradient *background=[[NSGradient alloc]initWithStartingColor:rgb(.14,.19,.23) endingColor:rgb(.025,.045,.065)]; [background drawInBezierPath:tile angle:90];
 [rgb(.22,.30,.34) setStroke]; tile.lineWidth=3; [tile stroke];
 roundrect(NSMakeRect(433,235,158,130),28,rgb(.19,.27,.30));
 roundrect(NSMakeRect(324,213,376,54),27,rgb(.34,.46,.49));
 NSBezierPath *body=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(170,324,684,416) xRadius:115 yRadius:115];
 NSGradient *metal=[[NSGradient alloc]initWithStartingColor:rgb(.27,.36,.39) endingColor:rgb(.12,.18,.21)]; [metal drawInBezierPath:body angle:90];
 [rgb(.43,.55,.57)setStroke]; body.lineWidth=4; [body stroke];
 [rgb(.025,.05,.065)setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(330,350,364,364)]fill];
 NSBezierPath *ring=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(356,376,312,312)];
 [rgb(.12,.89,.85)setStroke]; ring.lineWidth=21; [ring stroke];
 NSBezierPath *lens=[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(383,403,258,258)];
 NSGradient *glass=[[NSGradient alloc]initWithStartingColor:rgb(.035,.10,.20) endingColor:rgb(.08,.41,.48)]; [glass drawInBezierPath:lens angle:45];
 [rgb(.025,.07,.12)setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(444,464,136,136)]fill];
 [[NSColor colorWithWhite:1 alpha:.28]setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(412,566,73,45)]fill];
 [rgb(.32,1,.83)setFill]; [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(753,596,23,23)]fill];
 [NSGraphicsContext restoreGraphicsState];
 NSData *data=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}]; return [data writeToFile:@(argv[1]) atomically:YES]?0:1;
} }
