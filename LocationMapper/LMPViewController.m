//
//  LMPViewController.m
//  LocationMapper
//
//  Created by Eric Ito on 12/23/13.
//  Copyright (c) 2013 Eric Ito. All rights reserved.
//

#import "LMPViewController.h"
#import "LMPDataPoint.h"

#import "FMDatabase.h"
#import "FMDatabaseAdditions.h"
#import "FMResultSet.h"
#import "FMDatabaseQueue.h"

// TODO: Add dump button for manual saving
#define IN_MEMORY_POINT_THRESHOLD   1000

//#define QUICK_INSERT_LOTS_OF_POINTS
//#define SIMULATED_POINT_FACTOR      1000

@interface LMPViewController ()<UITableViewDataSource, UITableViewDelegate, CLLocationManagerDelegate>
{
    BOOL _deferringUpdates;
    BOOL _collecting;
    NSMutableArray *_points;
    CLLocation *_lastLocation;
    CLCircularRegion *_region;
}

@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) NSMutableArray *inMemoryLocations;
@property (nonatomic, assign) long long databasePointCount;

@property (nonatomic, weak) IBOutlet UITableView *tableView;

@property (nonatomic, strong) NSString *documentsPath;
@property (nonatomic, strong) FMDatabase *database;
@property (nonatomic, strong) FMDatabaseQueue *databaseQueue;

@property (nonatomic, strong) NSNumberFormatter *numberFormatter;
@end
        
@implementation LMPViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    self.navigationItem.title = @"Location Mapper";
    
    UIBarButtonItem *gpsBBI = [[UIBarButtonItem alloc] initWithTitle:@"Start" style:UIBarButtonItemStylePlain target:self action:@selector(toggleGPS)];
    self.navigationItem.leftBarButtonItem = gpsBBI;
    
    UIBarButtonItem *bbi = [[UIBarButtonItem alloc] initWithTitle:@"Dump" style:UIBarButtonItemStylePlain target:self action:@selector(dumpLocations)];
    self.navigationItem.rightBarButtonItem = bbi;
    
    self.inMemoryLocations = [NSMutableArray array];
    
    NSString *path = [self.documentsPath stringByAppendingPathComponent:@"points.db"];

    self.databaseQueue = [FMDatabaseQueue databaseQueueWithPath:path];

    __weak LMPViewController *weakSelf = self;
    //
    // if our db doesn't have a table yet...create it.
    [self.databaseQueue inDatabase:^(FMDatabase *db) {
        if (![db tableExists:@"points"]) {
            [db executeUpdate:@"CREATE TABLE points (lat REAL, lng REAL, timestamp INTEGER)"];
        }
        else {
            weakSelf.databasePointCount = [db longForQuery:@"select count(*) from points;"];
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.tableView reloadData];
            });
        }
    }];
    
    [self setupLocation];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark Internal

//
// this is called when user explicitly clicks start/stop
-(void)toggleGPS {
    if (!_collecting) {
        //
        // if we were monitoring a region when the user clicked "start"
        // we need to stop monitoring and just restart location updates
        if (_region) {
            [self.locationManager stopMonitoringForRegion:_region];
            _region = nil;
        }
        [self startGPS];
    }
    else {
        [self stopGPS];
    }
    _collecting = !_collecting;
}

//
// this is called when the user leaves a region and when the
// user clicks "start"
-(void)startGPS {
    UIBarButtonItem *bbi = self.navigationItem.leftBarButtonItem;
    bbi.title = @"Stop";
    [_locationManager startUpdatingLocation];
}

//
// called when user clicks "stop"
-(void)stopGPS {
    UIBarButtonItem *bbi = self.navigationItem.leftBarButtonItem;
    bbi.title = @"Start";
    [_locationManager stopUpdatingLocation];
}

-(void)setupLocation {
    _locationManager = [[CLLocationManager alloc] init];
    _locationManager.activityType = CLActivityTypeFitness;
    _locationManager.delegate = self;
    _locationManager.desiredAccuracy =  kCLLocationAccuracyBest;
    _locationManager.distanceFilter = kCLDistanceFilterNone;
//    _locationManager.pausesLocationUpdatesAutomatically = YES;
    _locationManager.allowsBackgroundLocationUpdates = YES;
    [_locationManager requestWhenInUseAuthorization];
}

-(void)setupDatabase {
    if (![self.database tableExists:@"points"]) {
        [self.database executeUpdate:@"CREATE TABLE points (lat REAL, lng REAL, timestamp INTEGER)"];
    }
}

