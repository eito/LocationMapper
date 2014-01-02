//
//  LMPDataPoint.m
//  LocationMapper
//
//  Created by Eric Ito on 12/27/13.
//  Copyright (c) 2013 Eric Ito. All rights reserved.
//

#import "LMPDataPoint.h"

@interface LMPDataPoint ()
@property (nonatomic, assign, readwrite) double latitude;
@property (nonatomic, assign, readwrite) double longitude;
@property (nonatomic, strong, readwrite) NSDate *timestamp;
@end

@implementation LMPDataPoint

-(id)initWithLatitude:(double)lat longitude:(double)lng timestamp:(NSDate*)t {
    self = [self init];
    if (self) {
        self.latitude = lat;
        self.longitude = lng;
        self.timestamp = t;
    }
    return self;
}

+(instancetype)pointWithLatitude:(double)lat longitude:(double)lng timestamp:(NSDate*)timestamp {
    return [[self alloc] initWithLatitude:lat longitude:lng timestamp:timestamp];
}

@end
