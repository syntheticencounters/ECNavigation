#import "ECNavigation.h"

@import Mapbox;
@import MapboxNavigation;
@import MapboxDirections;
@import MapboxNavigationNative;
@import MapboxCoreNavigation;

@implementation ECNavigation

RCT_EXPORT_MODULE()

NSString *MapboxAccessToken = nil;
MBRoute *route = nil;
MBDirections *directions = nil;
MBNavigationService *navigation = nil;
MBRouteStep *currentStep = nil;
MBNavigationLocationManager *manager = nil;

RCT_EXPORT_METHOD(setKey:(NSString *)key)
{
    MapboxAccessToken = key;
}

RCT_REMAP_METHOD(getDirections,
                 locations:(NSArray *)locations
                 travelMode:(NSString *)travelMode
                 calculateRouteWithResolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    
    // Token
    if(!MapboxAccessToken) {
        NSError *error = [NSError errorWithDomain:@"ec-navigation" code:(404) userInfo:nil];
        reject(@"error", @"MapBox key has not been set", error);
        return;
    }
    
    // Coordinates
    NSMutableArray<MBWaypoint *> *waypoints = [NSMutableArray new];
    for(NSDictionary* location in locations) {
        
        NSString *name = location[@"name"];
        NSNumber *latitude = location[@"latitude"];
        NSNumber *longitude = location[@"longitude"];
        if(!latitude || !longitude) {
            NSError *error = [NSError errorWithDomain:@"ec-navigation" code:(404) userInfo:nil];
            reject(@"error", @"Unsupported coordinate found for route request", error);
            return;
        }
        
        CLLocation *place = [[CLLocation alloc] initWithLatitude:(CLLocationDegrees)[latitude doubleValue] longitude:(CLLocationDegrees)[longitude doubleValue]];
        [waypoints addObject: [[MBWaypoint alloc] initWithCoordinate:place.coordinate coordinateAccuracy:-1 name:name]];
    }
    
    MBDirectionsProfileIdentifier identifier = MBDirectionsProfileIdentifierAutomobile;
    if([travelMode isEqual: @"walking"]) {
        identifier = MBDirectionsProfileIdentifierWalking;
    }
    
    MBRouteOptions *options = [[MBRouteOptions alloc] initWithWaypoints:waypoints profileIdentifier:identifier];
    options.includesSteps = true;
    options.routeShapeResolution = MBRouteShapeResolutionFull;
    options.shapeFormat = MBRouteShapeFormatPolyline6;
    
    directions = [[MBDirections alloc] initWithAccessToken:MapboxAccessToken];
    [directions calculateDirectionsWithOptions :options completionHandler:^(NSArray<MBWaypoint *> * _Nullable waypoints, NSArray<MBRoute *> * _Nullable routes, NSError * _Nullable error) {
        if (error) {
            reject(@"error", error.localizedDescription, error);
            return;
        }
            
        route = routes.firstObject;
        if(!route) {
            NSError *error = [NSError errorWithDomain:@"ec-navigation" code:(404) userInfo:nil];
            reject(@"error", @"No routes found", error);
            return;
        }
        
        NSMutableArray *routeLegs = [NSMutableArray new];
        for (MBRouteLeg *leg in route.legs) {
            
            NSMutableArray *routeSteps = [NSMutableArray new];
            for (MBRouteStep *step in leg.steps) {
                
                // Coordinates
                NSMutableArray *coordinates = [NSMutableArray new];
                for (NSValue *coordinate in step.coordinates) {
                    [coordinates addObject:@[
                        [NSNumber numberWithDouble:coordinate.MGLCoordinateValue.latitude],
                        [NSNumber numberWithDouble:coordinate.MGLCoordinateValue.longitude]
                        
                    ]];
                }
                // Step Data
                NSDictionary<NSString *, id> *stepData = @{
                    @"name": step.instructions,
                    @"direction": [self directionToString:step.maneuverDirection],
                    @"polyline": coordinates
                };
                [ routeSteps addObject:stepData];
            }
            
            // Leg Data
            NSDictionary<NSString *, id> *legData = @{
                @"summary": leg.name,
                @"distance": [NSNumber numberWithDouble:leg.distance],
                @"duration": [NSNumber numberWithDouble:leg.expectedTravelTime],
                @"steps": routeSteps
            };
            
            [routeLegs addObject:legData];
        }
        
        NSMutableArray *coordinates = [NSMutableArray new];
        for (NSValue *coordinate in route.coordinates) {
           
            [coordinates addObject:@[
                [NSNumber numberWithDouble:coordinate.MGLCoordinateValue.latitude],
                [NSNumber numberWithDouble:coordinate.MGLCoordinateValue.longitude]
            ]];
        }
        
        NSDictionary<NSString *, id> *routeData = @{
            @"legs": routeLegs,
            @"polyline": coordinates,
            @"distance": [NSNumber numberWithDouble:route.distance],
            @"duration": [NSNumber numberWithDouble:route.expectedTravelTime],
           
        };
        resolve(routeData);
    }];
}

