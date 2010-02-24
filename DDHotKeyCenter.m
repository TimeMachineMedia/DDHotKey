//
//  DDHotKeyManager.m
//  EmptyAppKit
//
//  Created by Dave DeLong on 2/20/10.
//  Copyright 2010 Home. All rights reserved.
//

#import "DDHotKeyCenter.h"
#import <Carbon/Carbon.h>

#pragma mark Private Global Declarations

static NSMutableSet * _registeredHotKeys = nil;
static UInt32 _nextHotKeyID = 1;
OSStatus dd_hotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void * userData);
NSUInteger dd_translateModifierFlags(NSUInteger flags);

#pragma mark DDHotKey

@interface DDHotKey : NSObject {
	id target;
	SEL action;
	id object;
	
#if BUILD_FOR_SNOWLEOPARD
	DDHotKeyTask task;
#endif
	
	unsigned short keyCode;
	NSUInteger modifierFlags;
	UInt32 hotKeyID;
	NSValue * hotKeyRef;
}

@property (retain) id target;
@property SEL action;
@property (retain) id object;
#if BUILD_FOR_SNOWLEOPARD
@property (copy) DDHotKeyTask task;
#endif
@property unsigned short keyCode;
@property NSUInteger modifierFlags;
@property UInt32 hotKeyID;
@property (retain) NSValue * hotKeyRef;

- (void) invokeWithEvent:(NSEvent *)event;
- (BOOL) registerHotKey;
- (void) unregisterHotKey;

@end

@implementation DDHotKey

@synthesize target, action, object, task, keyCode, modifierFlags, hotKeyID, hotKeyRef;

- (void) invokeWithEvent:(NSEvent *)event {
	if (target != nil && action != nil && [target respondsToSelector:action]) {
		[target performSelector:action withObject:event withObject:object];
	}
#if BUILD_FOR_SNOWLEOPARD
	else if (task != nil) {
		task(event);
	}
#endif
}

- (NSString *) actionString {
	return NSStringFromSelector(action);
}

- (BOOL) registerHotKey {
	EventHotKeyID keyID;
	keyID.signature = 'htk1';
	keyID.id = _nextHotKeyID;
	
	EventHotKeyRef carbonHotKey;
	OSStatus err = RegisterEventHotKey(keyCode, modifierFlags, keyID, GetEventDispatcherTarget(), 0, &carbonHotKey);
	
	//error registering hot key
	if (err != 0) { return NO; }
	
	NSValue * refValue = [NSValue valueWithPointer:carbonHotKey];
	[self setHotKeyRef:refValue];
	[self setHotKeyID:_nextHotKeyID];
	
	_nextHotKeyID++;
	
	return YES;
}

- (void) unregisterHotKey {
	EventHotKeyRef carbonHotKey = (EventHotKeyRef)[hotKeyRef pointerValue];
	UnregisterEventHotKey(carbonHotKey);
	[self setHotKeyRef:nil];
}

- (void) dealloc {
	[target release], target = nil;
	[object release], object = nil;
	if (hotKeyRef != nil) {
		[self unregisterHotKey];
		[hotKeyRef release], hotKeyRef = nil;
	}
	[super dealloc];
}

@end

#pragma mark DDHotKeyCenter

@implementation DDHotKeyCenter

+ (void) initialize {
	if (_registeredHotKeys == nil) {
		_registeredHotKeys = [[NSMutableSet alloc] init];
		_nextHotKeyID = 1;
		EventTypeSpec eventSpec;
		eventSpec.eventClass = kEventClassKeyboard;
		eventSpec.eventKind = kEventHotKeyReleased;
		InstallApplicationEventHandler(&dd_hotKeyHandler, 1, &eventSpec, NULL, NULL);
	}
}

- (NSSet *) hotKeysMatchingPredicate:(NSPredicate *)predicate {
	return [_registeredHotKeys filteredSetUsingPredicate:predicate];
}

- (BOOL) hasRegisteredHotKeyWithKeyCode:(unsigned short)keyCode modifierFlags:(NSUInteger)flags {
	NSPredicate * predicate = [NSPredicate predicateWithFormat:@"keyCode = %hu AND modifierFlags = %lu", keyCode, dd_translateModifierFlags(flags)];
	return ([[self hotKeysMatchingPredicate:predicate] count] > 0);
}