-(void)dumpLocations {
    NSArray *locationsToDB = [self.inMemoryLocations copy];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self addLocationsToDatabase:locationsToDB];
    });
    [self.inMemoryLocations removeAllObjects];
}

-(void)addLocationsToDatabase:(NSArray*)locations {
    __weak LMPViewController *weakSelf = self;
    [self.databaseQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
#ifdef QUICK_INSERT_LOTS_OF_POINTS
        for (int i = 0; i < SIMULATED_POINT_FACTOR; i++) {
#endif
            for (CLLocation *location in locations) {
                [db executeUpdate:[NSString stringWithFormat:@"insert into points values (%f, %f, %lld)", location.coordinate.latitude, location.coordinate.longitude, (long long)([location.timestamp timeIntervalSince1970] * 1000)]];
            }
#ifdef QUICK_INSERT_LOTS_OF_POINTS
        }
#endif
        weakSelf.databasePointCount = [db longForQuery:@"select count(*) from points"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.tableView reloadData];
        });
    }];
}

#pragma mark Lazy Loading

-(NSNumberFormatter *)numberFormatter {
    if (!_numberFormatter) {
        _numberFormatter = [[NSNumberFormatter alloc] init];
        _numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    }
    return _numberFormatter;
}

-(NSString *)documentsPath {
    if (!_documentsPath) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        _documentsPath = paths[0];
    }
    return _documentsPath;
}

#pragma mark UITableViewDataSource

-(NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

-(UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"MyCellIdentifier";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellIdentifier];
    }
    
    cell.textLabel.text = @"Points";
    
    if (indexPath.section == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.userInteractionEnabled = NO;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ points", [self.numberFormatter stringFromNumber:@(self.inMemoryLocations.count)]];
    }
    else {
        cell.selectionStyle = UITableViewCellSelectionStyleGray;
        
        // uncomment to test querying points from database on click
        //cell.userInteractionEnabled = YES;
        cell.userInteractionEnabled = NO;
        
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ points", [self.numberFormatter stringFromNumber:@(self.databasePointCount)]];
    }
    
    return cell;
}

-(NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

-(NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) {
        return @"In Memory";
    }
    else {
        return @"In Database";
    }
}

#pragma mark UITableViewDelegate

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && !_points) {
        _points = [NSMutableArray array];
        
        __weak NSMutableArray *weakPoints = _points;
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [self.databaseQueue inDatabase:^(FMDatabase *db) {
                double start = CACurrentMediaTime();
                NSLog(@"Start...%f", start);
                FMResultSet *resultSet = [db executeQuery:@"select * from points"];
                while ([resultSet next]) {
                    NSDate * timestamp = [NSDate dateWithTimeIntervalSince1970:[resultSet doubleForColumn:@"timestamp"]/1000];
                    LMPDataPoint *dp = [LMPDataPoint pointWithLatitude:[resultSet doubleForColumn:@"lat"]
                                                             longitude:[resultSet doubleForColumn:@"lng"]
                                                             timestamp:timestamp];
                    [weakPoints addObject:dp];
                }
                double end = CACurrentMediaTime();
                NSLog(@"end...%f", end);
                NSLog(@"elapsed...%f", end - start);
            }];
        });
    }
    else if (indexPath.section == 1) {
        
        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            __block double oldest1 = [[NSDate date] timeIntervalSince1970];
            __block double youngest1 = 0;
            
            double start = CACurrentMediaTime();
            for (LMPDataPoint *dp in _points) {
                double d = [dp.timestamp timeIntervalSince1970];
                if (d < oldest1) {
                    oldest1 = d;
                }
                if (d > youngest1) {
                    youngest1 = d;
                }
            }
            double end = CACurrentMediaTime();
            NSLog(@"enumerate - for/in - %f", end - start);
            NSLog(@"time diff = %f", youngest1 - oldest1);
            
        });
        
        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            __block double oldest2 = [[NSDate date] timeIntervalSince1970];
            __block double youngest2 = 0;
            double start = CACurrentMediaTime();
            [_points enumerateObjectsUsingBlock:^(LMPDataPoint *dp, NSUInteger idx, BOOL *stop) {
                double d = [dp.timestamp timeIntervalSince1970];
                if (d < oldest2) {
                    oldest2 = d;
                }
                if (d > youngest2) {
                    youngest2 = d;
                }
            }];
            double end = CACurrentMediaTime();
            NSLog(@"enumerate using block - %f", end - start);
            NSLog(@"time diff = %f", youngest2 - oldest2);
        });

        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            __block double oldest3 = [[NSDate date] timeIntervalSince1970];
            __block double youngest3 = 0;
            double start = CACurrentMediaTime();
            [_points enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(LMPDataPoint *dp, NSUInteger idx, BOOL *stop) {
                double d = [dp.timestamp timeIntervalSince1970];
                if (d < oldest3) {
                    oldest3 = d;
                }
                if (d > youngest3) {
                    youngest3 = d;
                }
            }];
            double end = CACurrentMediaTime();
            NSLog(@"enumerate using block (concurrent) - %f", end - start);
            NSLog(@"time diff = %f", youngest3 - oldest3);
        });
    }
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark CLLocationManagerDelegate

