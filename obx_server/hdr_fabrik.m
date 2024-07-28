//
//  hdr_fabrik.m
//  obx_server
//

#import <Foundation/Foundation.h>
#include <IOBluetooth/OBEX.h>
#include <string.h>
#include "hdr_fabrik.h"
#include <arpa/inet.h>

extern uint8_t obx_outbuff[672];
extern uint16_t obx_datalen;
extern uint8_t *obx_in;
uint8_t *obx_ptr;
uint16_t max_pkt_len = 672;
uint16_t remote_max_pkt_len = 672;      // assume L2CAP default

#define NUM_HEADER_KEYS 4
char unrecognised_hdr[] = "hdr NOT RECOGNISED";
char obx_header_strings[24][16] = { "count", "name", "type", "length",
                                    "time", "description", "target", "http",
                                    "body", "end_of_body", "who", "connectionID" };
// todo rest of strings

struct obx_hdr {
    uint8_t hdr_id;
    union {
        uint8_t int8;
        //uint16_t int16;
        uint32_t int32;
        //uint16_t stringlen;
        uint16_t datalen;
    };
    uint8_t str[128];    // converted from utf-16
    uint8_t *dataptr;
    struct obx_hdr* next;
};

struct obx_hdr* obx_hdr_list = NULL;

char nib[] = "0123456789ABCDEF";

void hexdump(uint8_t* data, int16_t n)
{
    int16_t k;
    char hex[64];
    uint8_t *s;
    char *p, hi, lo;
    
    s = data; p = hex;  k=0;
    while (k<n) {
        hi = (*s) >> 4;  lo = (*s) & 0x0f;  s++;
        *p++ = nib[hi];  *p++ = nib[lo];  *p++ = ' ';
        k++;
        if ((k & 0xf)==0)  { *p = 0;  printf("%s\n", hex);  p = hex;}
    }
    if (k & 0xf)  { *p++ = 0;  printf("%s    n=%d\n", hex, n);  p = hex;}
}

void init_obex_cmd(uint8_t cmd)    // set cmd byte and clear header pointers
{
    obx_ptr = obx_outbuff;
    *obx_ptr = cmd;
    obx_ptr += 3;       // leave space for length field
}

void add_name_hdr(char *name)   // also convert to unicode-16
{
    int16_t len = strlen(name);
    char *p;
    uint16_t avail = max_pkt_len - (uint16_t)(obx_ptr - obx_outbuff);

    if (avail >= 2*len+5) {
        *obx_ptr++ = NAME_HDR;
        *((uint16_t*) obx_ptr) = htons(2*len+5);
        obx_ptr += 2;
        p = name;
        while (*p) {        // ascii to big-end unicode
            *obx_ptr++ = 0;
            *obx_ptr++ = *p++;
        }
        *obx_ptr++ = 0;  *obx_ptr++ = 0;    //null terminator
        
    }
    else  printf("ERROR max_pkt_len exceeded\n");
}

void add_length_hdr(uint32_t length)
{
    uint16_t avail = max_pkt_len - (uint16_t)(obx_ptr - obx_outbuff);
    if (avail >= 5) {
        *obx_ptr++ = LENGTH_HDR | FOURBYTE;
        *((uint32_t*)obx_ptr) = htonl(length);     // change byte order
        obx_ptr += 4;
    }
    else  printf("ERROR max_pkt_len exceeded\n");
}

void add_body_hdr(uint8_t* body, uint16_t blen, bool isendof)
{
    uint16_t avail = max_pkt_len - (uint16_t)(obx_ptr - obx_outbuff);
    if (avail >= blen+3) {
        if (isendof)  *obx_ptr++ = END_OF_BODY_HDR | BYTES;
        else *obx_ptr++ = BODY_HDR | BYTES;
        *((uint16_t*)obx_ptr) = htons(blen+3);  obx_ptr+=2;
        memcpy(obx_ptr, body, blen);  obx_ptr += blen;
    }
    else  printf("ERROR max_pkt_len exceeded\n");
}

void add_version_flags_maxpkt()
{
    uint16_t avail = max_pkt_len - (uint16_t)(obx_ptr - obx_outbuff);
    if (avail >=4 ) {
        *obx_ptr++ = kOBEXVersion10;
        *obx_ptr++ = kOBEXConnectFlagNone;
        *((uint16_t*)obx_ptr) = htons(max_pkt_len);  obx_ptr+=2;
    }
    else  printf("ERROR max_pkt_len exceeded\n");
}

void complete_obex(void)  // fill in total pkt length
{
    obx_datalen = (uint16_t) (obx_ptr - obx_outbuff);
    uint16_t *ptr = (uint16_t*) (obx_outbuff+1);
    *ptr = htons(obx_datalen);
}
                                                        // input is whole response
