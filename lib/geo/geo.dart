import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';

class GeoService {
  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );
  
  static StreamSubscription<Position>? _positionStream;
  static Function(List<dynamic>)? _proximityCallback;
  
  static Future<Position?> getCurrentPosition() async {
    _logger.i('🌍 Requesting current position...');
    
    if (!await Geolocator.isLocationServiceEnabled()) {
      _logger.w('⚠️ Location services are disabled');
      return null;
    }
    
    var permission = await Geolocator.checkPermission();
    _logger.d('📍 Current permission status: $permission');
    
    if (permission == LocationPermission.denied) {
      _logger.i('🔒 Requesting location permission...');
      permission = await Geolocator.requestPermission();
      _logger.i('🔓 Permission result: $permission');
      if (permission == LocationPermission.denied) {
        _logger.e('❌ Location permission denied');
        return null;
      }
    }   
    
    final position = await Geolocator.getCurrentPosition();
    _logger.i('✅ Position obtained: ${position.latitude}, ${position.longitude}');
    return position;
  }
  
  /// Start continuous background location tracking
  static Future<bool> startBackgroundTracking({
    required Function(List<dynamic>) onNearbyUsers,
  }) async {
    _logger.i('🚀 Starting background location tracking...');
    
    if (!await Geolocator.isLocationServiceEnabled()) {
      _logger.e('❌ Location services not enabled');
      return false;
    }
    
    var permission = await Geolocator.checkPermission();
    _logger.d('📍 Current permission: $permission');
    
    if (permission == LocationPermission.denied) {
      _logger.i('🔒 Requesting location permission for background tracking...');
      permission = await Geolocator.requestPermission();
      _logger.i('🔓 Permission result: $permission');
    }
    
    if (permission == LocationPermission.denied || 
        permission == LocationPermission.deniedForever) {
      _logger.e('❌ Cannot start tracking - permission denied');
      return false;
    }
    
    _proximityCallback = onNearbyUsers;
    
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Update every 5 meters
    );
    
    _logger.i('📡 Starting position stream with 5m distance filter...');
    
    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings
    ).listen((Position position) {
      _logger.d('📍 New position: ${position.latitude}, ${position.longitude} (±${position.accuracy}m)');
      _checkProximity(position);
    });
    
    _logger.i('✅ Background tracking started successfully!');
    return true;
  }
  
  /// Stop background tracking
  static void stopBackgroundTracking() {
    _logger.i('🛑 Stopping background location tracking...');
    _positionStream?.cancel();
    _positionStream = null;
    _proximityCallback = null;
    _logger.i('✅ Background tracking stopped');
  }
  
  /// Check for nearby users (placeholder - replace with your API call)
  static void _checkProximity(Position currentPosition) async {
    _logger.d('🔍 Checking proximity at ${currentPosition.latitude}, ${currentPosition.longitude}');
    
    // TODO: Replace with your actual API call to get nearby users
    // Example API call:
    // final nearbyUsers = await ApiService.getNearbyUsers(
    //   lat: currentPosition.latitude,
    //   lng: currentPosition.longitude,
    //   radius: 50 // 50 feet
    // );
    
    // For now, just call the callback with current position
    final mockNearbyUsers = [
      {
        'lat': currentPosition.latitude,
        'lng': currentPosition.longitude,
        'timestamp': DateTime.now().toIso8601String(),
        'accuracy': currentPosition.accuracy,
      }
    ];
    
    _logger.i('👥 Found ${mockNearbyUsers.length} nearby users (mock data)');
    _proximityCallback?.call(mockNearbyUsers);
  }
  
  /// Calculate distance between two points in feet
  static double distanceInFeet(double lat1, double lng1, double lat2, double lng2) {
    double distanceInMeters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    return distanceInMeters * 3.28084; // Convert meters to feet
  }
}