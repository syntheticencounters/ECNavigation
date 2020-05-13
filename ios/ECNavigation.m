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

RCT_REMAP_METHOD(calculateRoute,
                 originMap:(NSDictionary *)originMap
                 destinationMap:(NSDictionary *)destinationMap
                 travelMode:(NSString *)travelMode
                 calculateRouteWithResolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject)
{
    
    // Token
    if(!MapboxAccessToken) {
        NSError *error = [NSError errorWithDomain:@"ec-navigation" code:(404) userInfo:nil];
        reject(@"error", @"MapBox key has not been set", error);
        return;
    }
    
    // Dictionary
    NSNumber *originLat = originMap[@"latitude"];
    NSNumber *originLong = originMap[@"longitude"];
    if(!originLat || !originLong) {
        NSError *error = [NSError errorWithDomain:@"ec-navigation" code:(404) userInfo:nil];
        reject(@"error", @"Invalid origin coordinate", error);
        return;
    }
    
    NSNumber *destinationLat = destinationMap[@"latitude"];
    NSNumber *destinationLong = destinationMap[@"longitude"];
    if(!destinationLat || !destinationLong) {
        NSError *error = [NSError errorWithDomain:@"ec-navigation" code:(404) userInfo:nil];
        reject(@"error", @"Invalid destination coordinate", error);
        return;
    }
    
    // Coordinates
    CLLocation *origin = [[CLLocation alloc] initWithLatitude:(CLLocationDegrees)[originLat doubleValue] longitude:(CLLocationDegrees)[originLong doubleValue]];
    
    CLLocation *destination = [[CLLocation alloc] initWithLatitude:(CLLocationDegrees)[destinationLat doubleValue] longitude:(CLLocationDegrees)[destinationLong doubleValue]];
    
    // Route
    NSArray<MBWaypoint *> *waypoints = @[
        [[MBWaypoint alloc] initWithCoordinate:origin.coordinate coordinateAccuracy:-1 name:@"origin"],
        [[MBWaypoint alloc] initWithCoordinate:destination.coordinate coordinateAccuracy:-1 name:@"destination"]
    ];
    
    MBDirectionsProfileIdentifier identifier = MBDirectionsProfileIdentifierAutomobileAvoidingTraffic;
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
        
        MBRouteLeg *leg = route.legs.firstObject;
        if(!leg) {
            NSError *error = [NSError errorWithDomain:@"ec-navigation" code:(404) userInfo:nil];
            reject(@"error", @"No steps found within the route", error);
            return;
        }
        
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
        
        NSMutableArray *coordinates = [NSMutableArray new];
        for (NSValue *coordinate in route.coordinates) {
            
            [coordinates addObject:@[
                [NSNumber numberWithDouble:coordinate.MGLCoordinateValue.latitude],
                [NSNumber numberWithDouble:coordinate.MGLCoordinateValue.longitude]
            ]];
        }
        
        NSDictionary<NSString *, id> *routeData = @{
            @"distance": [NSNumber numberWithDouble:route.distance],
            @"duration": [NSNumber numberWithDouble:route.expectedTravelTime],
            @"polyline": coordinates,
            @"steps": legData
        };
        
        resolve(routeData);
    }];
}

RCT_REMAP_METHOD(startNavigation,
                 startNavigationWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)

{
    
    dispatch_async(dispatch_get_main_queue(), ^{
        
        manager = [[MBNavigationLocationManager alloc] init];
        
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
        
        navigation = [[MBNavigationService alloc] initWithRoute:route directions:directions locationSource:manager eventsManagerType:nil simulating:MBNavigationSimulationOptionsNever routerType:nil];
            navigation.delegate = self;
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
        string = @"u turn";
        break;
    case MBManeuverDirectionSharpLeft:
        string = @"sharp left";
        break;
    case MBManeuverDirectionSharpRight:
        string = @"sharp right";
        break;
    case MBManeuverDirectionSlightLeft:
        string = @"slight left";
        break;
    case MBManeuverDirectionSlightRight:
        string = @"slight right";
        break;
    case MBManeuverDirectionStraightAhead:
        string = @"strait ahead";
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

- (void)navigationService:(id<MBNavigationService>)service didUpdateProgress:(MBRouteProgress *)progress withLocation:(CLLocation *)location rawLocation:(CLLocation *)rawLocation
{
    
    MBRouteStep *step = progress.currentLegProgress.currentStep;
    currentStep = step;
    
    NSMutableDictionary *stepData = [NSMutableDictionary dictionary];
    [stepData setObject: step.instructions forKey:@"text"];
    [stepData setObject: [self directionToString:step.maneuverDirection] forKey:@"direction"];
    [stepData setObject: [NSNumber numberWithDouble:progress.currentLegProgress.currentStepProgress.distanceRemaining] forKey:@"distanceToEnd"];
    
    // Show next step if available
    if(progress.currentLegProgress.upcomingStep) {
        
        MBRouteStep *nextStep = progress.currentLegProgress.upcomingStep;
        
        [stepData setObject: nextStep.instructions forKey:@"text"];
        [stepData setObject: [self directionToString:nextStep.maneuverDirection] forKey:@"direction"];
        [stepData setObject: [NSNumber numberWithDouble:progress.currentLegProgress.currentStepProgress.distanceRemaining] forKey:@"distanceToEnd"];
    }
    /*
    if(step.instructions) {
        
        currentStep = step;
        [stepData setObject:step.instructions forKey:@"text"];
        [stepData setObject: [self directionToString:step.maneuverDirection] forKey:@"direction"];
        [stepData setObject: [NSNumber numberWithDouble:progress.currentLegProgress.currentStepProgress.distanceRemaining] forKey:@"distanceToEnd"];
        
        
    } else if(currentStep) {
        
        NSValue *lastStepPoint = step.coordinates[step.coordinates.count - 1];
        if(lastStepPoint) {
            CLLocation *coordinate = [[CLLocation alloc] initWithLatitude:lastStepPoint.MGLCoordinateValue.latitude longitude:lastStepPoint.MGLCoordinateValue.longitude];
            
            CLLocationDistance distance = [coordinate distanceFromLocation:location];
            
            [stepData setObject:currentStep.instructions forKey:@"text"];
            [stepData setObject:[self directionToString:currentStep.maneuverDirection] forKey:@"directions"];
            [stepData setObject:[NSNumber numberWithDouble: distance] forKey:@"distanceToEnd"];
        }
    }
     */
    
    NSDictionary<NSString *, id> *progressData = @{
        @"location": @{
            @"latitude": [NSNumber numberWithDouble:location.coordinate.latitude],
            @"longitude": [NSNumber numberWithDouble:location.coordinate.longitude]
        },
        @"currentStep": stepData,
        @"remainingDistance": [NSNumber numberWithDouble:progress.distanceRemaining],
        @"remainingDuration": [NSNumber numberWithDouble:progress.durationRemaining]
    };
    
    [self sendEventWithName:(@"progressUpdated") body:(progressData)];
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"progressUpdated", @"offRoute"];
}

@end