RCT_REMAP_METHOD(startNavigation,
                 startNavigationWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        
        if(navigation) {
            [navigation stop];
            navigation = nil;
        }
        
        if(!route) {
            NSError *error = [NSError errorWithDomain:@"ec-navigation" code:(400) userInfo:nil];
            reject(@"error", @"Unable to calculate the route", error);
            return;
        }
        
        if(!directions) {
            NSError *error = [NSError errorWithDomain:@"ec-navigation" code:(400) userInfo:nil];
            reject(@"error", @"Unable to gather directions for the route", error);
            return;
        }
        
        // fix this => route simulation
        manager = [[MBNavigationLocationManager alloc] init];
        //manager = [[MBSimulatedLocationManager alloc] initWithRoute:route];
        
        // fix this => route simulation
        MBNavigationSimulationOptions simulate = MBNavigationSimulationOptionsNever;
        //MBNavigationSimulationOptions simulate = MBNavigationSimulationOptionsAlways;
        
        navigation = [[MBNavigationService alloc] initWithRoute:route directions:directions locationSource:manager eventsManagerType:nil simulating:simulate routerType:nil];
        navigation.delegate = self;
        //navigation.simulationSpeedMultiplier = 25;
        
        [navigation start];
    });
    
    resolve(@"Navigation started");
}

RCT_REMAP_METHOD(stopNavigation,
                 stopNavigationWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    if(navigation) {
        [navigation stop];
        resolve(@"Navigation stopped");
    } else {
        NSError *error = [NSError errorWithDomain:@"ec-navigation" code:(400) userInfo:nil];
        reject(@"error", @"Navigation has not been setup", error);
    }
}

- (NSString*) directionToString:(MBManeuverDirection)direction
{
    NSString *string = nil;
    switch (direction) {
    case MBManeuverDirectionRight:
        string = @"right";
        break;
    case MBManeuverDirectionLeft:
        string = @"left";
        break;
    case MBManeuverDirectionNone:
        string = @"none";
        break;
    case MBManeuverDirectionUTurn:
        string = @"u-turn";
        break;
    case MBManeuverDirectionSharpLeft:
        string = @"sharp-left";
        break;
    case MBManeuverDirectionSharpRight:
        string = @"sharp-right";
        break;
    case MBManeuverDirectionSlightLeft:
        string = @"slight-left";
        break;
    case MBManeuverDirectionSlightRight:
        string = @"slight-right";
        break;
    case MBManeuverDirectionStraightAhead:
        string = @"strait-ahead";
        break;
                        
    default:
        break;
    }
    
    return string;
}

- (void)navigationService:(id<MBNavigationService>)service willRerouteFromLocation:(CLLocation *)location {
    
    NSDictionary<NSString *, id> *locationData = @{
        @"latitude": [NSNumber numberWithDouble:location.coordinate.latitude],
        @"longitude": [NSNumber numberWithDouble:location.coordinate.longitude]
    };
    
    NSDictionary<NSString *, id> *offRoute = @{
        @"location":locationData
    };
    
    NSLog(@"off route and recalculating");
    [self sendEventWithName:(@"offRoute") body:(offRoute)];
}

- (void)navigationService:(id<MBNavigationService>)service willArriveAtWaypoint:(MBWaypoint *)waypoint after:(NSTimeInterval)remainingTimeInterval distance:(CLLocationDistance)distance {
    
    NSLog(@"will arrive at waypoint");
    NSDictionary<NSString *, id> *progressData = @{
        @"name": waypoint.name
    };
    [self sendEventWithName:(@"willArriveAtWaypoint") body:(progressData)];
}


- (void)navigationService:(id<MBNavigationService>)service didUpdateProgress:(MBRouteProgress *)progress withLocation:(CLLocation *)location rawLocation:(CLLocation *)rawLocation
{
    MBRouteStep *step = progress.currentLegProgress.currentStep;
    currentStep = step;
    
    NSMutableDictionary *stepData = [NSMutableDictionary dictionary];
    [stepData setObject: step.instructions forKey:@"text"];
    [stepData setObject: [self directionToString:step.maneuverDirection] forKey:@"direction"];
    [stepData setObject: [NSNumber numberWithDouble:progress.currentLegProgress.currentStepProgress.distanceRemaining] forKey:@"distanceToEnd"];
    
    // Show next step if available
    NSMutableDictionary *nextStepData = [NSMutableDictionary dictionary];
    if(progress.currentLegProgress.upcomingStep) {
        
        MBRouteStep *nextStep = progress.currentLegProgress.upcomingStep;
        [nextStepData setObject: nextStep.instructions forKey:@"text"];
        [nextStepData setObject: [self directionToString:nextStep.maneuverDirection] forKey:@"direction"];
        [nextStepData setObject: [NSNumber numberWithDouble:progress.currentLegProgress.currentStepProgress.distanceRemaining] forKey:@"distanceToEnd"];
    }
    
    NSDictionary<NSString *, id> *progressData = @{
        @"location": @{
            @"heading": [NSNumber numberWithDouble:location.course],
            @"latitude": [NSNumber numberWithDouble:location.coordinate.latitude],
            @"longitude": [NSNumber numberWithDouble:location.coordinate.longitude],
            @"speed": [NSNumber numberWithDouble:location.speed], // meters per second to miles per hour
        },
        @"remainingDistance": [NSNumber numberWithDouble:progress.distanceRemaining],
        @"remainingDuration": [NSNumber numberWithDouble:progress.durationRemaining],
        @"remainingLegs": [NSNumber numberWithLong:progress.remainingLegs.count],
        @"remainingSteps":[NSNumber numberWithLong:progress.remainingSteps.count],
        @"currentStep": stepData,
        @"nextStep": nextStepData
    };
    
    [self sendEventWithName:(@"progressUpdated") body:(progressData)];
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"progressUpdated", @"offRoute", @"willArriveAtWaypoint"];
}

@end
