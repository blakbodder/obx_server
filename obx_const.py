UNICODE  = 0x00
BITES    = 0x40
ONEBYTE  = 0x80
FOURBYTE = 0xc0

COUNT_HDR       = 0
NAME_HDR        = 1
TYPE_HDR        = 2
LENGTH_HDR      = 3
TIME_HDR        = 4
DESCRIPTION_HDR = 5
TARGET_HDR      = 6
HTTP_HDR        = 7
BODY_HDR        = 8
END_OF_BODY_HDR = 9
WHO_HDR         = 10
CONNECTION_ID_HDR = 11

lookup = [ "count", "name", "type", "length", "time", "description",
           "target", "http", "body", "end of body", "who", "connection id" ]

#status bits : for each header kind received, corresponding bit is set
NAME_BIT    = 0x01
TYPE_BIT    = 0x02
LENGTH_BIT  = 0x04
BODY_BIT    = 0x08
END_OF_BODY_BIT = 0x10

FORBIDDEN_BIT   = 0x100
NOT_FOUND_BIT   = 0x200
BAD_REQUEST_BIT = 0x400
