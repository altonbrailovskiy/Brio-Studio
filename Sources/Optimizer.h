#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
typedef struct { BOOL valid; double median, high, clipped; } FaceMeter;
FaceMeter MeasureFace(const unsigned char *bytes, NSUInteger width, NSUInteger height, NSUInteger stride, CGRect topLeftRect);
// Returns one bounded control adjustment, or nil when acceptable/at limits.
NSDictionary *ExposureAdjustment(FaceMeter meter, double target, int exposure, int gain, int exposureMin, int exposureMax, int exposureStep, int gainMin, int gainMax, int gainStep);
BOOL ExposureAcceptable(FaceMeter meter, double target);

double ExposureScore(FaceMeter meter, double target);

NSDictionary *ExposureAdjustmentWithGainLimit(FaceMeter meter, double target, int exposure, int gain, int exposureMin, int exposureMax, int exposureStep, int gainMin, int gainMax, int gainStep, int gainLimit);
