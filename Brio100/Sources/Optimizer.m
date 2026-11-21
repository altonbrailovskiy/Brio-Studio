#import "Optimizer.h"
#import <math.h>
FaceMeter MeasureFace(const unsigned char *bytes, NSUInteger width, NSUInteger height, NSUInteger stride, CGRect rect) {
 FaceMeter m={0}; if(!bytes || !width || !height || stride<width*4)return m;
 rect=CGRectIntersection(rect,CGRectMake(0,0,1,1)); if(CGRectIsNull(rect) || rect.size.width<.03 || rect.size.height<.03)return m;
 // Inset the box to reduce hair/background influence; no skin-color assumptions.
 rect=CGRectInset(rect,rect.size.width*.18,rect.size.height*.16);
 NSUInteger bins[256]={0},count=0,clipped=0;
 NSUInteger left=floor(rect.origin.x*width),right=MIN(width,ceil(CGRectGetMaxX(rect)*width));
 NSUInteger top=floor(rect.origin.y*height),bottom=MIN(height,ceil(CGRectGetMaxY(rect)*height));
 for(NSUInteger y=top;y<bottom;y++)for(NSUInteger x=left;x<right;x++) {
 const unsigned char *p=bytes+y*stride+x*4; int l=(54*p[2]+183*p[1]+19*p[0])>>8;bins[l]++;count++;
 if(l>=248)clipped++; // Meter broad luminance clipping, not saturated skin-color channels.
 }
 if(count<100)return m;
 NSUInteger sum=0; BOOL gotMedian=NO;
 for(int i=0;i<256;i++){sum+=bins[i];if(!gotMedian && sum>=count*.5){m.median=i/255.;gotMedian=YES;}if(sum>=count*.9){m.high=i/255.;break;}}
 m.clipped=(double)clipped/count;m.valid=YES;return m;
}
BOOL ExposureAcceptable(FaceMeter m,double target){return m.valid && fabs(m.median-target)<=.045 && m.high<.98 && m.clipped<.05;}
static int stepped(int requested,int current,int minimum,int maximum,int step){step=MAX(1,step);int value=minimum+(int)llround((requested-minimum)/(double)step)*step;value=MAX(minimum,MIN(maximum,value));if(value==current){value=MAX(minimum,MIN(maximum,current+(requested>current?step:-step)));}return value;}
NSDictionary *ExposureAdjustmentWithGainLimit(FaceMeter m,double target,int exposure,int gain,int emin,int emax,int estep,int gmin,int gmax,int gstep,int gainLimit){
 if(!m.valid || !isfinite(m.median) || target<.3 || target>.75)return nil;
 int cap=MIN(emax,333),gainCap=MIN(gmax,gainLimit);if(cap<emin || gainCap<gmin)return nil;
 NSString *key=nil,*reason=nil;int next=0;
 if(exposure>cap){key=@"exposure";next=cap;reason=@"Limiting exposure to preserve motion detail";}
 else if(ExposureAcceptable(m,target))return nil;
 else if(m.median>target+.045 || m.high>=.98 || m.clipped>=.05){
 if(gain>gmin){key=@"gain";next=stepped(gain-8,gain,gmin,gmax,gstep);reason=@"Reducing gain to protect face highlights";}
 else if(exposure>emin){key=@"exposure";next=stepped((int)floor(exposure*.84),exposure,emin,cap,estep);reason=@"Shortening exposure to protect face highlights";}
 }else if(m.median<target-.045){
 if(exposure<cap){key=@"exposure";next=stepped((int)ceil(exposure*1.18),exposure,emin,cap,estep);reason=@"Increasing exposure before adding gain";}
 else if(gain<gainCap){key=@"gain";next=stepped(gain+8,gain,gmin,gainCap,gstep);reason=@"Adding a little gain to brighten your face";}
 }
 return key?@{@"key":key,@"value":@(next),@"reason":reason}:nil;
}

double ExposureScore(FaceMeter m,double target){
 if(!m.valid)return INFINITY;
 return fabs(m.median-target)+2.0*MAX(0,m.clipped-.05)+MAX(0,m.high-.98);
}

NSDictionary *ExposureAdjustment(FaceMeter m,double target,int exposure,int gain,int emin,int emax,int estep,int gmin,int gmax,int gstep){return ExposureAdjustmentWithGainLimit(m,target,exposure,gain,emin,emax,estep,gmin,gmax,gstep,120);}
