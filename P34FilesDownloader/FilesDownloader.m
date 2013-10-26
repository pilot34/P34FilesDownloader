//
//  FilesDownloader.m
//  abookclub
//
//  Created by Глеб Тарасов on 26.03.12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "FilesDownloader.h"
#import "ASINetworkQueue.h"
#import "NSArray+P34Utils.h"
#import "P34Utils.h"

#define CUT_DOWNLOAD_SIZE_PERIOD 3
#define BANDWIDTH_WWAN_LIMIT 16000

static FilesDownloader *__shared;

@implementation NSNotification (FilesDownloader)

- (DownloadPortion *)portion
{
    return self.userInfo[FILES_DOWNLOADER_PORTION_KEY];
}

- (DownloadProgress *)progress
{
    return self.userInfo[FILES_DOWNLOADER_PROGRESS_KEY];
}

@end

@interface FilesDownloader()

@property(strong, atomic) NSArray *portionsQueue;
@property(strong, atomic) ASINetworkQueue *queue;
@property(strong, atomic) DownloadPortion *currentPortion;
@property(strong, atomic) NSDate *startDownloadingPortionDate;
@property(strong, atomic) NSArray *currentRequests;

@property(atomic) unsigned long long downlodedSizeFromCurrentPortion;
@property(atomic) unsigned long long cutDownloadedSize;
@property(atomic) BOOL wasError;
@property(atomic) BOOL wasCancelled;

@end

@implementation FilesDownloader

+ (FilesDownloader *)shared
{
    static FilesDownloader *__shared;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        __shared = [[FilesDownloader alloc] init];
    });
    
    return __shared;
}

- (id)init
{
    self = [super init];
    if (self) 
    {
        self.queue = [ASINetworkQueue queue];
    }
    return self;
}


- (BOOL)createFolder:(NSString *)folder
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if(![fileManager fileExistsAtPath:folder])
    {
        if(![fileManager createDirectoryAtPath:folder 
                   withIntermediateDirectories:YES
                                    attributes:nil
                                         error:NULL])
        {
            NSLog(@"Error: Create folder failed %@", folder);
            return NO;
        }
    }
    
    return YES;
}

- (NSArray *)requestsForPortion:(DownloadPortion *)portion
{
    NSMutableArray *result = [NSMutableArray array];
    self.downlodedSizeFromCurrentPortion = 0;
    
    for (NSString *url in portion.files)
    {
        NSString *path = [portion.destinationFolder stringByAppendingPathComponent:[url lastPathComponent]];
        NSString *partPath = [path stringByAppendingPathExtension:@"part"];

        // если уже скачали - добавлять не надо, но сохраним размер для правильного прогресса
        if ([NSFileManager.defaultManager fileExistsAtPath:path])
        {
            unsigned long long fileSize = [[NSFileManager.defaultManager attributesOfItemAtPath:path
                                                                                          error:nil] fileSize];
            self.downlodedSizeFromCurrentPortion += fileSize;
            continue;
        }
        
        ASIHTTPRequest *r = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:url]];
        r.downloadDestinationPath = path;
        r.temporaryFileDownloadPath = partPath;
        r.allowResumeForFileDownloads = YES;
        r.downloadProgressDelegate = self.queue;
        r.showAccurateProgress = YES;
        r.shouldContinueWhenAppEntersBackground = YES;
        r.allowCompressedResponse = self.allowCompressedResponse;
        [result addObject:r];
    }
    return result;
}

- (void)performEnqueue
{
    [self.queue reset];
    self.queue.downloadProgressDelegate = self;
    self.queue.queueDidFinishSelector = @selector(didDownloadPortion:);
    self.queue.requestDidStartSelector = @selector(didStartRequest:);
    self.queue.requestDidFailSelector = @selector(didFailRequest:);
    self.queue.requestDidFinishSelector = @selector(didFinishRequest:);
    self.queue.showAccurateProgress = YES;
    self.queue.shouldCancelAllRequestsOnFailure = YES;
    self.queue.delegate = self;
    NSArray *requests = [self requestsForPortion:self.currentPortion];
    
    if (requests.count == 0)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self didDownloadPortion:self.queue];
        });
        return;
    }
    
    for (ASIHTTPRequest *r in requests)
    {
        [self.queue addOperation:r];
    }
    
    self.startDownloadingPortionDate = NSDate.date;
    self.cutDownloadedSize = 0;
    
    [self.queue go];    
}


