//
//  obx.m
//  obx_server
//

#import <Foundation/Foundation.h>
#include "obx.h"
#include "hdr_fabrik.h"
#include "directory.h"
#include <sys/stat.h>

// TODO busyflags for incomming get incomming put. lump with connected
// TODO timer watchdog to reset when things break/jam
// TODO if handling multiple connections need _l2capchan for each
//      better to create connection instance for each client
//      with connection instance having _l2capchan, buffers, working_dirs etc.
// TODO if transport error prompt user to press 'q' to quit
// TODO hsndle ABORT

uint8_t obx_outbuff[672];       // used by hdr_fabrik
uint16_t obx_datalen;
extern uint16_t max_pkt_len;
extern uint16_t remote_max_pkt_len;

bool obx_connected = false;     // TODO ensure connect before get/put/setpath

extern uint16_t max_pkt_len;
uint32_t infile_length, get_bytes_received = 0;

uint8_t inget_name[128];     // could be filename or dir name
FILE* inget_file = NULL;
DIR* inget_dir = NULL;
uint32_t inget_len;         // file_len or dir_list_len
uint32_t inget_bytes_left = 0;
char list_dir[1024];
int list_dir_len;
struct dirent* dir_entry = NULL;
char download_path[1024];

uint32_t file_length(FILE* f)
{
    long ll;
    fseek(f, 0, SEEK_END);
    ll = ftell(f);
    printf("ll = %ld\n", ll);
    fseek(f, 0, SEEK_SET);
    return (ll & 0xffffffffL);
}

bool prune_path(void)
{
    int k = strlen(download_path) - 2;
    
    while (k>0 && download_path[k] != '/') k--;
    if (k<0) { download_path[0] = '/'; download_path[1] = 0;  return false; }
    download_path[k+1] = 0;
    printf("pruned path = %s\n", download_path);
    return true;
}

void incoming_connect(uint8_t *dataptr, int16_t datalen, IOBluetoothL2CAPChannel* l2capchan)
{
    uint8_t* inptr;
    printf("incoming_connect\n");
    if (datalen < 7) {
        printf("bad connect request\n");
        obx_outbuff[0] = kOBEXResponseCodeBadRequestWithFinalBit;
        obx_outbuff[1] = 0;  obx_outbuff[2] = 3;    // total length
        obx_datalen = 3;
    }
    else {
        inptr = dataptr + 5;
        remote_max_pkt_len = ntohs(*((uint16_t*) inptr));
        printf("remote max pkt len=%d\n", remote_max_pkt_len);
        if (remote_max_pkt_len < HOST_MAX_PKT_LEN)  max_pkt_len = remote_max_pkt_len;
        else  max_pkt_len = HOST_MAX_PKT_LEN;
        init_obex_cmd(kOBEXResponseCodeSuccessWithFinalBit);
        add_version_flags_maxpkt();
        complete_obex();
        obx_connected = true;   // maybe only when write done . need refcon with every write
    }
    [ l2capchan writeAsync: obx_outbuff length: obx_datalen refcon: nil ];
}

void compile_get_response(uint8_t *buff, uint16_t bytes_read, bool endof)
{
    init_obex_cmd(kOBEXResponseCodeSuccessWithFinalBit);
    add_name_hdr(inget_name);
    add_length_hdr(inget_len);
    if (bytes_read)  add_body_hdr(buff, bytes_read, endof);
    complete_obex();
}

