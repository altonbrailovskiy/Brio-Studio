#import "../Sources/Optimizer.h"
int main(void){@autoreleasepool{
 NSMutableData *image=[NSMutableData dataWithLength:100*100*4];unsigned char *p=image.mutableBytes;
 // White background, mid-gray face ROI: background must not affect the meter.
 for(int y=0;y<100;y++)for(int x=0;x<100;x++){int v=(x>=25 && x<75 && y>=25 && y<75)?128:255;int i=(y*100+x)*4;p[i]=p[i+1]=p[i+2]=v;p[i+3]=255;}
 FaceMeter m=MeasureFace(p,100,100,400,CGRectMake(.25,.25,.5,.5));
 NSCAssert(m.valid && fabs(m.median-128./255)<.001 && m.clipped==0,@"Face ROI must ignore bright background");
 NSCAssert(!MeasureFace(p,100,100,400,CGRectMake(2,2,.2,.2)).valid,@"Invalid ROI must pause");
 NSCAssert(ExposureAcceptable(m,.5),@"Balanced brightness should stop");
 NSCAssert(ExposureAdjustment(m,.5,333,75,5,2500,1,0,255,1)==nil,@"No unnecessary writes");
 m.median=.2;m.high=.4;m.clipped=0;
 NSDictionary *a=ExposureAdjustment(m,.5,100,40,5,2500,1,0,255,1);
 NSCAssert([a[@"key"] isEqual:@"exposure"] && [a[@"value"]intValue]>100,@"Dark scene raises exposure before gain");
 a=ExposureAdjustment(m,.5,333,40,5,2500,1,0,255,1);
 NSCAssert([a[@"key"]isEqual:@"gain"] && [a[@"value"]intValue]==48,@"Gain rises in small steps at exposure cap");
 NSCAssert(!ExposureAdjustment(m,.5,333,120,5,2500,1,0,255,1),@"Gain noise limit");
 m.median=.8;m.high=.98;m.clipped=.05;
 a=ExposureAdjustment(m,.5,333,40,5,2500,1,0,255,1);
 NSCAssert([a[@"key"]isEqual:@"gain"] && [a[@"value"]intValue]<40,@"Bright scene lowers gain first");
 a=ExposureAdjustment(m,.5,333,0,5,2500,1,0,255,1);
 NSCAssert([a[@"key"]isEqual:@"exposure"] && [a[@"value"]intValue]<333,@"Lower shutter time at minimum gain");
 a=ExposureAdjustment(m,.5,1000,0,5,2500,1,0,255,1);
 NSCAssert([a[@"value"]intValue]<=333,@"Motion exposure cap");
 m.valid=NO;NSCAssert(!ExposureAdjustment(m,.5,333,40,5,2500,1,0,255,1),@"No writes with invalid measurement");
 for(int i=0;i<100*100;i++){p[i*4]=80;p[i*4+1]=140;p[i*4+2]=255;}
 FaceMeter warm=MeasureFace(p,100,100,400,CGRectMake(.25,.25,.5,.5));
 NSCAssert(warm.clipped==0,@"A clipped red channel alone must not darken warm skin");
 FaceMeter good={YES,.55,.8,0},dark={YES,.3,.6,0};
 NSCAssert(ExposureScore(good,.55)<ExposureScore(dark,.55),@"Best-result score favors face brightness");
 FaceMeter dim={YES,.3,.6,0};
 NSDictionary *backlit=ExposureAdjustmentWithGainLimit(dim,.6,333,120,5,2500,1,0,255,1,255);
 NSCAssert([backlit[@"value"]intValue]==128,@"Backlit mode must exceed conservative gain cap");
 NSCAssert(!ExposureAdjustmentWithGainLimit(dim,.6,333,255,5,2500,1,0,255,1,255),@"Backlit mode must respect hardware limit");
 puts("PASS: face ROI, stability target, adjustment direction, exposure/gain limits, missing face");
}}
