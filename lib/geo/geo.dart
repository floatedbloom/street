import 'dart:async';
import 'package:geolocator/geolocator.dart';

class GeoService {
  static StreamSubscription<Position>? _positionStream;
  static Function(List<dynamic>)? _proximityCallback;
  
  static Future<Position?> getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }   
    return await Geolocator.getCurrentPosition();
  }
  
  /// Start continuous background location tracking
  static Future<bool> startBackgroundTracking({
    required Function(List<dynamic>) onNearbyUsers,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    if (permission == LocationPermission.denied || 
        permission == LocationPermission.deniedForever) {
      return false;
    }
    
    _proximityCallback = onNearbyUsers;
    
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Update every 5 meters
    );
    
    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings
    ).listen((Position position) {
      _checkProximity(position);
    });
    
    return true;
  }
  
  /// Stop background tracking
  static void stopBackgroundTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _proximityCallback = null;
  }
  
  /// Check for nearby users (placeholder - replace with your API call)
  static void _checkProximity(Position currentPosition) async {
    // TODO: Replace with your actual API call to get nearby users
    // Example API call:
    // final nearbyUsers = await ApiService.getNearbyUsers(
    //   lat: currentPosition.latitude,
    //   lng: currentPosition.longitude,
    //   radius: 50 // 50 feet
    // );
    
    // For now, just call the callback with current position
    _proximityCallback?.call([
      {
        'lat': currentPosition.latitude,
        'lng': currentPosition.longitude,
        'timestamp': DateTime.now().toIso8601String(),
      }
    ]);
  }
  
  /// Calculate distance between two points in feet
  static double distanceInFeet(double lat1, double lng1, double lat2, double lng2) {
    double distanceInMeters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    return distanceInMeters * 3.28084; // Convert meters to feet
  }
}