void incoming_get(uint8_t *dataptr, int16_t datalen, IOBluetoothL2CAPChannel* l2capchan)
{
    uint8_t* filename;
    char file_path[1024];
    uint8_t fbuff[1024];    // fbuff needs to be big because dir entires can be long
    uint16_t bytes_read;
    bool endof;
    
    if (inget_file) {   // file open so send next chunk
        bytes_read = fread(fbuff, 1, 512, inget_file);
        inget_bytes_left -= bytes_read;
        endof = (inget_bytes_left <= 0);
        compile_get_response(fbuff, bytes_read, endof);
        if (endof) { fclose(inget_file);  inget_file = NULL; }
    }
    else {
        if (inget_dir) {    // dir open so send next list-batch
             bytes_read = batch_list(fbuff, 512, inget_dir, &endof);
             inget_bytes_left -= bytes_read;
             compile_get_response(fbuff, bytes_read, endof);
             if (endof)  { closedir(inget_dir); inget_dir = NULL; }
        }
        else {
            parse_input(dataptr, datalen);
            if (extract_name(&filename)) {
                printf("incoming get %s\n", filename);
                // NSString* bund_path;
                // bund_path = [[NSBundle mainBundle] bundlePath ];
                // [bund_path getCString: file_path maxLength: 512 encoding: NSASCIIStringEncoding ];
                              
                // NSLog(@"%@", bund_path);
                // base path of file/dir to retreive from
                // nothing to find in bundle directory unless you copy files into it
                // so maybe set file_path to something like /Users/<username>/Downloads/
                // if porting to a cocoa app with sandbox, add entitlement
                // com.apple.security.files.downloads.read-only or com.apple.security.files.user-selected.read-only

                strcpy(file_path, download_path);
                printf("working directory=%s\n", file_path );
                
                // drop leading / if present
                if (*filename == '/') strncat(file_path, filename+1, 127);
                else  strncat(file_path, filename, 128);
                printf("path=%s\n", file_path);
    
                if (is_directory(file_path)) {
                    printf("is directory\n");
                    strcpy(list_dir, file_path);
                    list_dir_len = strlen(list_dir);
                    // drop trailing /
                    if (list_dir[list_dir_len] == '/') {  list_dir[list_dir_len] = 0;  list_dir_len--; }
                    inget_dir = opendir(list_dir);
                    if (inget_dir) {
                        strncpy(inget_name, filename, 128);
                        inget_bytes_left = inget_len = dir_list_len(inget_dir);
                        printf("dir list len = %d\n", inget_len);
                        bytes_read = batch_list(fbuff, 512, inget_dir, &endof);
                        inget_bytes_left -= bytes_read;
                        compile_get_response(fbuff, bytes_read, endof);
                        if (endof)  { closedir(inget_dir); inget_dir = NULL; }
                    }
                    else  {
                        printf("no can open dir\n");
                        obx_outbuff[0] = kOBEXResponseCodeForbiddenWithFinalBit;
                        obx_outbuff[1] = 0;  obx_outbuff[2] = 3;    // total length
                        obx_datalen = 3;
                    }
                }
                else {
                    inget_file = fopen(file_path, "rb");
                    if (inget_file) {
                        strncpy(inget_name, filename, 128);
                        inget_bytes_left = inget_len = file_length(inget_file);
                        bytes_read = fread(fbuff, 1, 512, inget_file);
                        inget_bytes_left -= bytes_read;
                        endof = (inget_bytes_left <= 0);
                        compile_get_response(fbuff, bytes_read, endof);
                        if (endof)  { fclose(inget_file); inget_file = NULL; } // TODO free header list
                    }
                    else {
                        printf("file not found\n");
                        obx_outbuff[0] = kOBEXResponseCodeNotFoundWithFinalBit;
                        obx_outbuff[1] = 0;  obx_outbuff[2] = 3;    // total length
                        obx_datalen = 3;
                    }
                }
            }
            else  {
                printf("no name header\n");
                obx_outbuff[0] = kOBEXResponseCodeBadRequestWithFinalBit;
                obx_outbuff[1] = 0;  obx_outbuff[2] = 3;    // total length
                obx_datalen = 3;
            }
        }
        free_obx_hdrs();
    }
   // [ rfcommchan writeAsync: obx_outbuff length: obx_datalen refcon: nil ];
    [ l2capchan writeAsync: obx_outbuff length: obx_datalen refcon: nil ];
}

uint32_t put_file_len=0;
uint32_t put_bytes_received=0;
FILE* put_file = NULL;
uint8_t cont[] = { 0x90, 0x00, 0x03 };
uint8_t succ[] = { 0xa0, 0x00, 0x03 };

void write_data_to_file(IOBluetoothL2CAPChannel* l2capChannel)
{
    uint8_t* bod_ptr;
    uint16_t bodlen;
    bool endof;
    
    if (extract_body(&bod_ptr, &bodlen, &endof)) {
        //hexdump(bod_ptr, bodlen);
        fwrite(bod_ptr, 1, bodlen, put_file);
        put_bytes_received += bodlen;
        if (! (endof || put_bytes_received >= put_file_len)) {
            [ l2capChannel writeAsync: cont length: 3 refcon: nil ];    // send continue
        }
        else {
            [ l2capChannel writeAsync: succ length: 3 refcon: nil ];    //-> success
            fclose(put_file);  put_file=NULL;  printf("put done\n");
        }
    }
    else { printf("no body\n");  fclose(put_file);  put_file=NULL; }
}

