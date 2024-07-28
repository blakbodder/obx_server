//
//  directory.h
//  obx_server
//

#ifndef directory_h
#define directory_h
#include <dirent.h>

bool is_directory(char* fullname);
static int listline(char* directory, int dirlen, char* fname, int fnamelen,  char* line);
uint32_t dir_list_len(DIR* d);
uint32_t batch_list(uint8_t* buff, int bufflen, DIR* d, bool* endof);

#endif /* directory_h */
