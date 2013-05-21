//
//  DownloadPortion.h
//  abookclub
//
//  Created by Глеб Тарасов on 27.03.12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ASINetworkQueue.h"

@interface DownloadPortion : NSObject

@property (strong, nonatomic, readonly) NSString *title;
@property (strong, nonatomic, readonly) NSArray *files;
@property (strong, nonatomic, readonly) NSString *destinationFolder;

- (id)initWithSingleUrl:(NSString *)url folder:(NSString *)destinationFolder;
- (id)initWithSingleUrl:(NSString *)url title:(NSString *)title folder:(NSString *)destinationFolder;
- (id)initWithTitle:(NSString *)title files:(NSArray *)files folder:(NSString *)destinationFolder;

@end
