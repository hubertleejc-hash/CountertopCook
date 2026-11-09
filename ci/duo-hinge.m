// Moves the iPhone Duo simulator's hinge to an angle, so CI can test the unfolded layout.
// Neither simctl nor XCTest can fold the simulator; only Device Hub's buttons can. SpringBoard
// has a test service, com.apple.springboard.sbdisplay, that sweeps the hinge through the
// system's own path, so apps get UIHingeInteraction updates and the display hand-off as from
// a real fold. Only a process inside the simulator with the entitlement
// com.apple.springboard.sbdisplay.service can reach it, so ci/duo-hinge.sh builds this for the
// simulator and runs it with `simctl spawn`. Private interface: tested on iOS 27.1 only.
//
// Usage (inside the simulator): duo-hinge <degrees 0-180> [seconds]
//
// Adapted from devicehubctl's hinge helper, https://github.com/ChrisThoma/devicehubctl
// (commit 8c7acc1). Copyright (c) 2026 Chris Thoma. MIT License:
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software
// and associated documentation files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions: The above copyright
// notice and this permission notice shall be included in all copies or substantial portions of
// the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
// PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
// DEALINGS IN THE SOFTWARE.

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#include <stdlib.h>

typedef struct { long long w[8]; } Swap;  // SBFDisplayToolSwapSettings, 64 bytes

@interface SBSDisplayToolServiceConnection : NSObject
- (void)swapDisplayWithSettings:(Swap)s completionHandler:(void (^)(NSError *))c;
- (void)unlockForTestingWithCompletion:(void (^)(void))c;
@end

static NSError *await(void (^call)(void (^)(NSError *))) {
  __block NSError *result = nil;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  call(^(NSError *e) { result = e; dispatch_semaphore_signal(done); });
  if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC)))
    return [NSError errorWithDomain:@"duo-hinge" code:1 userInfo:@{NSLocalizedDescriptionKey: @"SpringBoard didn't answer"}];
  return result;
}

int main(int argc, char **argv) { @autoreleasepool {
  if (argc < 2) { fprintf(stderr, "usage: duo-hinge <degrees 0-180> [seconds]\n"); return 2; }
  double degrees = atof(argv[1]), seconds = argc > 2 ? atof(argv[2]) : 2;
  if (degrees < 0 || degrees > 180 || seconds < 0) { fprintf(stderr, "degrees must be 0-180\n"); return 2; }

  dlopen("/System/Library/PrivateFrameworks/SpringBoardServices.framework/SpringBoardServices", RTLD_NOW);
  void *foundation = dlopen("/System/Library/PrivateFrameworks/SpringBoardFoundation.framework/SpringBoardFoundation", RTLD_NOW);
  BOOL (*parseSwap)(NSArray *, Swap *, NSError **) = foundation ? dlsym(foundation, "SBFDisplayToolSwapSettingsFromArguments") : NULL;
  Class connectionClass = NSClassFromString(@"SBSDisplayToolServiceConnection");
  if (!parseSwap || !connectionClass) { fprintf(stderr, "This simulator runtime has no hinge test service.\n"); return 3; }

  // Apple's own parser builds the settings; a position is degrees / 180.
  NSArray *args = @[[NSString stringWithFormat:@"-position=%.6f", degrees / 180],
                    [NSString stringWithFormat:@"-duration=%g", seconds], @"-wait"];
  Swap settings = {0};
  NSError *error = nil;
  if (!parseSwap(args, &settings, &error)) { fprintf(stderr, "%s\n", error.localizedDescription.UTF8String); return 2; }

  SBSDisplayToolServiceConnection *connection = [connectionClass new];
  error = await(^(void (^reply)(NSError *)) { [connection swapDisplayWithSettings:settings completionHandler:reply]; });
  if (error) { fprintf(stderr, "Hinge to %g failed: %s\n", degrees, error.localizedDescription.UTF8String); return 1; }
  printf("Hinge moved to %g degrees\n", degrees);

  // Release the test lock; the hinge stays where it landed.
  dispatch_semaphore_t unlocked = dispatch_semaphore_create(0);
  [connection unlockForTestingWithCompletion:^{ dispatch_semaphore_signal(unlocked); }];
  dispatch_semaphore_wait(unlocked, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
  return 0;
} }
