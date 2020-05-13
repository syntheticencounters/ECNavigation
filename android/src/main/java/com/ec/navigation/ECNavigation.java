// Adapted from
// https://github.com/gijoehosaphat/react-native-keep-screen-on

package com.ec.navigation;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.location.Location;

import com.facebook.react.bridge.ActivityEventListener;
import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.ReactContext;
import com.facebook.react.bridge.ReadableMap;
import com.facebook.react.bridge.Promise;
import com.facebook.react.modules.core.DeviceEventManagerModule;

import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.WritableArray;
import com.facebook.react.bridge.WritableMap;
import com.mapbox.android.core.location.LocationEngineRequest;

import com.mapbox.api.directions.v5.DirectionsCriteria;
import com.mapbox.api.directions.v5.models.DirectionsRoute;
import com.mapbox.api.directions.v5.models.LegStep;
import com.mapbox.api.directions.v5.models.RouteLeg;

import com.mapbox.api.directions.v5.models.RouteOptions;
import com.mapbox.geojson.Point;
import com.mapbox.mapboxsdk.geometry.LatLng;
import com.mapbox.navigator.BannerInstruction;
import com.mapbox.services.android.navigation.v5.navigation.MapboxNavigation;
import com.mapbox.services.android.navigation.v5.navigation.NavigationRoute;
import com.mapbox.api.directions.v5.models.DirectionsResponse;
import com.mapbox.services.android.navigation.v5.offroute.OffRouteListener;
import com.mapbox.services.android.navigation.v5.routeprogress.ProgressChangeListener;
import com.mapbox.services.android.navigation.v5.routeprogress.RouteProgress;

import retrofit2.Call;
import retrofit2.Callback;
import retrofit2.Response;

import java.util.List;

public class ECNavigation extends ReactContextBaseJavaModule implements ActivityEventListener {

    private Context context;
    private DirectionsRoute route;
    private MapboxNavigation navigation;
    private String key;
    private BannerInstruction currentStep;
    private OffRouteListener offRouteListener;
    private ProgressChangeListener progressChangeListener;

    public ECNavigation(ReactApplicationContext reactContext) {
        super(reactContext);
        context = reactContext;
    }

    @Override
    public String getName() {
        return "ECNavigation";
    }

    @ReactMethod
    public void setKey(String key) {
        this.key = key;
    }

    @ReactMethod
    public void calculateRoute(ReadableMap originMap, ReadableMap destinationMap, String travelMode, final Promise promise) {

        if(key == null) {
            promise.reject("404", "MapBox key has not been set");
            return;
        }

        if(originMap == null) {
            promise.reject("404", "Pickup location has not been set for this Reservation");
            return;
        }
        if(destinationMap == null) {
            promise.reject("404", "Drop off location has not been set for this Reservation");
            return;
        }

        final ECNavigation currentClass = this;
        Point origin = Point.fromLngLat(originMap.getDouble("longitude"), originMap.getDouble("latitude"));
        Point destination = Point.fromLngLat(destinationMap.getDouble("longitude"), destinationMap.getDouble("latitude"));

        String criteria = DirectionsCriteria.PROFILE_DRIVING_TRAFFIC;
        if(travelMode.equals("walking")) {
            criteria = DirectionsCriteria.PROFILE_WALKING;
        }

        NavigationRoute.builder(context)
                .accessToken(this.key)
                .origin(origin)
                .destination(destination)
                .profile(criteria)
                .build()
                .getRoute(new Callback<DirectionsResponse>() {
                    @Override
                    public void onResponse(Call<DirectionsResponse> call, Response<DirectionsResponse> response) {
                        List<DirectionsRoute> routes = response.body().routes();
                        if(routes.size() > 0) {

                            DirectionsRoute route = routes.get(0);
                            currentClass.route = route;

                            WritableMap map = Arguments.createMap();
                            map.putDouble("distance", route.distance());
                            map.putDouble("duration", route.duration());
                            map.putString("polyline", route.geometry());

                            List<RouteLeg> legs = route.legs();
                            if(legs != null) {

                                WritableArray routeLegs = Arguments.createArray();
                                for (int i = 0; i < legs.size(); i++) {

                                    WritableMap leg = Arguments.createMap();
                                    leg.putString("summary", legs.get(i).summary());
                                    leg.putDouble("distance", legs.get(i).distance());
                                    leg.putDouble("duration", legs.get(i).duration());

                                    // Steps
                                    List<LegStep> steps = legs.get(i).steps();
                                    if(steps != null) {

                                        WritableArray routeSteps = Arguments.createArray();
                                        for (int ii = 0; ii < steps.size(); ii++) {

                                            WritableMap step = Arguments.createMap();
                                            step.putString("name", steps.get(ii).name());
                                            step.putString("destinations", steps.get(ii).destinations());
                                            step.putString("exits", steps.get(ii).exits());
                                            step.putString("polyline", steps.get(ii).geometry());
                                            step.putString("ref", steps.get(ii).ref());
                                            routeSteps.pushMap(step);
                                        }
                                        map.putArray("steps", routeSteps);
                                    }
                                }
                            }

                            promise.resolve(map);

                        } else {
                            promise.reject("404", "No routes found for the supplied coordinates");
                        }
                    }

                    @Override
                    public void onFailure(Call<DirectionsResponse> call, Throwable t) {
                        promise.reject("400", t.getMessage());
                    }
                });
    }