void incoming_put(uint8_t* dataPointer, uint16_t dataLength, IOBluetoothL2CAPChannel* l2capChannel)
{
    uint8_t* filename;
    char file_path[1024];
    struct stat st;

    if (put_file) {
        parse_input(dataPointer, dataLength);
        write_data_to_file(l2capChannel);     // put_file open so save next chunk
        free_obx_hdrs();
    }
    else {
        parse_input(dataPointer, dataLength);
        if (extract_name(&filename)) {
            printf("incoming put %s\n", filename);
            strcpy(file_path, download_path);
            //printf("working directory=%s\n", file_path );
            // drop leading / if present
            if (*filename == '/')  strncat(file_path, filename+1, 127);
            else  strncat(file_path, filename, 128);
            printf("path=%s\n", file_path);
            if (stat(file_path, &st)) {
               put_bytes_received=0;
               put_file = fopen(file_path, "wb");
               put_file_len = extract_length();
               write_data_to_file(l2capChannel);
            }
            else {
                printf("file or dir exists.  REFUSING to overwrite.\n");
                obx_outbuff[0] = kOBEXResponseCodeForbiddenWithFinalBit;
                obx_outbuff[1] = 0;  obx_outbuff[2] = 3;    // total length
                [ l2capChannel writeAsync: obx_outbuff length: 3 refcon: nil];
            }
        }
        else  {
            printf("no name\n");
            obx_outbuff[0] = kOBEXResponseCodeBadRequestWithFinalBit;
            obx_outbuff[1] = 0;  obx_outbuff[2] = 3;    // total length
            [ l2capChannel writeAsync: obx_outbuff length: 3 refcon: nil];
        }
        free_obx_hdrs();
    }
}

void incoming_setpath(uint8_t* dataPointer, uint16_t dataLength, IOBluetoothL2CAPChannel* l2capChannel)
{
    char *path_name;
    char noo_path[1024];
    bool fail = false;
    int k;
    uint8_t flag = *(dataPointer + 3);
    uint8_t konstant = *(dataPointer + 4);
    
    parse_input(dataPointer, dataLength);
    extract_name(&path_name);
    free_obx_hdrs();
    printf("incoming setpath %s.  flag=%d  const=%d.\n",  path_name, flag, konstant);

    // adopt this policy:
    // if flag == goto_parent_dir:
    //      try prune working dir. eg /users/freddy/downloads/ -> /users/freddy/
    // if no path_name do nothing
    // if path_name starts with /  treat as absolute path
    // else append path_name to working directory:  working_dir/ becomes working_dir/path_name/
    if ((flag & 0x01) == 0x01) {
        if (!prune_path())  fail = true;
    }
    if (*path_name) {
        if (*path_name == '/') {
            if (!is_directory(path_name))  fail=true;
            else  strncpy(download_path, path_name, 1024);
        }
        else {
            strncpy(noo_path, download_path, 1024);
            strncat(noo_path, path_name, 1024);
            if (!is_directory(noo_path))  fail = true;
            else  strncpy(download_path, noo_path, 1024);
        }
        k = strlen(download_path)-1;
        if (download_path[k] != '/')  { download_path[++k] = '/';  download_path[++k] = 0; }
        printf("working directory: %s\n", download_path);
    }
    if (fail) obx_outbuff[0] = kOBEXResponseCodeForbiddenWithFinalBit;
    else  obx_outbuff[0] = kOBEXResponseCodeSuccessWithFinalBit;
    obx_outbuff[1] = 0;  obx_outbuff[2] = 3;
    [ l2capChannel writeAsync: obx_outbuff length: 3 refcon: nil ];
}

@implementation OBEXSERVER

-(instancetype) init
{
    char* home;
    self = [ super init ];
    [ IOBluetoothL2CAPChannel registerForChannelOpenNotifications: self selector: @selector(l2cap_open_notify:channel:) withPSM: 0x1001 direction: kIOBluetoothUserNotificationChannelDirectionIncoming ];
    
    [ self publish_file_transfer_service ];
    home = getenv("HOME");
    strncpy(download_path, home, 960);
    strcat(download_path, "/Downloads/");   // /Users/username/Downloads/
    if (!is_directory(download_path))  printf("PROBLEM: %s IS NOT A DIRECTORY\n", download_path);
    return self;
}

