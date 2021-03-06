#import "ILReportingApplication.h"
#import "ILExceptionRecovery.h"
#import "ILReportWindow.h"

#if IL_APP_KIT
#import <ExceptionHandling/ExceptionHandling.h>
#endif

@implementation ILReportingApplication

- (void) checkForNewCrash:(NSTimer*) timer
{
    // TODO present UI to the user asking if we can report a previous crash
    NSString* latestSystemCrash = [ILReportWindow latestSystemCrashReport];
#if IL_APP_KIT
    if (latestSystemCrash && ![NSApp modalWindow]) { // don't prompt if there is already a modal window on screen
        self.reportWindow = [ILReportWindow windowForSystemCrashReport:latestSystemCrash];
        [self.reportWindow showWindow:self];
        [[self.reportWindow window] makeKeyAndOrderFront:self]; // don't be modal
    }
#else
    NSLog(@"latestSystemCrash: %@", latestSystemCrash);
#endif
}

#pragma mark - NSApplication Overrides

#if IL_APP_KIT
- (void) finishLaunching
{
    // register as exception handler delegate
    [NSExceptionHandler defaultExceptionHandler].exceptionHandlingMask =
      ( NSHandleUncaughtExceptionMask
      | NSHandleUncaughtSystemExceptionMask
      | NSHandleUncaughtRuntimeErrorMask
      | NSHandleTopLevelExceptionMask);
//      | NSHandleOtherExceptionMask;
    [NSExceptionHandler defaultExceptionHandler].delegate = self;

    // defer this to after runloop start so that the app doesn't start twice
    [NSTimer scheduledTimerWithTimeInterval:5.0 target:self selector:@selector(checkForNewCrash:) userInfo:nil repeats:NO];

    [super finishLaunching];
}
#endif

#pragma mark - NSResponder Overrides

/*
- (NSError *)willPresentError:(NSError *)error
{
    if( [[error userInfo] objectForKey:NSRecoveryAttempterErrorKey])
    {
        return error;
    }
    else
    {
        self.reportWindow = [ILReportWindow windowForError:error];
        [self.reportWindow runModal];
        return nil;
    }
}
*/

#if IL_APP_KIT
- (BOOL) presentError:(NSError *)error
{
    BOOL wasRecovered = NO;

    if ([[error userInfo] objectForKey:NSRecoveryAttempterErrorKey]) {
        wasRecovered = [super presentError:error];
    }

    if (!wasRecovered) { // recovery failed, show the report window
        self.reportWindow = [ILReportWindow windowForError:error];
        [self.reportWindow runModal];
        wasRecovered = NO;
    }

    return wasRecovered;
}

- (void)presentError:(NSError *)error modalForWindow:(NSWindow *)window delegate:(id)delegate didPresentSelector:(SEL)didPresentSelector contextInfo:(void *)contextInfo
{
    if( [[error userInfo] objectForKey:NSRecoveryAttempterErrorKey]
     || ([[error domain] isEqualToString:NSCocoaErrorDomain] && [error code]==NSUserCancelledError))
    {
        [super presentError:error modalForWindow:window delegate:delegate didPresentSelector:didPresentSelector contextInfo:contextInfo];
    }
    else // TODO do this attached to a window and inform the delegate of the success or failure
    {
        self.reportWindow = [ILReportWindow windowForError:error];
        [self.reportWindow runModal];
    }
}
#endif

#pragma mark - NSExceptionHandling
#if IL_APP_KIT
- (BOOL)exceptionHandler:(NSExceptionHandler *)exceptionHandler
   shouldHandleException:(NSException *)exception
                    mask:(NSUInteger)mask
{
    if( [ILExceptionRecovery isCommonSystemException:exception])
        return YES;

    ILExceptionRecovery* handler = [ILExceptionRecovery registeredHandlerForException:exception];
    if( handler)
    {
        NSError* recoverableError = [handler recoverableErrorForException:exception];
        BOOL wasRecovered = [NSApp presentError:recoverableError];
        return !wasRecovered; // presentError: returns TRUE if there was recovery, don't handle those
    }

    // could not or did not recover, report the exception
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        self.reportWindow = [ILReportWindow windowForException:exception];
        [self.reportWindow runModal];
    }];

    return NO;
}
#endif

#pragma mark - NSErrorRecoveryAttempting

- (BOOL)attemptRecoveryFromError:(NSError *)error optionIndex:(NSUInteger)recoveryOptionIndex;
{
    NSLog(@"attemptRecoveryFromError: %@ optionIndex: %li", error, recoveryOptionIndex);
    return (recoveryOptionIndex == 0);
}

#pragma mark - IBActions

- (void) reportBug:(id) sender
{
#if IL_APP_KIT
    // check for snag keys to see if we need to do something, excpetioal
    NSEventModifierFlags currentFlags = [[NSApp currentEvent] modifierFlags];
    
#if TEST_CODE
    if ((currentFlags & NSAlternateKeyMask) && (currentFlags & NSControlKeyMask)) {
        /* Trigger a crash */
        ((char *)NULL)[1] = 0;
    }
#endif

    if ([[NSApp currentEvent] modifierFlags] & NSControlKeyMask) { // report a test error with recovery options
        if ([[NSApp currentEvent] modifierFlags] & NSShiftKeyMask) { // report a recoverable error
            NSDictionary* recoveryInfo = @{
                NSRecoveryAttempterErrorKey: self,
                NSLocalizedDescriptionKey: @"Can you handle this error, man!?",
                NSLocalizedFailureReasonErrorKey: @"There is no Reason Here.",
                NSLocalizedRecoverySuggestionErrorKey: @"You're gonna wanna freak out.",
                NSLocalizedRecoveryOptionsErrorKey: @[@"Ignore", @"Report"]
            };
            NSError* handled = [NSError errorWithDomain:@"net.istumbler.labs" code:-2 userInfo:recoveryInfo];
            [NSApp presentError:handled];
        }
        else {
            NSDictionary* errorInfo = @{
                NSLocalizedDescriptionKey: @"This is a test error",
                NSLocalizedFailureReasonErrorKey: @"If this had been a real error, the reason would be displayed here."
            };
            NSError* userReported = [NSError errorWithDomain:@"net.istumbler.labs" code:-1 userInfo:errorInfo];
            [NSApp presentError:userReported];
        }
    }
    else if (currentFlags & NSAlternateKeyMask) { // report an exception
        if (currentFlags & NSShiftKeyMask) {
            [[ILExceptionRecovery testException] raise];
        }
        else {
            [[NSException exceptionWithName:@"net.istumbler.labs" reason:@"Test Exception" userInfo:nil] raise];
        }
    }
    else { // just a bug report
        self.reportWindow = [ILReportWindow windowForBug];
        [self.reportWindow runModal];
    }
#endif
}

@end

/* Copyright © 2014-2017, Alf Watt (alf@istumbler.net) Avaliale under MIT Style license in README.md */
