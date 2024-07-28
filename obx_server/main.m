//
//  main.m
//  obx_server
//
//  WARNING. RUNNING THIS APP MAKES YOUR COMPUTER VERY INSECURE.
//  if you want to grant access to data outside working directory, blakbodder recommends you
//  modify the server and client code to exchange passwords or implement other security

#import <Foundation/Foundation.h>
#import "obx.h"

OBEXSERVER* obex_server;

int t=0;
void timer_callback(CFRunLoopTimerRef timref, void* info)
{
  //  printf("%d ",t++);
  //  fflush(stdout);
  //  if ((t & 0xf) == 0)  printf("\n");

}

void fd_callback(CFFileDescriptorRef fdr, CFOptionFlags callBackTypes, void *info)
{
    int c = getchar();
    //printf("c=%d\n", c);
    if (c=='q') {
        [ obex_server unpublish_service ];  // remove sdp record
        printf("quitting\n");
        // maybe do clean up such as disconnect + [ obex_server.l2capchan closeChannel ]
        CFRunLoopStop(*(CFRunLoopRef*) info);
    }
    else  CFFileDescriptorEnableCallBacks(fdr, kCFFileDescriptorReadCallBack);
}

static CFRunLoopTimerCallBack tcbptr = timer_callback;
static CFFileDescriptorCallBack fdcbptr = fd_callback;

CFRunLoopRef info;
CFFileDescriptorContext fd_context = { 1, &info, NULL, NULL, NULL };

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        CFRunLoopRef mainrunloop;
        CFRunLoopTimerRef timer;
        CFRunLoopSourceRef kybsource;
        CFFileDescriptorRef kybfd;
        CFAbsoluteTime now;

        printf("to quit, enter q<RET>\n");
        // if running inside Xcode, click on console area to route keyboard input to app
        // note if porting this to cocoa no need start runloop because window apps already have runloop
        // runloop needs at least one source or timer to run. l2capchan is probably a runloopsource
        
        info = mainrunloop = CFRunLoopGetCurrent();
        
        // set up keyboard runloopsource so app stays running until user quits
        int fd = fcntl(STDIN_FILENO,  F_DUPFD, 0);
        //printf("fd=%d\n", fd);
        
        kybfd = CFFileDescriptorCreate(kCFAllocatorDefault, fd, false, fdcbptr, &fd_context);
        CFFileDescriptorEnableCallBacks(kybfd, kCFFileDescriptorReadCallBack);
        //printf("kybfd=%p\n", kybfd);
        kybsource = CFFileDescriptorCreateRunLoopSource(kCFAllocatorDefault, kybfd, 0);
        
        if (!kybsource)  printf("NULL kybsource\n");
        CFRunLoopAddSource(mainrunloop, kybsource, kCFRunLoopDefaultMode);
        
        // no timer presently but could be used to police timeouts
        now = CFAbsoluteTimeGetCurrent();
        timer = CFRunLoopTimerCreate(kCFAllocatorDefault, now+1.0, 1.0, 0, 0, tcbptr, NULL);
        //CFRunLoopAddTimer(mainrunloop, timer, kCFRunLoopDefaultMode);
        obex_server = [[ OBEXSERVER alloc ] init ];
        CFRunLoopRun();
    }
    return 0;
}
