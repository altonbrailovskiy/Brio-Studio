#import "Camera.h"
#import <IOKit/IOKitLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/usb/IOUSBLib.h>

typedef struct { const char *key, *label; int terminal, selector, bytes, bit, signedValue, kind; } Spec;
static const Spec specs[] = {
 {"autoExposure","Exposure mode",1,2,1,1,0,2},
 {"exposure","Exposure · 0.1 ms",1,4,4,3,0,0},
 {"priority","Allow variable frame rate",1,3,1,2,0,1},
 {"gain","Gain",0,4,2,9,0,0},
 {"autoWB","Automatic white balance",0,11,1,12,0,1},
 {"whiteBalance","White balance · Kelvin",0,10,2,6,0,0},
 {"brightness","Brightness",0,2,2,0,1,0},
 {"contrast","Contrast",0,3,2,1,0,0},
 {"saturation","Saturation",0,7,2,3,0,0},
 {"sharpness","Sharpness",0,8,2,4,0,0},
 {"gamma","Gamma",0,9,2,5,0,0},
 {"hue","Hue",0,6,2,2,1,0},
 {"backlight","Backlight compensation",0,1,2,8,0,0},
 {"frequency","Anti-flicker",0,5,1,10,0,3},
 {"autoFocus","Automatic focus",1,8,1,17,0,1},
 {"focus","Focus",1,6,2,5,0,0},
 {"zoom","Zoom",1,11,2,9,0,0}
};
@implementation Camera {
 IOUSBDeviceInterface500 **usb;
 uint8_t interfaceNumber, terminalID, processingID;
 uint64_t terminalBits, processingBits;
 BOOL opened;
}
- (instancetype)init { if ((self=[super init])) { _controls=[NSMutableArray new]; _error=@""; } return self; }
- (void)close { if(usb) { if(opened)(*usb)->USBDeviceClose(usb); (*usb)->Release(usb); usb=NULL; } opened=NO; }
- (void)dealloc { [self close]; }
- (BOOL)transfer:(int)request selector:(int)selector unit:(int)unit bytes:(int)bytes value:(int *)value signed:(BOOL)isSigned {
 if(!usb) return NO;
 uint8_t data[4]={0};
 if(request==1) for(int i=0;i<bytes;i++) data[i]=((uint32_t)*value>>(i*8))&255;
 IOUSBDevRequestTO r={0}; r.bmRequestType=request==1?0x21:0xa1; r.bRequest=request;
 r.wValue=selector<<8; r.wIndex=(unit<<8)|interfaceNumber; r.wLength=bytes; r.pData=data;
 r.noDataTimeout=750; r.completionTimeout=1000;
 IOReturn status=(*usb)->DeviceRequestTO(usb,&r);
 if(status!=kIOReturnSuccess || r.wLenDone!=(UInt32)bytes) { self.error=[NSString stringWithFormat:@"Camera request failed (0x%08x). Reconnect the camera or close other camera-control apps.",status]; return NO; }
 if(request!=1) { uint32_t result=0; for(int i=0;i<bytes;i++) result|=(uint32_t)data[i]<<(i*8); if(isSigned && bytes==2) *value=(int16_t)result; else *value=(int)result; }
 return YES;
}
- (BOOL)read:(int)request control:(NSDictionary *)c value:(int *)value {
 return [self transfer:request selector:[c[@"selector"] intValue] unit:[c[@"unit"] intValue] bytes:[c[@"bytes"] intValue] value:value signed:[c[@"signed"] boolValue]];
}
- (BOOL)connect {
 [self close]; [_controls removeAllObjects]; terminalBits=processingBits=0; terminalID=processingID=0;
 io_iterator_t iterator=0;
 CFMutableDictionaryRef match=IOServiceMatching("IOUSBHostDevice");
 int vendor=0x046d, product=0x094c;
 CFNumberRef v=CFNumberCreate(NULL,kCFNumberIntType,&vendor), p=CFNumberCreate(NULL,kCFNumberIntType,&product);
 CFDictionarySetValue(match,CFSTR("idVendor"),v); CFDictionarySetValue(match,CFSTR("idProduct"),p); CFRelease(v); CFRelease(p);
 IOServiceGetMatchingServices(kIOMainPortDefault,match,&iterator);
 io_service_t service=IOIteratorNext(iterator); IOObjectRelease(iterator);
 if(!service) { self.error=@"Brio 100 is not connected. Plug it in, then click Reconnect."; return NO; }
 IOCFPlugInInterface **plugin=NULL; SInt32 score=0;
 IOReturn result=IOCreatePlugInInterfaceForService(service,kIOUSBDeviceUserClientTypeID,kIOCFPlugInInterfaceID,&plugin,&score); IOObjectRelease(service);
 if(result==0 && plugin) { (*plugin)->QueryInterface(plugin,CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID500),(LPVOID *)&usb); IODestroyPlugInInterface(plugin); }
 if(!usb) { self.error=@"macOS could not access the USB camera controls."; return NO; }
 IOUSBConfigurationDescriptorPtr config=NULL;
 if((*usb)->GetConfigurationDescriptorPtr(usb,0,&config)!=0 || !config) { self.error=@"Unable to read camera capabilities."; [self close]; return NO; }
 const uint8_t *raw=(const uint8_t *)config; int total=USBToHostWord(config->wTotalLength); BOOL video=NO;
 for(int offset=0;offset+2<=total;) {
 const uint8_t *d=raw+offset; int length=d[0]; if(length<2 || offset+length>total)break;
 if(d[1]==4 && length>=9) { video=d[5]==14 && d[6]==1; if(video)interfaceNumber=d[2]; }
 if(video && d[1]==0x24 && length>=3) {
 if(d[2]==2 && length>=15 && d[4]==1 && d[5]==2 && 15+d[14]<=length) { terminalID=d[3]; for(int j=0;j<MIN(d[14],8);j++)terminalBits|=(uint64_t)d[15+j]<<(j*8); }
 if(d[2]==5 && length>=8 && 8+d[7]<=length) { processingID=d[3]; for(int j=0;j<MIN(d[7],8);j++)processingBits|=(uint64_t)d[8+j]<<(j*8); }
 } offset+=length;
 }
 result=(*usb)->USBDeviceOpen(usb);
 if(result!=0) { self.error=[NSString stringWithFormat:@"USB access unavailable (0x%08x). Close other control apps and reconnect.",result]; [self close]; return NO; } opened=YES;
 for(unsigned i=0;i<sizeof(specs)/sizeof(Spec);i++) {
 Spec s=specs[i]; if(!((s.terminal?terminalBits:processingBits)&((uint64_t)1<<s.bit)))continue;
 NSMutableDictionary *c=[@{@"key":@(s.key),@"label":@(s.label),@"selector":@(s.selector),@"unit":@(s.terminal?terminalID:processingID),@"bytes":@(s.bytes),@"signed":@(s.signedValue),@"kind":@(s.kind)} mutableCopy];
 int info=0,current=0,minimum=0,maximum=1,step=1,def=0;
 if(![self transfer:0x86 selector:s.selector unit:[c[@"unit"] intValue] bytes:1 value:&info signed:NO] || !(info&1) || ![self read:0x81 control:c value:&current]) continue;
 BOOL ranged=YES;
 if(s.kind==0) ranged=[self read:0x82 control:c value:&minimum] && [self read:0x83 control:c value:&maximum];
 if(s.kind==3) { minimum=0; maximum=2; [self read:0x83 control:c value:&maximum]; }
 if(s.kind==0 || s.kind==2) [self read:0x84 control:c value:&step];
 BOOL hasDefault=[self read:0x87 control:c value:&def];
 [c addEntriesFromDictionary:@{@"value":@(current),@"min":@(minimum),@"max":@(maximum),@"step":@(MAX(1,step)),@"default":@(def),@"hasDefault":@(hasDefault),@"writable":@((info&2)!=0 && ranged),@"info":@(info)}]; [_controls addObject:c];
 }
 self.error=_controls.count?@"":@"The camera returned no readable controls."; return _controls.count>0;
}
- (BOOL)refresh {
 BOOL success=YES;
 for(NSMutableDictionary *c in _controls) { int value=0,info=0; if([self read:0x81 control:c value:&value]) c[@"value"]=@(value); else success=NO;
 if([self transfer:0x86 selector:[c[@"selector"] intValue] unit:[c[@"unit"] intValue] bytes:1 value:&info signed:NO])c[@"info"]=@(info); }
 if(success)self.error=@""; return success;
}
- (BOOL)setControl:(NSMutableDictionary *)c value:(int)value {
 if(![c[@"writable"] boolValue])return NO;
 int kind=[c[@"kind"] intValue];
 if(kind==0) { int lo=[c[@"min"] intValue],hi=[c[@"max"] intValue],step=[c[@"step"] intValue]; value=MAX(lo,MIN(hi,value)); value=lo+((value-lo)/step)*step; }
 if(kind==1 && value!=0 && value!=1)return NO;
 if(kind==2 && (!(value==1 || value==2 || value==4 || value==8) || !([c[@"step"] intValue]&value)))return NO;
 if(kind==3 && (value<0 || value>[c[@"max"] intValue]))return NO;
 if(![self read:1 control:c value:&value])return NO;
 int actual=0; if(![self read:0x81 control:c value:&actual])return NO;
 c[@"value"]=@(actual);
 if(value!=actual) { self.error=@"The camera did not accept that value. Its current value is shown."; return NO; }
 self.error=@""; return YES;
}
@end