- (void)enqueuePortion:(DownloadPortion *)portion
{
    log(@"enqueuePortion %@ to queue %@", portion.title, self.queue);
    
    // отключаем таймер, чтобы не засыпало, пока качаем
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    
    @synchronized(self.class)
    {
        if (!self.currentPortion)
        {
            log(@"currentPortion = %@", portion.title);
            // если ничего не скачиваем - сразу запускаем очередь
            self.currentPortion = portion;
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self performEnqueue];
            });
        }
        else 
        {
            log(@"added to queue %@", portion.title);
            // иначе сохраняем на потом
            self.portionsQueue = self.portionsQueue ? [self.portionsQueue arrayByAddingObject:portion] : @[portion];
        }
    }
}

- (void)subscribeForNotifications:(id<FilesDownloaderDelegate>)object
{
    [NSNotificationCenter.defaultCenter addObserver:object
                                           selector:@selector(filesDownloaderDidDownload:)
                                               name:FILES_DOWNLOADER_DID_DOWNLOAD_NOTIFICATION
                                             object:nil];
    
    [NSNotificationCenter.defaultCenter addObserver:object
                                           selector:@selector(filesDownloaderDidFail:)
                                               name:FILES_DOWNLOADER_DID_FAIL_NOTIFICATION
                                             object:nil];
    
    [NSNotificationCenter.defaultCenter addObserver:object
                                           selector:@selector(filesDownloaderDidChangeProgress:)
                                               name:FILES_DOWNLOADER_DID_CHANGE_PROGRESS_NOTIFICATION
                                             object:nil];
}

- (void)unsubscribeFromNotifications:(id<FilesDownloaderDelegate>)object
{
    [NSNotificationCenter.defaultCenter removeObserver:object name:FILES_DOWNLOADER_DID_DOWNLOAD_NOTIFICATION
                                                object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:object name:FILES_DOWNLOADER_DID_FAIL_NOTIFICATION
                                                object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:object name:FILES_DOWNLOADER_DID_CHANGE_PROGRESS_NOTIFICATION
                                                object:nil];
}

- (void)notifyObserversWithProgress:(DownloadProgress *)progress
{
    NSMutableDictionary *ui = [NSMutableDictionary dictionary];
    if (progress)
        ui[FILES_DOWNLOADER_PROGRESS_KEY] = progress;
    if (self.currentPortion)
        ui[FILES_DOWNLOADER_PORTION_KEY] = self.currentPortion;
    
    [NSNotificationCenter.defaultCenter postNotificationName:FILES_DOWNLOADER_DID_CHANGE_PROGRESS_NOTIFICATION
                                                      object:nil
                                                    userInfo:ui];
}

- (void)notifyObserversWithFinish
{
    NSMutableDictionary *ui = [NSMutableDictionary dictionary];
    if (self.currentPortion)
        ui[FILES_DOWNLOADER_PORTION_KEY] = self.currentPortion;
    
    [NSNotificationCenter.defaultCenter postNotificationName:FILES_DOWNLOADER_DID_DOWNLOAD_NOTIFICATION
                                                      object:nil
                                                    userInfo:ui];
}

- (void)notifyObserversWithError
{
    NSMutableDictionary *ui = [NSMutableDictionary dictionary];
    if (self.currentPortion)
        ui[FILES_DOWNLOADER_PORTION_KEY] = self.currentPortion;
    ui[FILES_DOWNLOADER_CANCELLED_KEY] = @(self.wasCancelled);
    
    [NSNotificationCenter.defaultCenter postNotificationName:FILES_DOWNLOADER_DID_FAIL_NOTIFICATION
                                                      object:nil
                                                    userInfo:ui];
}

- (NSString *)downloadFileSynchronous:(NSString *)url folder:(NSString *)folder
{
    ASIHTTPRequest *r = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:url]];
    r.downloadDestinationPath = [folder stringByAppendingPathComponent:[url lastPathComponent]];
    [r startSynchronous];
    return r.downloadDestinationPath;
}

- (NSInteger)bytesPerSecond
{
    CGFloat spentSeconds = -self.startDownloadingPortionDate.timeIntervalSinceNow;
    
    if (spentSeconds > CUT_DOWNLOAD_SIZE_PERIOD && self.cutDownloadedSize == 0)
    {
        // обрезаем то, что скачано за первую секунду, чтобы не влияло на скорость уже загруженное
        self.cutDownloadedSize = self.queue.bytesDownloadedSoFar;
    }
    
    CGFloat downloadedSize = self.queue.bytesDownloadedSoFar - self.cutDownloadedSize;
    return roundf(downloadedSize / spentSeconds);
}