bool parse_input(uint8_t* indata, uint16_t indatalen)  // ->linked list of obx_hdr structs
{
    uint8_t *inptr = indata+3;
    int32_t data_left = indatalen;  // go to unsigned int so can tell if data runs out
    int32_t d;
    uint8_t hid, type_bits, *strptr;
    uint16_t len;
    struct obx_hdr* h;
    
    data_left -= 3;
    if (*indata == kOBEXOpCodeSetPath) { inptr+=2; data_left-=2; }  // skip flag + constant
        
    obx_hdr_list = NULL;
    if (data_left <= 0)  return false;
    while (data_left > 0) {
        h = malloc(sizeof(struct obx_hdr));
        h->next = obx_hdr_list;  obx_hdr_list = h;  // append to list
        hid = *inptr++;
        type_bits = hid & 0xc0;
        hid &= 0x3f;    // strip type bits
        h->hdr_id = hid;
        // TODO bail if data_left <=0
        printf("hid = %s\n", obx_header_strings[hid]);
        d=0;
        switch (hid) {
            case NAME_HDR:
                d = len = ntohs(*((uint16_t*) inptr));  inptr+=2;
                len -=3;  // -> len(uincode including terminator)
                // TODO truncate long names
                strptr = h->str;
                while (len>0) { inptr++; *strptr++ = *inptr++; len-=2; }
                *strptr = 0;    // extra null for safety
                //h->stringlen = strlen(h->str);
                printf("str = %s\n", h->str);
                break;
                
            case LENGTH_HDR:
                if (type_bits == ONEBYTE) {
                    h->int8 =  *inptr++;
                    d=2;
                }
                if (type_bits == FOURBYTE) {
                    h->int32 = ntohl(*((uint32_t *) inptr));  inptr += 4;
                    d=5;
                }
                break;
                
            case BODY_HDR:
            case END_OF_BODY_HDR:
                d = len = ntohs(*((uint16_t*) inptr));  inptr+=2;
                h->dataptr = inptr;
                h->datalen = len - 3;
                inptr += (len-3);
                printf("bod\n");
                break;
                
            default:
                switch (type_bits) {
                    case UNICODE:
                    case BYTES:
                        d = ntohs(*((uint16_t*) inptr));  inptr += (d-1);
                        break;
                        
                    case FOURBYTE:
                        d = 5;  inptr += 4;
                        break;
                        
                    case ONEBYTE:
                        d = 2;  inptr++;
                }

        }
        if (d==0) {
            printf("bad header?\n");
            hexdump(inptr, 16);
            break;
        }
        data_left -= d;
    }
    
    return true;
}

bool parse_connect_response(uint8_t* indata, uint16_t indatalen)
{
    uint8_t* inptr = indata;
    uint16_t remote_max_pkt_len;
    
    if (indatalen < 7) { printf("bad connect respose\n");  return false; }
    if (*inptr == kOBEXResponseCodeSuccessWithFinalBit) {
        // ignoring version + flags
        inptr +=5;
        remote_max_pkt_len = ntohs(*((uint16_t*) inptr));
        printf("remote mak_pkt_len=%d\n", remote_max_pkt_len);
        if (remote_max_pkt_len > max_pkt_len)  printf("bad remote max_pkt_len\n");
        if (remote_max_pkt_len < max_pkt_len)  max_pkt_len = remote_max_pkt_len;
        if (max_pkt_len < 48)   printf("tiny pkt len\n"); //TODO something}
        return true;
    }
    printf("obex connect failed\n");
    return false;
}


uint32_t extract_length(void)
{
    struct obx_hdr* h;
    uint32_t len = 1024;    // default length
    
    h = obx_hdr_list;
    while (h) {
        if (h->hdr_id == LENGTH_HDR) {
            len = h->int32;
            break;
        }
        h= h->next;
    }
    return len;
}


bool extract_body(uint8_t **body_ptr, uint16_t *body_len,  bool *end_of)
{
    struct obx_hdr* h;
    
    h = obx_hdr_list;
    while (h) {
        if ((h->hdr_id & 0x3e) == BODY_HDR) {     // look for hid == 8 or 9
            *body_ptr = h->dataptr;
            *body_len = h->datalen;
            *end_of = (h->hdr_id == END_OF_BODY_HDR);
            return true;
        }
        h = h->next;
    }
    return false;
}

uint8_t nulstr[] =  { 0 };
bool extract_name(uint8_t **name)
{
    struct obx_hdr* h;
    
    h = obx_hdr_list;
    while (h) {
        if (h->hdr_id == NAME_HDR) {
            *name = h->str;
            return true;
        }
        h = h->next;
    }
    *name = nulstr;
    return false;
}

void free_obx_hdrs(void)
{
    struct obx_hdr *h;
    
    h = obx_hdr_list;
    while (h) { obx_hdr_list = h->next;  free(h);  h = obx_hdr_list; }
}
