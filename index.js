import React, { Component } from 'react';
import { NativeModules, NativeEventEmitter, DeviceEventEmitter, Platform } from 'react-native';
import Polyline from '@mapbox/polyline';

const emitter = new NativeEventEmitter(NativeModules.ECNavigation);
class Navigation {

    route;
    active = false;
    subscribers = {};
    travelMode = 'driving';
    recalculatingTolerance = -1;

    constructor(key) {
        NativeModules.ECNavigation.setKey(key || 'pk.eyJ1IjoibWlrZWNhcnAiLCJhIjoiY2pvZXF5ZnVjMDFhejNwbW1yaDRoNnpoNSJ9.l0qpJf-6yGDYmTXE0JFfVg');
    }

    subscribe = (id, callbacks) => {
        this.subscribers[id] = {
            id: id,
            callbacks: callbacks
        };
        return this;
    }

    notifySubscribers = (key, props) => {

        Object.values(this.subscribers).forEach(({ id, callbacks }) => {
            if(typeof(callbacks[key]) === 'function') {
                callbacks[key](props);
            }
        })
    }

    unsubscribe = (id) => {
        delete this.subscribers[id];
    }

    getDirections = (locations, callback) => {

        NativeModules.ECNavigation.getDirections(locations.map((place, index) => {
            return {
                name: place.name || place.address,
                latitude: parseFloat(place.location ? place.location.latitude : place.latitude),
                longitude: parseFloat(place.location ? place.location.longitude : place.longitude)
            }
        }), this.travelMode).then((route) => {

            let polyline = (Platform.OS == 'android') ? Polyline.decode(route.polyline, 6) : route.polyline;
            route.coordinates = polyline.map(coordinate => [coordinate[0], coordinate[1]]);
            route.encoded_polyline = Polyline.encode(polyline.map(coordinate => [coordinate[1], coordinate[0]]));

            this.route = route;
            this.isRecalculating = false;
            this.notifySubscribers('onGetDirections', route);

        }).catch((e) => {

            let message = e;
            if(e.toString().includes('A specified location could not be associated with a roadway or pathway')) {
                message = 'One of the addresses may be incomplete or invalid'
            }
            this.notifySubscribers('onDirectionsError', message);
        });
    }

    startNavigation = () => {

        if(!this.route) {
            this.notifySubscribers('onNavigationError', 'We were unable to find an accessible route for this Reservation');
            return;
        }

        this.active = true;
        this.setListeners();
        NativeModules.ECNavigation.startNavigation().then((response) => {
            this.notifySubscribers('onStartNavigation');
        }).catch((e) => {
            this.notifySubscribers('onNavigationError', e);
        });
    }

    stopNavigation = () => {

        this.active = false;
        this.removeListeners();
        NativeModules.ECNavigation.stopNavigation().then(() => {
            this.notifySubscribers('onStopNavigation');
        }).catch((e) => {
            console.log(e);
        });
    }

    onArriveAtWaypoint = (data) => {
        console.log(data);
    }

    onRouteProgressChange = (data) => {
        this.notifySubscribers('onRouteProgressChange', data);
    }

    onRouteRecalculation = () => {
        if(this.isRecalculating) {
            return;
        }
        this.isRecalculating = true;
        this.notifySubscribers('onRouteRecalculation');
    }

    setListeners = () => {
        emitter.addListener('offRoute', this.onRouteRecalculation);
        emitter.addListener('progressUpdated', this.onRouteProgressChange);
        emitter.addListener('willArriveAtWaypoint', this.onArriveAtWaypoint);
    }

    removeListeners = () => {
        emitter.removeListener('offRoute', this.onRouteRecalculation);
        emitter.removeListener('progressUpdated', this.onRouteProgressChange);
        emitter.removeListener('willArriveAtWaypoint', this.onArriveAtWaypoint);
    }
}

export default Navigation;