-(void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    
    //
    // keep track of our last location for region monitoring purposes
    _lastLocation = [locations lastObject];
    
    if (locations.count > 2) {
        UILocalNotification *ln = [[UILocalNotification alloc] init];
        ln.alertBody = [NSString stringWithFormat:@"%lu deferred updates", (unsigned long)locations.count];
        ln.hasAction = NO;
        ln.fireDate = [NSDate dateWithTimeIntervalSinceNow:1.0];
        [[UIApplication sharedApplication] scheduleLocalNotification:ln];
    }

    [self.inMemoryLocations addObjectsFromArray:locations];

    if (self.inMemoryLocations.count >= IN_MEMORY_POINT_THRESHOLD) {
        [self dumpLocations];
    }
    
    if (!_deferringUpdates && [CLLocationManager deferredLocationUpdatesAvailable]) {
        NSLog(@"DEFERRED UPDATES AVAILABLE");
        _deferringUpdates = YES;
        [_locationManager allowDeferredLocationUpdatesUntilTraveled:CLLocationDistanceMax timeout:CLTimeIntervalMax];
    }
    
    [self.tableView reloadData];
}

-(void)locationManager:(CLLocationManager *)manager didFinishDeferredUpdatesWithError:(NSError *)error {
    NSLog(@"Finished deferred updated: %@", error);
    UILocalNotification *ln = [[UILocalNotification alloc] init];
    ln.alertBody = [NSString stringWithFormat:@"Finished deferred updates: %@", error];
    ln.fireDate = [NSDate dateWithTimeIntervalSinceNow:1.0];
    ln.hasAction = NO;
    [[UIApplication sharedApplication] scheduleLocalNotification:ln];
    _deferringUpdates = NO;
}

-(void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    [self postLocalNotificationWithMessage:@"Left region! -- stopped monitoring, restarting location"];
    [manager stopMonitoringForRegion:region];
    _region = nil;
    [self startGPS];
}

-(void)locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLRegion *)region {
    [self postLocalNotificationWithMessage:@"Started monitoring region"];
}

-(void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error {
    [self postLocalNotificationWithMessage:[NSString stringWithFormat:@"Region monitoring failed: %@", error]];
}

//
// when location updates are paused -- monitor the current region so we can
// restart location updates when we begin moving
-(void)locationManagerDidPauseLocationUpdates:(CLLocationManager *)manager {

    [self postLocalNotificationWithMessage:@"Pausing location updates..."];
    
    //
    // create a region around our lastLocation
    NSString *regionIdentifier = [NSString stringWithFormat:@"%@.region", [[NSBundle mainBundle] bundleIdentifier]];
    _region = [[CLCircularRegion alloc] initWithCenter:_lastLocation.coordinate
                                                radius:50
                                            identifier:regionIdentifier];
    
    //
    // start monitoring this region
    [self.locationManager startMonitoringForRegion:_region];
    
    //
    // notify user if this coordinate isn't in the region -- may have poor GPS signal in this case
    if (![_region containsCoordinate:_lastLocation.coordinate]) {
        [self postLocalNotificationWithMessage:@"Region doesn't contain last coordinate"];
        [self.locationManager stopMonitoringForRegion:_region];
        _region = nil;
    }
}

#pragma mark Helper methods

-(void)postLocalNotificationWithMessage:(NSString*)message {
    UILocalNotification *ln = [[UILocalNotification alloc] init];
    ln.alertBody = message;
    ln.fireDate = [NSDate dateWithTimeIntervalSinceNow:1.0];
    ln.hasAction = NO;
    [[UIApplication sharedApplication] scheduleLocalNotification:ln];
    NSLog(@"Message: %@", message);
}

@end
