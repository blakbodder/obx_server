//
//  obx.h
//  obx_server
//

#ifndef obex_h
#define obex_h
#import <IOBluetooth/IOBluetooth.h>

@interface  OBEXSERVER : NSObject <IOBluetoothL2CAPChannelDelegate>

@property IOBluetoothL2CAPChannel* l2capchan;
@property IOBluetoothSDPServiceRecord* service_record;

-(instancetype) init;
-(bool) publish_file_transfer_service;
-(void) l2cap_open_notify:(IOBluetoothUserNotification*)inNotification channel:
    (IOBluetoothL2CAPChannel*) newchan;
- (void)l2capChannelData:(IOBluetoothL2CAPChannel*)l2capChannel data:(void *)dataPointer length:(size_t)dataLength;
-(void) unpublish_service;

@end
#endif /* obex_h */
