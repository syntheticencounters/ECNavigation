// @flow

import React, { Component } from 'react';
import { NativeModules, NativeEventEmitter, DeviceEventEmitter, Platform } from 'react-native';
import Polyline from '@mapbox/polyline';

class Navigation {

    origin;
    destination;
    travelMode = 'driving';
    currentLocation;
    route;

    isRecalculating = false;
    onCalculatedRoute;
    onProgressUpdated;
    onStoppedNavigation;
    onRecalculated;
    onError;
    onCalculatedRouteError;
    recalculatingTolerance = -1;

    init = (origin, destination) => {
        this.origin = {
            latitude: origin.latitude ? parseFloat(origin.latitude) : null,
            longitude: origin.longitude ? parseFloat(origin.longitude) : null,
        };
        this.destination = {
            latitude: destination.latitude ? parseFloat(destination.latitude) : null,
            longitude: destination.longitude ? parseFloat(destination.longitude) : null,
        };

        NativeModules.Navigation.setKey('pk.eyJ1IjoibWlrZWNhcnAiLCJhIjoiY2pvZXF5ZnVjMDFhejNwbW1yaDRoNnpoNSJ9.l0qpJf-6yGDYmTXE0JFfVg');

        console.log('init');
        console.log(this.origin, this.destination);
    }

    calculateDirections = (callback) => {
        NativeModules.Navigation.calculateRoute(this.origin, this.destination, this.travelMode).then((route) => {

            this.route = route;
            let polyline = (Platform.OS == 'android') ? Polyline.decode(route.polyline, 6) : route.polyline;

            var coordinates = [];
            var encodedCoordinates = [];

            for(var i in polyline) {
                encodedCoordinates.push([polyline[i][1], polyline[i][0]]); // Reversed for MapBox
                coordinates.push({latitude: polyline[i][0], longitude: polyline[i][1]});
            }

            route.coordinates = coordinates;
            route.encoded_polyline = Polyline.encode(encodedCoordinates);

            this.onCalculatedRoute(route);
            if(callback) {
                callback();
            }

        }).catch((e) => {
            if(this.onCalculatedRouteError) {
                var message = e;
                if(e.toString().includes('A specified location could not be associated with a roadway or pathway')) {
                    message = 'One of the addresses may be incomplete or invalid'
                }
                this.onCalculatedRouteError(message);
            }
        });
    }

    startNavigation = (completion) => {

        if(!this.route) {
            if(this.onError) {
                this.onError('We were unable to find an accessible route for this Reservation');
            }
            return;
        }

        this.setListeners();
        NativeModules.Navigation.startNavigation().then((response) => {
            completion();
            this.isNavigating = true;

        }).catch((e) => {
            if(this.onError) {
                this.onError(e);
            }
            console.log(e);
        });
    }

    stopNavigation = (completion) => {

        this.isNavigating = false;
        NativeModules.Navigation.stopNavigation().then(() => {
            if(this.onStoppedNavigation) {
                this.onStoppedNavigation();
            }
            if(completion) { completion(); }
        }).catch((e) => {
            console.log(e);
        });
    }

    setListeners = () => {

        const emitter = new NativeEventEmitter(NativeModules.Navigation);
        emitter.addListener('progressUpdated', (data) => {
            if(this.onProgressUpdated) {
                this.onProgressUpdated(data);
            }
        });

        emitter.addListener('offRoute', (data) => {

            if(!this.currentLocation || this.isRecalculating) { return; }

            this.isRecalculating = true;
            NativeModules.Navigation.calculateRoute(this.currentLocation, this.destination, this.travelMode).then((route) => {

                this.route = route;
                let polyline = (Platform.OS == 'android') ? Polyline.decode(route.polyline, 6) : route.polyline;

                var coordinates = [];
                var encodedCoordinates = [];

                for(var i in polyline) {
                    encodedCoordinates.push([polyline[i][1], polyline[i][0]]); // Reversed for MapBox
                    coordinates.push({latitude: polyline[i][0], longitude: polyline[i][1]});
                }

                route.coordinates = coordinates;
                route.encoded_polyline = Polyline.encode(encodedCoordinates);

                NativeModules.Navigation.startNavigation().then((response) => {

                    this.isRecalculating = false;
                    if(this.onRecalculated) {
                        this.onRecalculated(route);
                    }
                })

            }).catch((e) => {
                console.log(e);
            });
        });
    }
}

export default Navigation;
