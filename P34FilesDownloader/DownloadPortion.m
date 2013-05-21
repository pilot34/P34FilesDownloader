//
//  DownloadPortion.m
//  abookclub
//
//  Created by Глеб Тарасов on 27.03.12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "DownloadPortion.h"
#import "ASIHTTPRequest.h"

@interface DownloadPortion()


@property (strong, nonatomic) NSString *title;
@property (strong, nonatomic) NSArray *files;
@property (strong, nonatomic) NSString *destinationFolder;

@end

@implementation DownloadPortion : NSObject

- (id)initWithSingleUrl:(NSString *)url title:(NSString *)title folder:(NSString *)destinationFolder
{
    return [self initWithTitle:title files:@[url] folder:destinationFolder];
}

- (id)initWithSingleUrl:(NSString *)url folder:(NSString *)destinationFolder
{
    return [self initWithSingleUrl:url title:url folder:destinationFolder];
}

- (id)initWithTitle:(NSString *)title files:(NSArray *)files folder:(NSString *)destinationFolder
{
    self = [super init];
    if (self)
    {
        self.title = title;
        self.files = files;
        self.destinationFolder = destinationFolder;
    }
    return self;
}

- (NSString *)description
{
    return self.title;
}

@end