-(bool) publish_file_transfer_service
{
    NSString* plist_path;
    NSMutableDictionary* sdpentries;
   // BluetoothSDPServiceRecordHandle serv_rec_handle;
    NSString* bund_path;
    BluetoothL2CAPPSM psm;
    
    bund_path = [[NSBundle mainBundle] bundlePath ];
    //NSLog(@"bundle = %@,", bund_path);
    plist_path = [ [NSBundle mainBundle] pathForResource: @"sdprec" ofType: @"plist"];
    sdpentries = [ NSMutableDictionary dictionaryWithContentsOfFile: plist_path ];
    // bizzarly, this creates L2CAP channel and listens
    _service_record = [ IOBluetoothSDPServiceRecord publishedServiceRecordWithDictionary: sdpentries ];
    if (_service_record) {
        if ( [_service_record getL2CAPPSM: &psm ] == kIOReturnSuccess)
            { printf("service L2CAP chan psm = 0x%x\n", psm);   return true; }
        else  { printf("FAILED getL2CAPPSM\n");  return false; }
    }
    else  printf("FAILED publish service record\n");
    return false;
}

// called when remote device connects
-(void) l2cap_open_notify:(IOBluetoothUserNotification*)inNotification channel:(IOBluetoothL2CAPChannel*) newchan
{
    printf("L2CAP OPEN NOTIFY\n");
    _l2capchan =  newchan;
    // [ inNotification unregister ];
    // allow further connections so pi can obxget more than once
    newchan.delegate = self;
}

// process incoming data
- (void)l2capChannelData: (IOBluetoothL2CAPChannel*)l2capChannel data:(void *)dataPointer length:(size_t)dataLength
{
    uint8_t* udata = (uint8_t*) dataPointer;
    char* home;
    // should check if operations pending
    //hexdump(dataPointer, dataLength);
        
    switch (*udata) {
        case kOBEXOpCodeConnect:
            incoming_connect(dataPointer, dataLength, l2capChannel);
            break;
                
        case kOBEXOpCodeGetWithHighBitSet:
            incoming_get(dataPointer, dataLength, l2capChannel);
            break;
        
        case kOBEXOpCodePut:
        case kOBEXOpCodePutWithHighBitSet:
            incoming_put(dataPointer, dataLength, l2capChannel);
            break;
                
        case kOBEXOpCodeSetPath:
            // BEWARE. enabling setpath makes the entire filesystem public
            // incoming_setpath(dataPointer, dataLength, l2capChannel);
            // if allowing setpath, comment out the following 3 lines that send forbidden response
            obx_outbuff[0] = kOBEXResponseCodeForbiddenWithFinalBit;
            obx_outbuff[1] = 0;  obx_outbuff[2] = 3;    // total length
            [ l2capChannel writeAsync: obx_outbuff length: 3 refcon: nil];
            break;
                
        case kOBEXOpCodeDisconnect:
            printf("CLIENT DISCONNECTED\n");
            obx_outbuff[0] = kOBEXResponseCodeSuccessWithFinalBit;
            obx_outbuff[1] = 0;  obx_outbuff[2] = 3;    // total length
            [ l2capChannel writeAsync: obx_outbuff length: 3 refcon: nil];
            obx_connected  = false;
            
            home = getenv("HOME");           //  reset working dir
            strncpy(download_path, home, 960);
            strcat(download_path, "/Downloads/");   // /Users/username/Downloads/
            if (!is_directory(download_path))  printf("PROBLEM: %s IS NOT A DIRECTORY\n", download_path);
            break;
                              
        case kOBEXOpCodeAbort:
            //TODO
            break;
        
        default:
            printf("unrecognised request\n");
            obx_outbuff[0] = kOBEXResponseCodeBadRequestWithFinalBit;
            obx_outbuff[1] = 0;  obx_outbuff[2] = 3;    // total length
            [ l2capChannel writeAsync:obx_outbuff length: 3 refcon: nil];
    }
}

-(void) unpublish_service
{
    [ _service_record removeServiceRecord ];
}

@end
