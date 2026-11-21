#import <Foundation/Foundation.h>
@interface Camera : NSObject
@property NSMutableArray<NSMutableDictionary *> *controls;
@property NSString *error;
- (BOOL)connect;
- (BOOL)refresh;
- (BOOL)setControl:(NSMutableDictionary *)control value:(int)value;
@end
