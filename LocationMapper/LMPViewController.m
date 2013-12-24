//
//  LMPViewController.m
//  LocationMapper
//
//  Created by Eric Ito on 12/23/13.
//  Copyright (c) 2013 Eric Ito. All rights reserved.
//

#import "LMPViewController.h"
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
//    self.database = [FMDatabase databaseWithPath:path];
//    [self.database open];
//    [self setupDatabase];
    
    [self setupLocation];
}

//-(void)viewWillAppear:(BOOL)animated {
//    [super viewWillAppear:animated];
//}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark Internal

-(void)toggleGPS {
    UIBarButtonItem *bbi = self.navigationItem.leftBarButtonItem;
    if (!_collecting) {
        bbi.title = @"Stop";
        [_locationManager startUpdatingLocation];
    }
    else {
        bbi.title = @"Start";
        [_locationManager stopUpdatingLocation];
    }
    _collecting = !_collecting;
}

-(void)setupLocation {
    _locationManager = [[CLLocationManager alloc] init];
    _locationManager.activityType = CLActivityTypeFitness;
    _locationManager.delegate = self;
    _locationManager.desiredAccuracy =  kCLLocationAccuracyBest;
    _locationManager.distanceFilter = kCLDistanceFilterNone;
    _locationManager.pausesLocationUpdatesAutomatically = NO;
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
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ points", [self.numberFormatter stringFromNumber:@(self.inMemoryLocations.count)]];
    }
    else {
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

#pragma mark CLLocationManagerDelegate

-(void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
//    NSLog(@"Updated with %d locations %@", locations.count, locations);

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
    [[UIApplication sharedApplication] scheduleLocalNotification:ln];
    _deferringUpdates = NO;
}
@end
