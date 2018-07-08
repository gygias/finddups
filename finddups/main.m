//
//  main.m
//  finddups
//
//  Created by david on 6/11/18.
//  Copyright © 2018 combobulated. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AppKit/NSWorkspace.h>

//#define USE_CKSUM 1

int usage(int help) {
    NSLog(@"usage: finddup [-d|s|v|t|o|O|h] <path>");
    if ( help ) {
        NSLog(@"  d - delete duplicate files");
        NSLog(@"  D - preserve 'deeper' files (e.g. if deeper-nested files have been manually sorted)");
        NSLog(@"      without this option, duplicate files are deleted in the order enumerated");
        NSLog(@"  v - verbose log spew");
        NSLog(@"  t - ignore trash-not-empty state");
        NSLog(@"");
        NSLog(@"  o - open like-sized but different files in preview");
        NSLog(@"  O - open duplicate files in preview. the file to be deleted is opened, and should be listed, first.");
        NSLog(@"      these options are intended for dry runs");
        NSLog(@"");
        NSLog(@"  h - display this usage info");
    }
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

int mydiff(NSString *file1, NSString *file2) {
    NSFileHandle *f1 = [NSFileHandle fileHandleForReadingAtPath:file1];
    if ( ! f1 ) {
        NSLog(@"failed to open: %@",file1);
        exit(1);
    }
    
    NSFileHandle *f2 = [NSFileHandle fileHandleForReadingAtPath:file2];
    if ( ! f2 ) {
        NSLog(@"failed to open: %@",file2);
        exit(1);
    }
    
    NSUInteger readBy = 4096;
    do {
        NSData *d1 = [f1 readDataOfLength:readBy];
        NSData *d2 = [f2 readDataOfLength:readBy];
        
        if ( ! d1 || ! d2 ) {
            NSLog(@"error reading: %@",d1 ? file2 : file1);
            exit(1);
        }
        
        if ( [d1 length] == 0 && [d1 isEqual:d2] )
            break;
        
        if ( [d1 length] != [d2 length] )
            return 1;
        else if ( ! [d1 isEqual:d2] )
            return 1;
        
    } while(1);
    
    return 0;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        
        if ( argc < 2 ) {
            return usage(0);
        }
        
        NSString *arg1 = [NSString stringWithUTF8String:argv[1]];
        NSString *arg2 = nil;
        BOOL openJustSizeDups = NO;
        BOOL openDelete = NO;
        BOOL verbose = NO;
        BOOL delete = NO;
        BOOL deeper = NO;
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
                    else if ( [anOption isEqualToString:@"D"] )
                        deeper = YES;
                    else if ( [anOption isEqualToString:@"t"] )
                        ignoreTrash = YES;
                    else if ( [anOption isEqualToString:@"h"] )
                        return usage(1);
                    else
                        return usage(0);
                    chomp = [chomp substringFromIndex:1];
                }
            } else {
                return usage(0);
            }
        } else if ( [arg1 hasPrefix:@"-"] )
            return usage(0);
        
        if ( delete && ! ignoreTrash && ! trashIsEmpty() ) {
            NSLog(@"please empty the trash first. use -t to override");
            return 2;
        }
        
        NSString *path = arg2 ? arg2 : arg1;
        NSFileManager *fm = [NSFileManager defaultManager];
        
        BOOL isDir = NO;
        if ( ! [fm fileExistsAtPath:path isDirectory:&isDir] ) {
            NSLog(@"not found: %@",path);
            return 1;
        } else if ( ! isDir ) {
            NSLog(@"not a directory: %@",path);
            return 1;
        }
        
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
                
#ifdef USE_CKSUM
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
#endif
                
                for ( NSString *likeSize in likeSized ) {
                    NSString *otherFullPath = [path stringByAppendingPathComponent:likeSize];
                    
#if USE_CKSUM
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
#else
                    if ( 0 == mydiff(fullPath,otherFullPath) ) {
#endif
                        if ( verbose ) NSLog(@"*** %@ appears to be a dup of %@!",aPath,likeSize);
                        dupSpace += [size unsignedIntegerValue];
                        
                        if ( delete ) {
                            NSString *fileToDelete = nil;
                            if ( deeper ) {
                                NSArray *ignoreSubdirs = @[@"_unsorted"];
                                NSArray *fullPathComponents = [fullPath pathComponents];
                                NSInteger count1 = [fullPathComponents count];
                                NSArray *otherFullPathComponents = [otherFullPath pathComponents];
                                NSInteger count2 = [otherFullPathComponents count];
                                for ( NSString *component in fullPathComponents ) {
                                    if ( [ignoreSubdirs containsObject:component] ) {
                                        //NSLog(@"'%@' contains '%@'!",fullPath,component);
                                        fileToDelete = fullPath;
                                        goto delete_found;
                                    }
                                }
                                for ( NSString *component in otherFullPathComponents ) {
                                    if ( [ignoreSubdirs containsObject:component] ) {
                                        //NSLog(@"'%@' contains '%@'!",otherFullPath,component);
                                        fileToDelete = otherFullPath;
                                        goto delete_found;
                                    }
                                }
                                fileToDelete = count1 > count2 ? otherFullPath : fullPath;
                            delete_found:
                                    
                                //NSLog(@"[%ld]:%@ vs [%ld]:%@",count1,fullPath,count2,otherFullPath);
                                if ( verbose ) NSLog(@"trashing shallower file: %@ vs %@",fileToDelete,[fileToDelete isEqualToString:fullPath] ? otherFullPath : fullPath);
                            } else {
                                fileToDelete = fullPath;
                                if ( verbose ) NSLog(@"trashing current file: %@",fileToDelete);
                            }
                            
                            if ( openDelete ) {
                                [[NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[@"-a",@"Preview",fileToDelete,[fileToDelete isEqualToString:fullPath] ? otherFullPath : fullPath]] waitUntilExit];
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
                            [[NSTask launchedTaskWithLaunchPath:@"/usr/bin/open" arguments:@[@"-a",@"Preview",fullPath,otherFullPath]] waitUntilExit];
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
