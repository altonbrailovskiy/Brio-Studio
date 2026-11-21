#import "Camera.h"
static NSMutableDictionary *find(Camera *camera, NSString *key) { for(NSMutableDictionary *c in camera.controls)if([c[@"key"] isEqual:key])return c; return nil; }
int main(int argc,const char *argv[]) { @autoreleasepool {
 Camera *camera=[Camera new]; if(![camera connect]) { fprintf(stderr,"%s\n",camera.error.UTF8String); return 1; }
 if(argc>1 && strcmp(argv[1],"--self-test")==0) {
 BOOL ok=YES;
 for(NSArray *pair in @[@[@"autoExposure",@"exposure",@1],@[@"autoWB",@"whiteBalance",@0]]) {
 NSMutableDictionary *mode=find(camera,pair[0]), *manual=find(camera,pair[1]);
 if(!mode || !manual)return 2;
 int originalMode=[mode[@"value"] intValue],originalValue=[manual[@"value"] intValue];
 BOOL switched=[camera setControl:mode value:[pair[2] intValue]];
 BOOL wrote=switched && [camera setControl:manual value:originalValue];
 BOOL restored=[camera setControl:mode value:originalMode];
 printf("%s: manual=%s value readback=%s restore=%s\n",[pair[1] UTF8String],switched?"PASS":"FAIL",wrote?"PASS":"FAIL",restored?"PASS":"FAIL");
 ok=ok && switched && wrote && restored;
 }
 NSMutableDictionary *brightness=find(camera,@"brightness"); int original=[brightness[@"value"] intValue];
 int target=original<[brightness[@"max"] intValue]?original+1:original-1;
 BOOL changed=[camera setControl:brightness value:target]; BOOL restored=[camera setControl:brightness value:original];
 printf("brightness: changed readback=%s restore=%s\n",changed?"PASS":"FAIL",restored?"PASS":"FAIL");
 return ok && changed && restored?0:1;
 }
 NSData *data=[NSJSONSerialization dataWithJSONObject:camera.controls options:NSJSONWritingPrettyPrinted error:nil]; puts([[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
 } return 0; }
