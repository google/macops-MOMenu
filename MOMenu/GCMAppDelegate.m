/// Copyright 2015 Google Inc. All rights reserved.
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///    http://www.apache.org/licenses/LICENSE-2.0
///
///    Unless required by applicable law or agreed to in writing, software
///    distributed under the License is distributed on an "AS IS" BASIS,
///    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
///    See the License for the specific language governing permissions and
///    limitations under the License.

#import "GCMAboutWindowController.h"
#import "GCMAppDelegate.h"
#import "GCMProtocol.h"

#import <MOLCodesignChecker/MOLCodesignChecker.h>

@interface GCMAppDelegate ()
@property GCMAboutWindowController *aboutWindowController;
@property NSMenu *statusMenu;
@property NSMenuItem *muteMenuItem;
@property NSStatusItem *statusItem;
@property NSMutableArray *plugins;
@property BOOL statusIconIsHidden;
@end

@implementation GCMAppDelegate

NSString *const kPlugInDirectory = @"/Library/MOMenu/PlugIns";
NSString *const kHideMenuIconKey = @"HideMenuIcon";

- (instancetype)init {
  self = [super init];
  if (self) {
    _statusIconIsHidden = [[NSUserDefaults standardUserDefaults] boolForKey:kHideMenuIconKey];
    if (_statusIconIsHidden) {
      _statusItem = [[NSStatusItem alloc] init];
    } else {
      _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    }
    _plugins = [[NSMutableArray alloc] initWithCapacity:10];
    _statusMenu = [[NSMenu alloc] init];
    [_statusMenu setAutoenablesItems:NO];
    _aboutWindowController = [[GCMAboutWindowController alloc]
                                 initWithWindowNibName:@"GCMAboutWindowController"];
    [self setUpMenuIcon];
  }
  return self;
}

- (void)setUpMenuIcon {
  [_statusItem setMenu:_statusMenu];
  NSImage *iconImage = [NSImage imageNamed:@"icon"];
  [iconImage setTemplate:YES];
  [_statusItem setImage:iconImage];
  [_statusItem setHighlightMode:YES];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  BOOL noCheckSignatures = [[[NSProcessInfo processInfo] arguments]
                                containsObject:@"--nochecksignatures"];
  NSArray *pluginDir = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:kPlugInDirectory
                                                                           error:NULL];
  [pluginDir enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
    if ([[[(NSString *)obj pathExtension] lowercaseString] isEqualToString:@"bundle"]) {
      NSString *fullPath = [kPlugInDirectory stringByAppendingPathComponent:(NSString *)obj];
      NSBundle *pluginBundle = [NSBundle bundleWithPath:fullPath];
      Class principalClass = [pluginBundle principalClass];
      MOLCodesignChecker *cc = [[MOLCodesignChecker alloc] initWithBinaryPath:fullPath];
      if (noCheckSignatures ||
          [cc signingInformationMatches:[[MOLCodesignChecker alloc] initWithSelf]]) {
        if ([principalClass conformsToProtocol:@protocol(GCMProtocol)]) {
          [pluginBundle load];
          NSObject<GCMProtocol> *plugin = [[principalClass alloc] init];
          [self.plugins addObject:plugin];
          [self.statusMenu addItem:[plugin menuItem]];
        } else {
          NSLog(@"PlugIn does not conform to GCMProtocol: %@", (NSString *)obj);
        }
      } else {
        NSLog(@"PlugIn is not signed, or is signed with wrong certificate: %@", (NSString *)obj);
      }
    }
  }];

  if ([self.plugins count] == 0) {
    NSLog(@"No suitable PlugIns found in %@", kPlugInDirectory);
    [[NSApplication sharedApplication] terminate:nil];
  }

  NSMenuItem *aboutMenuItem = [[NSMenuItem alloc] initWithTitle:@"About MOMenu"
                                                         action:@selector(showWindow:)
                                                  keyEquivalent:@""];
  [aboutMenuItem setTarget:self.aboutWindowController];

  NSMenuItem *hideMenuItem = [[NSMenuItem alloc] initWithTitle:@"Hide"
                                                        action:@selector(hideMenu)
                                                 keyEquivalent:@""];
  [hideMenuItem setTarget:self];

  self.muteMenuItem = [[NSMenuItem alloc] initWithTitle:@"Mute Popups"
                                                 action:@selector(mutePopups)
                                          keyEquivalent:@""];
  [self.muteMenuItem setTarget:self];

  [self.statusMenu addItem:[NSMenuItem separatorItem]];
  [self.statusMenu addItem:aboutMenuItem];
  [self.statusMenu addItem:self.muteMenuItem];
  [self.statusMenu addItem:hideMenuItem];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
  if (self.statusIconIsHidden) {
    self.statusItem = [[NSStatusBar systemStatusBar]
                          statusItemWithLength:NSVariableStatusItemLength];
    [self setUpMenuIcon];
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kHideMenuIconKey];
    self.statusIconIsHidden = NO;
  }

  [self.statusItem.button performClick:sender];

  return YES;
}

- (void)hideMenu {
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"To display this menu icon again, run MOMenu.app located in the "
                         "/Applications folder."];
  [alert addButtonWithTitle:@"OK"];
  [alert addButtonWithTitle:@"Cancel"];
  if ([alert runModal] == NSAlertFirstButtonReturn) {
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    [statusBar removeStatusItem:self.statusItem];
    self.statusIconIsHidden = YES;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kHideMenuIconKey];
  }
}

- (void)mutePopups {
  [self.muteMenuItem setState:![self.muteMenuItem state]];

  for (NSObject<GCMProtocol> *plugin in self.plugins) {
    if ([plugin respondsToSelector:@selector(setMuteState:)]) {
      [plugin setMuteState:[self.muteMenuItem state]];
    }
  }
}
@end
