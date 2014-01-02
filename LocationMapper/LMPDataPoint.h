//
//  LMPDataPoint.h
//  LocationMapper
//
//  Created by Eric Ito on 12/27/13.
//  Copyright (c) 2013 Eric Ito. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LMPDataPoint : NSObject

+(instancetype)pointWithLatitude:(double)lat longitude:(double)lng timestamp:(NSDate*)timestamp;

@property (nonatomic, assign, readonly) double latitude;
@property (nonatomic, assign, readonly) double longitude;
@property (nonatomic, strong, readonly) NSDate *timestamp;

@end
