#import <React/RCTBridgeModule.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

#import <MapboxCoreNavigation/MapboxCoreNavigation.h>

@interface EcNavigation : RCTEventEmitter <RCTBridgeModule, NavigationServiceDelegate>

@end