    @ReactMethod
    public void startNavigation(final Promise promise) {

        LocationEngineRequest locationEngineRequest = new LocationEngineRequest.Builder(1000)
                .setPriority(LocationEngineRequest.PRIORITY_HIGH_ACCURACY)
                .setMaxWaitTime(3000)
                .build();

        if(navigation != null) {
            navigation.stopNavigation();

            // User Left Route
            if(offRouteListener != null) {
                navigation.removeOffRouteListener(offRouteListener);
            }
            // Progress Changes and Updates
            if(progressChangeListener != null) {
                navigation.removeProgressChangeListener(progressChangeListener);
            }

            navigation = null;
        }

        navigation = new MapboxNavigation(getReactApplicationContext(), key);
        navigation.setLocationEngineRequest(locationEngineRequest);
        navigation.startNavigation(route);

        offRouteListener = new OffRouteListener() {
            @Override
            public void userOffRoute(Location location) {
                WritableMap map = Arguments.createMap();
                WritableMap locationMap = Arguments.createMap();
                locationMap.putDouble("latitude", location.getLatitude());
                locationMap.putDouble("longitude", location.getLongitude());
                map.putMap("location", locationMap);
                sendEvent(getReactApplicationContext(), "offRoute", map);
            }
        };
        navigation.addOffRouteListener(offRouteListener);

        progressChangeListener = new ProgressChangeListener() {
            @Override
            public void onProgressChange(Location location, RouteProgress progress) {

                WritableMap map = Arguments.createMap();
                WritableMap step = Arguments.createMap();
                BannerInstruction banner = progress.bannerInstruction();
                if(banner != null) {

                    currentStep = banner;
                    step.putString("text", banner.getPrimary().getText());
                    step.putString("direction", banner.getPrimary().getModifier());
                    step.putDouble("distanceToEnd", banner.getRemainingStepDistance());
                    map.putMap("currentStep", step);

                } else if(currentStep != null) {

                    Point lastStepPoint = progress.currentStepPoints().get(progress.currentStepPoints().size() - 1);
                    LatLng lastPoint = new LatLng(lastStepPoint.latitude(), lastStepPoint.longitude());
                    double distance = lastPoint.distanceTo(new LatLng(location));

                    step.putString("text", currentStep.getPrimary().getText());
                    step.putString("direction", currentStep.getPrimary().getModifier());
                    step.putDouble("distanceToEnd", distance);
                    map.putMap("currentStep", step);
                }

                WritableMap userLocation = Arguments.createMap();
                userLocation.putDouble("latitude", location.getLatitude());
                userLocation.putDouble("longitude", location.getLongitude());

                map.putDouble("remainingDistance", progress.currentLegProgress().distanceRemaining());
                map.putDouble("remainingDuration", progress.currentLegProgress().durationRemaining());

                sendEvent(getReactApplicationContext(), "progressUpdated", map);
                promise.resolve("Monitor Route Changes Enabled");
            }
        };
        navigation.addProgressChangeListener(progressChangeListener);

        promise.resolve("Navigation Started");
    }

    @ReactMethod
    public void stopNavigation(final Promise promise) {
        if(navigation != null) {
            navigation.stopNavigation();
            promise.resolve(true);
        } else {
            promise.reject("400", "Navigation has not been setup");
        }
    }

    @Override
    public void onActivityResult(Activity activity, int requestCode, int resultCode, Intent data) {

    }

    @Override
    public void onNewIntent(Intent intent) {

    }

    private void sendEvent(ReactContext reactContext,
                           String eventName,
                           ReadableMap object) {
        reactContext
                .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter.class)
                .emit(eventName, object);
    }
}