#if BUILD_FOR_SNOWLEOPARD
- (BOOL) registerHotKeyWithBlock:(DDHotKeyTask)task keyCode:(unsigned short)keyCode modifierFlags:(NSUInteger)flags {
	//we can't add a new hotkey if something already has this combo
	if ([self hasRegisteredHotKeyWithKeyCode:keyCode modifierFlags:flags]) { return NO; }
	
	//translate the flags
	NSUInteger modifierFlags = dd_translateModifierFlags(flags);
	
	DDHotKey * newHotKey = [[DDHotKey alloc] init];
	[newHotKey setTask:task];
	[newHotKey setKeyCode:keyCode];
	[newHotKey setModifierFlags:modifierFlags];
	
	BOOL success = [newHotKey registerHotKey];
	if (success) {
		[_registeredHotKeys addObject:newHotKey];
	}
	
	[newHotKey release];
	return success;
}
#endif

- (BOOL) registerHotKeyWithTarget:(id)target action:(SEL)action object:(id)object keyCode:(unsigned short)keyCode modifierFlags:(NSUInteger)flags {
	//we can't add a new hotkey if something already has this combo
	if ([self hasRegisteredHotKeyWithKeyCode:keyCode modifierFlags:flags]) { return NO; }
	
	//translate the flags
	NSUInteger modifierFlags = dd_translateModifierFlags(flags);
	
	//build the hotkey object:
	DDHotKey * newHotKey = [[DDHotKey alloc] init];
	[newHotKey setTarget:target];
	[newHotKey setAction:action];
	[newHotKey setObject:object];
	[newHotKey setKeyCode:keyCode];
	[newHotKey setModifierFlags:modifierFlags];
	
	BOOL success = [newHotKey registerHotKey];
	if (success) {
		[_registeredHotKeys addObject:newHotKey];
	}
	
	[newHotKey release];
	return success;
}

- (void) unregisterHotKeysMatchingPredicate:(NSPredicate *)predicate {
	//when a DDHotKey is deallocated, it unregisters itself
	//-hotKeysMatchingPredicate returns an autoreleased set
	//so we force sooner deallocation (and unregistering) with a explicit pool
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	NSSet * matches = [self hotKeysMatchingPredicate:predicate];
	[_registeredHotKeys minusSet:matches];
	[pool release];
}

- (void) unregisterHotKeysWithTarget:(id)target {
	NSPredicate * predicate = [NSPredicate predicateWithFormat:@"target = %@", target];
	[self unregisterHotKeysMatchingPredicate:predicate];
}

- (void) unregisterHotKeyWithTarget:(id)target action:(SEL)action {
	NSPredicate * predicate = [NSPredicate predicateWithFormat:@"target = %@ AND actionString = %@", target, NSStringFromSelector(action)];
	[self unregisterHotKeysMatchingPredicate:predicate];
}

- (void) unregisterHotKeyWithKeyCode:(unsigned short)keyCode modifierFlags:(NSUInteger)flags {
	NSPredicate * predicate = [NSPredicate predicateWithFormat:@"keyCode = %hu AND modifierFlags = %lu", keyCode, dd_translateModifierFlags(flags)];
	[self unregisterHotKeysMatchingPredicate:predicate];
}

@end

OSStatus dd_hotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void * userData) {
	NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
	
	EventHotKeyID hotKeyID;
	GetEventParameter(theEvent, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(hotKeyID),NULL,&hotKeyID);
	
	UInt32 keyID = hotKeyID.id;
	
	NSSet * matchingHotKeys = [_registeredHotKeys filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"hotKeyID = %u", keyID]];
	if ([matchingHotKeys count] > 1) { NSLog(@"ERROR!"); }
	DDHotKey * matchingHotKey = [matchingHotKeys anyObject];
	
	NSEvent * event = [NSEvent eventWithEventRef:theEvent];
	NSEvent * keyEvent = [NSEvent keyEventWithType:NSKeyUp 
										  location:[event locationInWindow] 
									 modifierFlags:[event modifierFlags]
										 timestamp:[event timestamp] 
									  windowNumber:-1 
										   context:nil 
										characters:@"" 
					   charactersIgnoringModifiers:@"" 
										 isARepeat:NO 
										   keyCode:[matchingHotKey keyCode]];

	[matchingHotKey invokeWithEvent:keyEvent];
	
	[pool release];
	
	return noErr;
}

NSUInteger dd_translateModifierFlags(NSUInteger flags) {
	NSUInteger newFlags = 0;
	if ((flags & NSControlKeyMask) > 0) { newFlags |= controlKey; }
	if ((flags & NSCommandKeyMask) > 0) { newFlags |= cmdKey; }
	if ((flags & NSShiftKeyMask) > 0) { newFlags |= shiftKey; }
	if ((flags & NSAlternateKeyMask) > 0) { newFlags |= optionKey; }
	return newFlags;
}