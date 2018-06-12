//
//  main.m
//  finddups
//
//  Created by david on 6/11/18.
//  Copyright © 2018 combobulated. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AppKit/NSWorkspace.h>

int usage() {
    NSLog(@"usage: finddup [-d|s|v|t] <path>");
    return 1;
}

int trashIsEmpty() {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *trashPath = [NSHomeDirectory() stringByAppendingPathComponent:@".Trash"];
    NSDirectoryEnumerator *e = [fm enumeratorAtPath:trashPath];
    BOOL empty = YES;
    for ( NSString *aFile in e ) {
        if ( ! [aFile isEqualToString:@".DS_Store"] ) {
            empty = NO;
            break;
        }
    }
    
    return empty;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        if ( argc < 2 ) {
            return usage();
        }
        
        NSString *arg1 = [NSString stringWithUTF8String:argv[1]];
        NSString *arg2 = nil;
        BOOL openJustSizeDups = NO;
        BOOL openDelete = NO;
        BOOL verbose = NO;
        BOOL delete = NO;
        BOOL shallow = NO;
        BOOL ignoreTrash = NO;
        if ( argc == 3 ) {
            arg2 = [NSString stringWithUTF8String:argv[2]];
            if ( [arg1 hasPrefix:@"-"] && [arg1 length] > 1 ) {
                NSString *chomp = [arg1 substringFromIndex:1];
                while ( [chomp length] ) {
                    NSString *anOption = [chomp substringToIndex:1];
                    if ( [anOption isEqualToString:@"o"] )
                        openJustSizeDups = YES;
                    else if ( [anOption isEqualToString:@"O"] )
                        openDelete = YES;
                    else if ( [anOption isEqualToString:@"d"] )
                        delete = YES;
                    else if ( [anOption isEqualToString:@"v"] )
                        verbose = YES;
                    else if ( [anOption isEqualToString:@"s"] )
                        shallow = YES;
                    else if ( [anOption isEqualToString:@"t"] )
                        ignoreTrash = YES;
                    else
                        return usage();
                    chomp = [chomp substringFromIndex:1];
                }
            } else {
                return usage();
            }
        }
        
        if ( delete && ! ignoreTrash && ! trashIsEmpty() ) {
            NSLog(@"please empty the trash first. use -t to override");
            return 2;
        }
        
        NSString *path = arg2 ? arg2 : arg1;
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDirectoryEnumerator *e = [fm enumeratorAtPath:path];
        NSArray *fileList = [e allObjects];
        
        NSUInteger dupSpace = 0;
        NSMutableDictionary *map = [NSMutableDictionary new];
        for ( NSString *aPath in fileList ) {
            if ( [aPath hasSuffix:@".DS_Store"] )
                continue;
            BOOL add = YES;
            NSString *fullPath = [path stringByAppendingPathComponent:aPath];
            NSDictionary *attrs = [fm attributesOfItemAtPath:fullPath error:nil];
            
            if ( ! [attrs[NSFileType] isEqualToString:NSFileTypeRegular] )
                continue;
            
            NSNumber *size = attrs[NSFileSize];
            NSArray *likeSized = [map allKeysForObject:size];
            if ( [likeSized count] ) {
                
                NSTask *cksum1 = [NSTask new];
                cksum1.launchPath = @"/usr/bin/cksum";
                cksum1.arguments = @[fullPath];
                NSPipe *pipe1 = [NSPipe new];
                cksum1.standardOutput = pipe1;
                [cksum1 launch];
                [cksum1 waitUntilExit];
                
                NSData *raw1 = [[pipe1 fileHandleForReading] readDataToEndOfFile];
                if ( [cksum1 terminationStatus] != 0 ) {
                    NSLog(@"failed to cksum %@: %d %s",aPath,[cksum1 terminationStatus],strerror([cksum1 terminationStatus]));
                    continue;
                }
                
                NSString *string1 = [NSString stringWithUTF8String:[raw1 bytes]];
                if ( ! string1 )
                    string1 = [NSString stringWithCString:[raw1 bytes] encoding:NSASCIIStringEncoding];
                if ( ! string1 || ! [string1 length] ) {
                    NSLog(@"failed to decode cksum output1 for %@ (%@)",aPath,raw1);
                    continue;
                }
                
                NSString *output1 = [[string1 componentsSeparatedByString:@" "] firstObject];
                
                for ( NSString *likeSize in likeSized ) {
                    NSString *otherFullPath = [path stringByAppendingPathComponent:likeSize];
                    
                    NSTask *cksum2 = [NSTask new];
                    cksum2.launchPath = @"/usr/bin/cksum";
                    cksum2.arguments = @[otherFullPath];
                    NSPipe *pipe2 = [NSPipe new];
                    cksum2.standardOutput = pipe2;
                    [cksum2 launch];
                    [cksum2 waitUntilExit];
                    
                    NSData *raw2 = [[pipe2 fileHandleForReading] readDataToEndOfFile];
                    if ( [cksum2 terminationStatus] != 0 || ! [raw2 length] ) {
                        NSLog(@"failed to cksum like-sized %@: %d %s",likeSize,[cksum2 terminationStatus],strerror([cksum2 terminationStatus]));
                        continue;
                    }
                    
                    NSString *string2 = [NSString stringWithUTF8String:[raw2 bytes]];
                    if ( ! string2 )
                        string2 = [NSString stringWithCString:[raw2 bytes] encoding:NSASCIIStringEncoding];
                    if ( ! string2 || ! [string2 length] ) {
                        NSLog(@"failed to decode cksum output2 for %@ (%@)",likeSize,raw2);
                        continue;
                    }
                    
                    NSString *output2 = [[string2 componentsSeparatedByString:@" "] firstObject];
                    if ( [output1 isEqualToString:output2] ) {
                        if ( verbose ) NSLog(@"*** %@ appears to be a dup of %@!",aPath,likeSize);
                        dupSpace += [size unsignedIntegerValue];
                        
                        if ( delete ) {
                            NSString *fileToDelete = nil;
                            if ( shallow ) {
                                NSInteger count1 = [[fullPath componentsSeparatedByString:@"/"] count];
                                NSInteger count2 = [[otherFullPath componentsSeparatedByString:@"/"] count];
                                fileToDelete = count1 > count2 ? otherFullPath : fullPath;
                                if ( verbose ) NSLog(@"deleting shallowest %@",fileToDelete);
                            } else {
                                fileToDelete = fullPath;
                                if ( verbose ) NSLog(@"deleting current file: %@",fileToDelete);
                            }
                            
                            if ( openDelete ) {
                                [[NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[fileToDelete,[fileToDelete isEqualToString:fullPath] ? otherFullPath : fullPath]] waitUntilExit];
                            } else {
                                NSURL *url = [NSURL fileURLWithPath:fileToDelete], *outURL = nil;
                                NSError *error = nil;
                                BOOL okay = [fm trashItemAtURL:url resultingItemURL:&outURL error:&error];
                                if ( ! okay ) {
                                    NSLog(@"error trashing %@: %@",fileToDelete,error);
                                } else {
                                    if ( verbose ) NSLog(@"trashed %@",fileToDelete);
                                }
                            }
                            
                            if ( [fileToDelete isEqualToString:otherFullPath] )
                                [map removeObjectForKey:size];
                            else
                                add = NO;
                        }
                    } else {
                        if ( verbose ) NSLog(@"*** %@ has the same size as %@, but they are different!",aPath,likeSize);
                        if ( openJustSizeDups )
                            [[NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[fullPath,otherFullPath]] waitUntilExit];
                    }
                }
            }
            if ( add )
                [map setObject:size forKey:aPath];
        }
        NSLog(@"space consumed by duplicates: %lu",dupSpace);
    }
    return 0;
}
