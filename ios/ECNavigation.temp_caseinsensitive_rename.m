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

RCT_EXPORT_METHOD(setKey:(NSString *)key)
{
    MapboxAccessToken = key;
}

RCT_REMAP_METHOD(calculateRoute,
                 originMap:(NSDictionary *)originMap
                 destinationMap:(NSDictionary *)destinationMap
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
    CLLocation *origin = [CLLocation init];
    CLLocationCoordinate2D originCoordinate;
    originCoordinate.latitude = (CLLocationDegrees)[originLat doubleValue];
    originCoordinate.longitude = (CLLocationDegrees)[originLong doubleValue];
    
    CLLocation *destination = [CLLocation init];
    CLLocationCoordinate2D destinationCoordinate;
    destinationCoordinate.latitude = (CLLocationDegrees)[destinationLat doubleValue];
    destinationCoordinate.longitude = (CLLocationDegrees)[destinationLong doubleValue];
    
    // Route
    NSArray *coordinates = [NSArray arrayWithObjects:origin, destination, nil];
    MBRouteOptions *options = [[MBRouteOptions alloc] initWithLocations:coordinates profileIdentifier:nil];
    
    directions = [MBDirections alloc];
    [[directions initWithAccessToken:MapboxAccessToken] calculateDirectionsWithOptions:options completionHandler:^(NSArray<MBWaypoint *> * _Nullable waypoints, NSArray<MBRoute *> * _Nullable routes, NSError * _Nullable error) {
        if (error) {
            reject(@"error", @"Error calculating route", error);
            return;
        }
            
        route = routes.firstObject;
        
        NSMutableArray *routeLegs = [NSMutableArray new];
        for (MBRouteLeg *leg in route.legs) {
                
            NSMutableArray *routeSteps = [NSMutableArray new];
            for (MBRouteStep *step in leg.steps) {
                    
                // Step Data
                NSDictionary<NSString *, id> *stepData = @{
                    @"name": step.instructions,
                    @"destinations": step.destinations,
                    @"exits": step.exitNames,
                    @"polyline": step.coordinates
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
        
        NSDictionary<NSString *, id> *routeData = @{
            @"distance": [NSNumber numberWithDouble:route.distance],
            @"duration": [NSNumber numberWithDouble:route.expectedTravelTime],
            @"polyline": route.coordinates,
            @"steps": routeLegs
        };
        
        resolve(routeData);
    }];
}

RCT_REMAP_METHOD(startNavigation,
                 startNavigationWithResolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)

{
    
    MBNavigationLocationManager *manager = [[MBNavigationLocationManager alloc] init];
    
    navigation = [[MBNavigationService alloc] initWithRoute:route directions:directions locationSource:manager eventsManagerType:nil simulating:MBNavigationSimulationOptionsNever routerType:nil];
    navigation.delegate = self;
    [navigation start];
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

- (void)navigationService:(id<MBNavigationService>)service willRerouteFromLocation:(CLLocation *)location {
    
    NSDictionary<NSString *, id> *locationData = @{
        @"latitude": [NSNumber numberWithDouble:location.coordinate.latitude],
        @"longitude": [NSNumber numberWithDouble:location.coordinate.longitude]
    };
    
    NSDictionary<NSString *, id> *offRoute = @{
        @"location":locationData
    };
    
    [self sendEventWithName:(@"offRoute") body:(offRoute)];
}

- (void)navigationService:(id<MBNavigationService>)service didUpdateProgress:(MBRouteProgress *)progress withLocation:(CLLocation *)location rawLocation:(CLLocation *)rawLocation

{
    
    MBRouteStep *step = progress.currentLegProgress.currentStep;
    
    NSMutableDictionary *stepData = [NSMutableDictionary dictionary];
    if(step.instructions) {
        
        currentStep = step;
        [stepData setObject:step.instructions forKey:@"text"];
        
        MBManeuverDirection direction = step.maneuverDirection;
        switch (direction) {
            case MBManeuverDirectionRight:
                [stepData setObject:@"right" forKey:@"direction"];
                break;
            case MBManeuverDirectionLeft:
                [stepData setObject:@"left" forKey:@"direction"];
                break;
            case MBManeuverDirectionNone:
                [stepData setObject:@"none" forKey:@"direction"];
                break;
            case MBManeuverDirectionUTurn:
                [stepData setObject:@"left" forKey:@"direction"];
                break;
            case MBManeuverDirectionSharpLeft:
                [stepData setObject:@"sharp left" forKey:@"direction"];
                break;
            case MBManeuverDirectionSharpRight:
                [stepData setObject:@"sharp right" forKey:@"direction"];
                break;
            case MBManeuverDirectionSlightLeft:
                [stepData setObject:@"slignt left" forKey:@"direction"];
                break;
            case MBManeuverDirectionSlightRight:
                [stepData setObject:@"slight right" forKey:@"direction"];
                break;
            case MBManeuverDirectionStraightAhead:
                [stepData setObject:@"strait ahead" forKey:@"direction"];
                break;
                
            default:
                break;
        }
        
        [stepData setObject: [NSNumber numberWithDouble:step.expectedTravelTime] forKey:@"distanceToEnd"];
        
        
    } else if(currentStep) {
        
        NSValue *lastStepPoint = step.coordinates[step.coordinates.count - 1];
        if(lastStepPoint) {
            CLLocation *coordinate = [[CLLocation alloc] initWithLatitude:lastStepPoint.MGLCoordinateValue.latitude longitude:lastStepPoint.MGLCoordinateValue.longitude];
            
            CLLocationDistance distance = [coordinate distanceFromLocation:location];
            
            [stepData setObject:currentStep.instructions forKey:@"text"];
            [stepData setObject: [NSNumber numberWithDouble: distance] forKey:@"distanceToEnd"];
            
            MBManeuverDirection direction = currentStep.maneuverDirection;
            switch (direction) {
                case MBManeuverDirectionRight:
                    [stepData setObject:@"right" forKey:@"direction"];
                    break;
                case MBManeuverDirectionLeft:
                    [stepData setObject:@"left" forKey:@"direction"];
                    break;
                case MBManeuverDirectionNone:
                    [stepData setObject:@"none" forKey:@"direction"];
                    break;
                case MBManeuverDirectionUTurn:
                    [stepData setObject:@"left" forKey:@"direction"];
                    break;
                case MBManeuverDirectionSharpLeft:
                    [stepData setObject:@"sharp left" forKey:@"direction"];
                    break;
                case MBManeuverDirectionSharpRight:
                    [stepData setObject:@"sharp right" forKey:@"direction"];
                    break;
                case MBManeuverDirectionSlightLeft:
                    [stepData setObject:@"slignt left" forKey:@"direction"];
                    break;
                case MBManeuverDirectionSlightRight:
                    [stepData setObject:@"slight right" forKey:@"direction"];
                    break;
                case MBManeuverDirectionStraightAhead:
                    [stepData setObject:@"strait ahead" forKey:@"direction"];
                    break;
                    
                default:
                    break;
            }
        }
    }
    
    
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
