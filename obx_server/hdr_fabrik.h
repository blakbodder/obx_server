//
//  hdr_fabrik.h
//  obx_server
//

#ifndef hdr_fabrik_h
#define hdr_fabrik_h

#define HOST_MAX_PKT_LEN 672
#define UNICODE 0x00
#define BYTES 0x40
#define ONEBYTE 0x80
#define FOURBYTE 0xC0

#define COUNT_HDR       0
#define NAME_HDR        1
#define TYPE_HDR        2
#define LENGTH_HDR      3
#define TIME_HDR        4
#define DESCRIPTION_HDR 5
#define TARGET_HDR      6
#define HTTP_HDR        7
#define BODY_HDR        8
#define END_OF_BODY_HDR 9
#define WHO_HDR        10
#define CONNECTION_ID_HDR   11
#define APPARAM_HDR       12
#define AUTHCHAL_HDR      13
#define AUTHRESP_HDR      14
#define CREATOR_HDR       15
#define WANUUID_HDR       16
#define OBJECTCLASS_HDR   17
#define SESSIONPARAM_HDR  18
#define SESSIONSEQ_HDR    19
#define ACTION_ID_HDR     20
#define DESTNAME_HDR      21
#define PERMISSIONS_HDR   22
#define SRM_HDR_HDR       23
#define SRM_FLAGS_HDR     24

void hexdump(uint8_t* data, int16_t n);
void init_obex_cmd(uint8_t cmd);
void add_name_hdr(char *name);
void add_length_hdr(uint32_t length);
void add_body_hdr(uint8_t* body, uint16_t blen, bool isendof);
void add_version_flags_maxpkt(void);
void complete_obex(void);
bool parse_input(uint8_t* indata, uint16_t indatalen);
bool parse_connect_response(uint8_t* indata, uint16_t indatalen);
uint32_t extract_length(void);
bool extract_body(uint8_t **body_ptr, uint16_t *length, bool *end_of);
bool extract_name(uint8_t **name);
void free_obx_hdrs(void);

#endif /* hdr_fabrik_h */