- (NSTimeInterval)remainingTimeInterval
{
    CGFloat bytesPerSecond = self.bytesPerSecond;
    
    if (bytesPerSecond == 0)
        return 0;
    
    CGFloat estimateSize = self.queue.totalBytesToDownload - self.queue.bytesDownloadedSoFar;
    CGFloat estimateSeconds = estimateSize / bytesPerSecond;
    return roundf(estimateSeconds);
}

- (void)resume
{
    if (self.currentPortion)
    {
        DownloadPortion *c = self.currentPortion;
        self.currentPortion = nil;
        [self.queue reset];
        // немного отложим, чтоб успели очиститься старые реквесты
        doAfter(2, ^{
            [self enqueuePortion:c];
        });
    }
}

- (BOOL)isDownloadingPortion:(NSString *)portion
{
    @synchronized(self.class)
    {
        return [self.currentPortion.title isEqualToString:portion] || [self.portionsQueue any:^BOOL(id object){
            DownloadPortion *p = object;
            return [p.title isEqualToString:portion];
        }];
    }
}

- (void)cancelAllPortions
{
    @synchronized(self.class)
    {
        self.portionsQueue = nil;
        self.currentPortion = nil;
        [self.queue reset];
    }
}

- (void)cancelPortion:(NSString *)portion
{
    @synchronized(self.class)
    {
        if ([self.currentPortion.title isEqualToString:portion])
        {
            // чтобы уведомление не отправилось - обнуляем
            [self.queue reset];
            
            // откладываем, иначе реквесты cancell-ется
            doAfter(1, ^{
                self.wasCancelled = YES;
                [self didDownloadPortion:self.queue];
            });
        }
        else
        {
            self.portionsQueue = [self.portionsQueue where:^BOOL(id object){
                DownloadPortion *p = object;
                return ![p.title isEqualToString:portion];
            }];
        }
    }
}

#pragma mark - ASIHTTPRequestDownloadProgress

- (void)setProgress:(CGFloat)progress
{
    // если head еще не загрузились - не обновляем
    if (self.queue.totalBytesToDownload == 0)
        return;
    
    DownloadProgress *p = [[DownloadProgress alloc] init];
    p.bytesPerSecond = self.bytesPerSecond;
    
    // хз, почему надо делить пополам, но так заработало корректно
    p.totalBytes = self.queue.totalBytesToDownload / 2 + self.downlodedSizeFromCurrentPortion;
    p.downloadedBytes = self.queue.bytesDownloadedSoFar / 2 + self.downlodedSizeFromCurrentPortion;
    p.progress = ((CGFloat)p.downloadedBytes) / p.totalBytes;
    p.remainingTime = self.remainingTimeInterval;
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self notifyObserversWithProgress:p];
    });
}

- (void)didDownloadPortion:(ASINetworkQueue *)queue
{
    // возвращаем засыпание в зад
    if (self.portionsQueue.count == 0)
        UIApplication.sharedApplication.idleTimerDisabled = NO;
    
    if (self.wasError || self.wasCancelled)
    {        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self notifyObserversWithError];
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                [self.queue reset];
                self.currentPortion = nil;
                self.wasError = NO;
                self.wasCancelled = NO;
            });
        });
        return;
    }
    
    log(@"didDownloadPortion %@", self.currentPortion.title);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self notifyObserversWithFinish];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self.queue reset];
            self.currentPortion = nil;
            
            if (self.portionsQueue.count > 0)
            {
                DownloadPortion *first = self.portionsQueue.firstObject;
                self.portionsQueue = [self.portionsQueue subarrayWithRange:NSMakeRange(1, self.portionsQueue.count - 1)];
                [self enqueuePortion:first];
            }
        });
    });
}

- (void)didStartRequest:(ASIHTTPRequest *)request
{
    NSArray *requests = self.currentRequests ? self.currentRequests : @[];
    self.currentRequests = [requests arrayByAddingObject:request];
}

- (void)removeRequestFromCurrent:(ASIHTTPRequest *)request
{
    NSMutableArray *requests = self.currentRequests.mutableCopy;
    [requests removeObject:request];
    self.currentRequests = requests;
}

- (void)didFinishRequest:(ASIHTTPRequest *)request
{
    [self removeRequestFromCurrent:request];
}

- (void)didFailRequest:(ASIHTTPRequest *)request
{
    // когда cancelled ничего делать не надо
    if (request.error.code == ASIRequestCancelledErrorType)
        return;
    
    self.wasError = YES;
    [self removeRequestFromCurrent:request];    
}

@end
