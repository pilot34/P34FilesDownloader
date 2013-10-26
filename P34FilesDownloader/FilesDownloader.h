//
//  FilesDownloader.h
//  abookclub
//
//  Created by Глеб Тарасов on 26.03.12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "DownloadPortion.h"
#import "DownloadProgress.h"
#import "ASIHTTPRequest.h"

#define FILES_DOWNLOADER_DID_DOWNLOAD_NOTIFICATION @"FILES_DOWNLOADER_DID_DOWNLOAD_NOTIFICATION"
#define FILES_DOWNLOADER_DID_FAIL_NOTIFICATION @"FILES_DOWNLOADER_DID_FAIL_NOTIFICATION"
#define FILES_DOWNLOADER_DID_CHANGE_PROGRESS_NOTIFICATION @"FILES_DOWNLOADER_DID_CHANGE_PROGRESS_NOTIFICATION"

#define FILES_DOWNLOADER_PORTION_KEY @"FILES_DOWNLOADER_PORTION_KEY"
#define FILES_DOWNLOADER_PROGRESS_KEY @"FILES_DOWNLOADER_PROGRESS_KEY"
#define FILES_DOWNLOADER_CANCELLED_KEY @"FILES_DOWNLOADER_CANCELLED_KEY"

@protocol FilesDownloaderDelegate <NSObject>

- (void)filesDownloaderDidDownload:(NSNotification *)notification;
- (void)filesDownloaderDidFail:(NSNotification *)notification;
- (void)filesDownloaderDidChangeProgress:(NSNotification *)notification;

@end

@interface NSNotification (FilesDownloader)

@property (strong, nonatomic, readonly) DownloadPortion *portion;
@property (strong, nonatomic, readonly) DownloadProgress *progress;

@end

@interface FilesDownloader : NSObject

+ (FilesDownloader *)shared;

- (void)enqueuePortion:(DownloadPortion *)portion;
- (NSString *)downloadFileSynchronous:(NSString *)url folder:(NSString *)folder;
- (BOOL)isDownloadingPortion:(NSString *)portion;

- (void)subscribeForNotifications:(id<FilesDownloaderDelegate>)object;
- (void)unsubscribeFromNotifications:(id<FilesDownloaderDelegate>)object;

// нужно вызывать в applicationDidEnterForeground
- (void)resume;

- (void)cancelAllPortions;
- (void)cancelPortion:(NSString *)portion;


@property(nonatomic) BOOL allowCompressedResponse;

@end
