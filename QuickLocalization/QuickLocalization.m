//
//  QuickLocalization.m
//  QuickLocalization
//
//  Created by Zitao Xiong on 5/12/13.
//  Copyright (c) 2013 nanaimostudio. All rights reserved.
//

#import "QuickLocalization.h"
#import "RCXcode.h"

#define REPLACEMENT_STRINGS @[@"%@", @",", @".", @":", @"\\", @""]

static NSString *localizeRegexs[] = {
    @"NSLocalizedString\\s*\\(\\s*@\"(.*)\"\\s*,\\s*(.*)\\s*\\)",
    @"localizedStringForKey:\\s*@\"(.*)\"\\s*value:\\s*(.*)\\s*table:\\s*(.*)",
    @"NSLocalizedStringFromTable\\s*\\(\\s*@\"(.*)\"\\s*,\\s*(.*)\\s*,\\s*(.*)\\s*\\)",
    @"NSLocalizedStringFromTableInBundle\\s*\\(\\s*@\"(.*)\"\\s*,\\s*(.*)\\s*,\\s*(.*)\\s*,\\s*(.*)\\s*\\)",
    @"NSLocalizedStringWithDefaultValue\\s*\\(\\s*@\"(.*)\"\\s*,\\s*(.*)\\s*,\\s*(.*)\\s*,\\s*(.*)\\s*,\\s*(.*)\\s*\\)"
};
static NSString *stringRegexs = @"@\"[^\"]*\"";

@implementation QuickLocalization

static id sharedPlugin = nil;

+ (void)pluginDidLoad:(NSBundle *)plugin
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedPlugin = [[self alloc] init];
    });
}

- (NSFileHandle*)localizibleStringsFile
{
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Localizable.strings"];
    return [NSFileHandle fileHandleForWritingAtPath:path];
}

- (id)init
{
    if (self = [super init])
    {
        NSMenuItem *viewMenuItem = [[NSApp mainMenu] itemWithTitle:@"Edit"];
        if (viewMenuItem)
        {
            [[viewMenuItem submenu] addItem:[NSMenuItem separatorItem]];
            NSMenuItem *sample = [[NSMenuItem alloc] initWithTitle:@"Быстрая локализация" action:@selector(quickLocalization) keyEquivalent:@"d"];
            [sample setKeyEquivalentModifierMask:NSShiftKeyMask | NSAlternateKeyMask];
            [sample setTarget:self];
            [[viewMenuItem submenu] addItem:sample];
            
            NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Localizable.strings"];
            
            FILE *fout = fopen([path cStringUsingEncoding:NSASCIIStringEncoding], "wt");
            
            if (fout)
            {
                fclose(fout);
            }
        }
    }
    return self;
}

// Sample Action, for menu item:
- (void)quickLocalization {
    IDESourceCodeDocument *document = [RCXcode currentSourceCodeDocument];
    NSTextView *textView = [RCXcode currentSourceCodeTextView];
    if (!document || !textView) {
        return;
    }
    
    //    NSLog(@"file: %@", [RCXcode currentWorkspaceDocument].workspace.representingFilePath.fileURL.absoluteString);
    NSArray *selectedRanges = [textView selectedRanges];
    if ([selectedRanges count] > 0) {
        NSRange range = [[selectedRanges objectAtIndex:0] rangeValue];
        NSRange lineRange = [textView.textStorage.string lineRangeForRange:range];
        NSString *line = [textView.textStorage.string substringWithRange:lineRange];
        
        NSRegularExpression *localizedRex = [[NSRegularExpression alloc] initWithPattern:localizeRegexs[0] options:NSRegularExpressionCaseInsensitive error:nil];
        NSArray *localizedMatches = [localizedRex matchesInString:line options:0 range:NSMakeRange(0, [line length])];
        
        NSRegularExpression *regex = [[NSRegularExpression alloc] initWithPattern:stringRegexs options:NSRegularExpressionCaseInsensitive error:nil];
        NSArray *matches = [regex matchesInString:line options:0 range:NSMakeRange(0, [line length])];
        NSUInteger addedLength = 0;
        for (int i = 0; i < [matches count]; i++) {
            NSTextCheckingResult *result = [matches objectAtIndex:i];
            NSRange matchedRangeInLine = result.range;
            NSRange matchedRangeInDocument = NSMakeRange(lineRange.location + matchedRangeInLine.location + addedLength, matchedRangeInLine.length);
            if ([self isRange:matchedRangeInLine inSkipedRanges:localizedMatches]) {
                continue;
            }
            NSString *string = [line substringWithRange:matchedRangeInLine];
//            NSLog(@"string index:%d, %@", i, string);
            
            __block NSString *keyName = string;
            
            [REPLACEMENT_STRINGS enumerateObjectsUsingBlock:^(NSString *stringForReplacement, NSUInteger idx, BOOL *stop)
            {
                keyName = [keyName stringByReplacingOccurrencesOfString:stringForReplacement withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, keyName.length)];
            }];
            
            keyName = [keyName stringByReplacingOccurrencesOfString:@" " withString:@"_" options:NSCaseInsensitiveSearch range:NSMakeRange(0, keyName.length)];

            NSString *outputString = [NSString stringWithFormat:@"NSLocalizedString(%@, %@)", keyName, string];
            
            addedLength = addedLength + outputString.length - string.length;
            
            if ([textView shouldChangeTextInRange:matchedRangeInDocument replacementString:outputString])
            {
                [textView.textStorage replaceCharactersInRange:matchedRangeInDocument
                                          withAttributedString:[[NSAttributedString alloc] initWithString:outputString]];
                
                NSFileHandle *fh = [self localizibleStringsFile];
                
                if (!fh)
                {
                    NSRunAlertPanel(@"", @"", @"OK", @"", nil);
                }
                
                [fh seekToEndOfFile];
                
                NSString *keyValueString =
                [NSString stringWithFormat:@"%@ = %@;\n", [keyName substringFromIndex:1], [string substringFromIndex:1]];
                
                [fh writeData:[keyValueString dataUsingEncoding:NSUTF8StringEncoding]];
                
                [fh closeFile];
                
                [textView didChangeText];
            }
            
            //            [textView replaceCharactersInRange:matchedRangeInDocument withString:outputString];
            //            NSAlert *alert = [NSAlert alertWithMessageText:outputString defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:@""];
            //            [alert runModal];
        }
    }
}

- (BOOL)isRange:(NSRange)range inSkipedRanges:(NSArray *)ranges {
    for (int i = 0; i < [ranges count]; i++) {
        NSTextCheckingResult *result = [ranges objectAtIndex:i];
        NSRange skippedRange = result.range;
        if (skippedRange.location <= range.location && skippedRange.location + skippedRange.length > range.location + range.length) {
            return YES;
        }
    }
    return NO;
}

@end
