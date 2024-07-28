//
//  directory.m
//  obx_server

#import <Foundation/Foundation.h>
#include <sys/stat.h>
#include "directory.h"

extern uint32_t inget_len;         // file_len or dir_list_len
extern  uint32_t inget_bytes_left;
extern char list_dir[1024];
extern int list_dir_len;
extern struct dirent* dir_entry;

bool is_directory(char* fullname)
{
    struct stat st;
    if (stat(fullname, &st))  return false; // false if no find
    if (st.st_mode & 0x4000)  return true;
    return false;
}

char monstr[12][4] = { "Jan","Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

static int listline(char* directory, int dirlen, char* fname, int fnamelen,  char* line)
{
    char *lp;
    char fullfilename[1024];
    time_t stim;
    char* fnp;
    struct stat st;
    struct tm* tim;
    int mode, uid, gid;
    int mask;
    
    // need check if workingdir ends in /
    strcpy(fullfilename, directory);
    fnp = fullfilename + dirlen;
    *fnp++ = '/';
    strncpy(fnp, fname, fnamelen+1);
    stat(fullfilename, &st);
    stim = st.st_mtimespec.tv_sec;
    tim = gmtime(&stim);
    mode = st.st_mode;
    lp = line;
    if (mode & 0x4000)  *lp++='d';  else  *lp++='-';
    mask = 0x100;
    if (mode & mask)  *lp++='r';  else  *lp++='-';  mask>>=1;
    if (mode & mask)  *lp++='w';  else  *lp++='-';  mask>>=1;
    if (mode & mask)  *lp++='x';  else  *lp++='-';  mask>>=1;
    if (mode & mask)  *lp++='r';  else  *lp++='-';  mask>>=1;
    if (mode & mask)  *lp++='w';  else  *lp++='-';  mask>>=1;
    if (mode & mask)  *lp++='x';  else  *lp++='-';  mask>>=1;
    if (mode & mask)  *lp++='r';  else  *lp++='-';  mask>>=1;
    if (mode & mask)  *lp++='w';  else  *lp++='-';  mask>>=1;
    if (mode & mask)  *lp++='x';  else  *lp++='-';
    *lp++ = ' ';
    uid = st.st_uid;
    gid = st.st_gid;
    // CHECK fnamelen not rediculous
    
    sprintf(lp, " 1 u%d g%d %7lld %s %2d %2d:%02d %s\n",
            uid, gid, st.st_size, monstr[tim->tm_mon], tim->tm_mday,  tim->tm_hour, tim->tm_min, fname);
    //printf(line);
    return strlen(line);
}


uint32_t dir_list_len(DIR* d)
{
    char buff[1024];
    uint32_t sigma, line_len;
    char *name;
    
    sigma = 0;
    dir_entry = readdir(d);
    while (dir_entry) {
        name = dir_entry->d_name;
        if (*name != '.') {  // TODO skip longnames
            line_len = listline(list_dir, list_dir_len, name, dir_entry->d_namlen, buff);
            sigma += line_len;
            printf("%s", buff);
        }
        dir_entry = readdir(d);
    }
    rewinddir(d);
    return sigma;
}

uint32_t batch_list(uint8_t* buff, int bufflen, DIR* d, bool* endof)
{
    uint8_t* bp;
    char* name;
    int dnamelen;
    int batchlen, k;
    int linelen;
    
    bp = buff;
    batchlen=0;
    
    k=0;
    if (dir_entry != NULL) {
        name = dir_entry->d_name;
        if ((*name != '.')  && (dir_entry->d_namlen < bufflen-80)) {  // skip .names and longnames
            linelen = listline(list_dir, list_dir_len, name, dir_entry->d_namlen, bp);
            bp += linelen;
            batchlen = linelen;
            k++;
        }
    }
    while (k<8) {
        dir_entry = readdir(d);
        if(dir_entry== NULL)  { *endof=true;  return batchlen; }
        name = dir_entry->d_name;
        if (*name != '.') {
            dnamelen = dir_entry->d_namlen;
            if (batchlen + dnamelen > bufflen - 80) { *endof=false;  return batchlen; }   // poss overflow so try in next batch
            linelen = listline(list_dir, list_dir_len, name, dnamelen, bp);
            bp += linelen;
            batchlen += linelen;
            k++;
        }
    }
    dir_entry = readdir(d);
    *endof = (dir_entry == NULL);
    return batchlen;
}
