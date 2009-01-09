/*!
@file macro_1.m
@description Nu macros.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/
#import "macro_0.h"
#import "macro_1.h"
#import "cell.h"
#import "symbol.h"
#import "class.h"
#import "extensions.h"
#import "objc_runtime.h"
#import "operator.h"
#import "match.h"

extern id Nu__null;

//#define MACRO1_DEBUG	1
//#define USE_NU_DESTRUCTURE 1


// Following  debug output on and off for this file only
#ifdef MACRO1_DEBUG
#define Macro1Debug(arg...) NSLog(arg)
#else
#define Macro1Debug(arg...)
#endif


@implementation NuMacro_1

+ (id) macroWithName:(NSString *)n parameters:(NuCell*)p body:(NuCell *)b
{
    return [[[self alloc] initWithName:n parameters:p body:b] autorelease];
}

- (void) dealloc
{
	[parameters release];
    [super dealloc];
}


- (id) initWithName:(NSString *)n parameters:(NuCell *)p body:(NuCell *)b
{
    [super initWithName:n body:b];
	parameters = [p retain];

	id match = [NuMatch matcher];

	if (([parameters length] == 1) 
		&& ([[[parameters car] stringValue] isEqualToString:@"*args"])) {
		// Skip the check
	}
	else {
		id foundArgs = [match findAtom:@"*args" inSequence:parameters];

		if (foundArgs && (foundArgs != Nu__null)) {
			printf("Warning: Overriding implicit variable '*args'.\n");
		}
	}

    return self;
}

- (NSString *) stringValue
{
    return [NSString stringWithFormat:@"(macro-1 %@ %@ %@)", name, [parameters stringValue], [body stringValue]];
}



- (void) dumpContext:(NSMutableDictionary*)context
{
	NSArray* keys = [context allKeys];
	int count = [keys count];
	for (int i = 0; i < count; i++) {
		id key = [keys objectAtIndex:i];
		Macro1Debug(@"contextdump: %@  =  %@  [%@]", key, 
			[[context objectForKey:key] stringValue],
			[[context objectForKey:key] class]);
	}
}

- (void) restoreArgs:(id)old_args context:(NSMutableDictionary*)calling_context
{
	NuSymbolTable *symbolTable = [calling_context objectForKey:SYMBOLS_KEY];
    
    if (old_args == nil) {
        [calling_context removeObjectForKey:[symbolTable symbolWithCString:"*args"]];
	}
    else {
        [calling_context setPossiblyNullObject:old_args forKey:[symbolTable symbolWithCString:"*args"]];
	}
}


- (void)restoreBindings:(id)bindings
					forMaskedVariables:(NSMutableDictionary*)maskedVariables
					fromContext:(NSMutableDictionary*)calling_context
{
	id plist = bindings;
	
	while (plist && (plist != Nu__null)) {
		id param = [[plist car] car];

		[calling_context removeObjectForKey:param];		
		id pvalue = [maskedVariables objectForKey:param];
		
		Macro1Debug(@"restoring calling context for: %@, value: %@",
			[param stringValue], [pvalue stringValue]);
		
		if (pvalue) {
			[calling_context setPossiblyNullObject:pvalue forKey:param];
		}
		
		plist = [plist cdr];
	}
}


- (id) mdestructure:(id)pattern withSequence:(id)sequence
{
	Macro1Debug(@"mdestructure: pat: %@  seq: %@", [pattern stringValue], [sequence stringValue]);

	// ((and (not pat) seq)
	if (   ((pattern == nil) || (pattern == Nu__null)) 
	    && (sequence != Nu__null))
	{
        [NSException raise:@"NuDestructureException"
            format:@"Attempt to match empty pattern to non-empty object"];
	}
	// ((not pat) nil)
	else if ((pattern == nil) || (pattern == Nu__null))
	{
		return nil;
	}
	else if (   (pattern && (pattern != Nu__null))
	         && (sequence == nil || sequence == Nu__null))
	{
        [NSException raise:@"NuDestructureException"
            format:@"Attempt to match non-empty pattern to empty object"];		
	}
	// ((eq pat '_) '())  ; wildcard match produces no binding
	else if ([[pattern stringValue] isEqualToString:@"_"])
	{
		return nil;
	}
	// ((symbol? pat)
    //   (let (seq (if (eq ((pat stringValue) characterAtIndex:0) '*')
    //                 (then (list seq))
	//                 (else seq)))
	//        (list (list pat seq))))
	else if ([pattern class] == [NuSymbol class])
	{
		id result;

		if ([[pattern stringValue] characterAtIndex:0] == '*')
		{
			// List-ify sequence
			id l = [[[NuCell alloc] init] autorelease];
			[l setCar:sequence];
			result = l;
		}
		else
		{
			result = sequence;
		}
		
		// (list pattern sequence)
		id p = [[[NuCell alloc] init] autorelease];
		id s = [[[NuCell alloc] init] autorelease];
		
		[p setCar:pattern];
		[p setCdr:s];
		[s setCar:result];
		
		// (list (list pattern sequence))
		id l = [[[NuCell alloc] init] autorelease];
		[l setCar:p];
	
		return l;
	}
	// ((pair? pat)
	//   (if (and (symbol? (car pat))
	//       (eq (((car pat) stringValue) characterAtIndex:0) '*'))
	//       (then (list (list (car pat) seq)))
	//       (else ((let ((bindings1 (mdestructure (car pat) (car seq)))
	//                    (bindings2 (mdestructure (cdr pat) (cdr seq))))
	//                (append bindings1 bindings2))))))
	else if ([pattern class] == [NuCell class])
	{
		if (   ([[pattern car] class] == [NuSymbol class])
		    && ([[[pattern car] stringValue] characterAtIndex:0] == '*'))
		{
			id l1 = [[[NuCell alloc] init] autorelease];
			id l2 = [[[NuCell alloc] init] autorelease];
			id l3 = [[[NuCell alloc] init] autorelease];
			[l1 setCar:[pattern car]];
			[l1 setCdr:l2];
			[l2 setCar:sequence];
			[l3 setCar:l1];
			
			return l3;
		}
		else
		{
			id b1 = [self mdestructure:[pattern car] withSequence:[sequence car]];
			id b2 = [self mdestructure:[pattern cdr] withSequence:[sequence cdr]];

			// (append b1 b2)
		    id newList = Nu__null;
		    id cursor = nil;
		    id item_to_append = b1;

	        while (item_to_append && (item_to_append != Nu__null)) {
	            if (newList == Nu__null) {
	                newList = [[[NuCell alloc] init] autorelease];
	                cursor = newList;
	            }
	            else {
	                [cursor setCdr: [[[NuCell alloc] init] autorelease]];
	                cursor = [cursor cdr];
	            }
	            id item = [item_to_append car];
	            [cursor setCar: item];
	            item_to_append = [item_to_append cdr];
	        }

			item_to_append = b2;
	        while (item_to_append && (item_to_append != Nu__null)) {
	            if (newList == Nu__null) {
	                newList = [[[NuCell alloc] init] autorelease];
	                cursor = newList;
	            }
	            else {
	                [cursor setCdr: [[[NuCell alloc] init] autorelease]];
	                cursor = [cursor cdr];
	            }
	            id item = [item_to_append car];
	            [cursor setCar: item];
	            item_to_append = [item_to_append cdr];
	        }

		    return newList;
		}
	}
	// (else (throw* "NuMatchException"
	//               "pattern is not nil, a symbol or a pair: #{pat}"))))
	else
	{
        [NSException raise:@"NuDestructureException"
			format:@"Pattern is not nil, a symbol or a pair: %@", [pattern stringValue]];
	}

	// Just for aesthetics...
	return nil;
}


- (id) expandAndEval:(id)cdr context:(NSMutableDictionary*)calling_context evalFlag:(BOOL)evalFlag
{
    NuSymbolTable *symbolTable = [calling_context objectForKey:SYMBOLS_KEY];

	NSMutableDictionary* maskedVariables = [[NSMutableDictionary alloc] init];

	id plist;

	Macro1Debug(@"Dumping context:");
	Macro1Debug(@"---------------:");
	[self dumpContext:calling_context];

    id old_args = [calling_context objectForKey:[symbolTable symbolWithCString:"*args"]];
	[calling_context setPossiblyNullObject:cdr forKey:[symbolTable symbolWithCString:"*args"]];

#ifdef USE_NU_DESTRUCTURE
	id match = [NuMatch matcher];
#endif

	id destructure;

	#ifdef DARWIN
	@try
		#else
		NS_DURING
		#endif
	{
		// Destructure the arguments
#ifdef USE_NU_DESTRUCTURE
		destructure = [match mdestructure:parameters withSequence:cdr];
#else
		destructure = [self mdestructure:parameters withSequence:cdr];
#endif

	}
	#ifdef DARWIN
	@catch (id exception)
		#else
		NS_HANDLER
		#endif
	{
		// Destructure failed...restore/remove *args
		[self restoreArgs:old_args context:calling_context];

		#ifdef DARWIN
		@throw;
			#else
			[localException raise];
			#endif
	}
	#ifndef DARWIN
	NS_ENDHANDLER
    	#endif

	plist = destructure;
	while (plist && (plist != Nu__null)) {
		id parameter = [[plist car] car];
		id value = [[[plist car] cdr] car];
		Macro1Debug(@"Destructure: %@ = %@", [parameter stringValue], [value stringValue]);
			
		id pvalue = [calling_context objectForKey:parameter];
		
		if (pvalue) {
			Macro1Debug(@"  Saving context: %@ = %@", 
					[parameter stringValue],
					[pvalue stringValue]);
			[maskedVariables setPossiblyNullObject:pvalue forKey:parameter];
		}

		[calling_context setPossiblyNullObject:value forKey:parameter];
		
		plist = [plist cdr];
	}

	Macro1Debug(@"Dumping context (after destructure):");
	Macro1Debug(@"-----------------------------------:");
	[self dumpContext:calling_context];


    // evaluate the body of the block in the calling context (implicit progn)
    id value = Nu__null;

    // if the macro contains gensyms, give them a unique prefix
    int gensymCount = [[self gensyms] count];
    id gensymPrefix = nil;
    if (gensymCount > 0) {
        gensymPrefix = [NSString stringWithFormat:@"g%ld", [NuMath random]];
    }

    id bodyToEvaluate = (gensymCount == 0)
        ? (id)body : [self body:body withGensymPrefix:gensymPrefix symbolTable:symbolTable];

	// Macro1Debug(@"macro evaluating: %@", [bodyToEvaluate stringValue]);
	// Macro1Debug(@"macro context: %@", [calling_context stringValue]);

	#ifdef DARWIN
	@try
		#else
		NS_DURING
		#endif
	{
		// Macro expansion
	    id cursor = [self expandUnquotes:bodyToEvaluate withContext:calling_context];
	    while (cursor && (cursor != Nu__null)) {
			Macro1Debug(@"macro eval cursor: %@", [cursor stringValue]);
	        value = [[cursor car] evalWithContext:calling_context];
			Macro1Debug(@"macro expand value: %@", [value stringValue]);
	        cursor = [cursor cdr];
	    }

		// Now that macro expansion is done, restore the masked calling context variables
		[self restoreBindings:destructure
							forMaskedVariables:maskedVariables
							fromContext:calling_context];

		[maskedVariables release];

		// Macro evaluation
		// If we're just macro-expanding, don't do this step...
		if (evalFlag) {
			Macro1Debug(@"About to execute: %@", [value stringValue]);
		    value = [value evalWithContext:calling_context];
			Macro1Debug(@"macro eval value: %@", [value stringValue]);		
		}

		Macro1Debug(@"Dumping context at end:");
		Macro1Debug(@"----------------------:");
		[self dumpContext:calling_context];

	    // restore the old value of *args
		[self restoreArgs:old_args context:calling_context];

		Macro1Debug(@"macro result: %@", value);
	}
	#ifdef DARWIN
	@catch (id exception)
		#else
		NS_HANDLER
		#endif
	{
		[self restoreBindings:destructure
							forMaskedVariables:maskedVariables
							fromContext:calling_context];

		[maskedVariables release];

		[self restoreArgs:old_args context:calling_context];

		#ifdef DARWIN
		@throw;
			#else
			[localException raise];
			#endif
	}
	#ifndef DARWIN
	NS_ENDHANDLER
    	#endif

    return value;
}

- (id) expand1:(id)cdr context:(NSMutableDictionary*)calling_context
{
	return [self expandAndEval:cdr context:calling_context evalFlag:NO];
}


- (id) evalWithArguments:(id)cdr context:(NSMutableDictionary *)calling_context
{
	return [self expandAndEval:cdr context:calling_context evalFlag:YES];
}

@end
