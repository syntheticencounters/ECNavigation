#if __has_include(<React/RCTBridgeModule.h>)
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#else
#import "RCTBridgeModule.h"
#import "RCTEventEmitter.h"
#endif

#if __has_include(<MapboxCoreNavigation/MapboxCoreNavigation.h>)
#import <MapboxCoreNavigation/MapboxCoreNavigation.h>
#else
#import "MapboxCoreNavigation.h"
#endif

@interface ECNavigation : RCTEventEmitter <RCTBridgeModule, NavigationServiceDelegate>

@end
