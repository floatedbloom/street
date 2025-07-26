import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../ai/matchmaker.dart';
import '../services/notification_service.dart';

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
  static Function()? _onNewMatchCallback;
  static String? _currentUserId;
  static UserProfile? _currentUserProfile;
  static SupabaseClient get _supabase => Supabase.instance.client;
  
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
  
  /// Start continuous background location tracking with matchmaking
  static Future<bool> startBackgroundTracking({
    required Function(List<dynamic>) onNearbyUsers,
    required String userId,
    required UserProfile userProfile,
    Function()? onNewMatch,
  }) async {
    _logger.i('🚀 Starting background location tracking with matchmaking...');
    
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
    _onNewMatchCallback = onNewMatch;
    _currentUserId = userId;
    _currentUserProfile = userProfile;
    
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5, // Update every 5 meters
    );
    
    _logger.i('📡 Starting position stream with 5m distance filter...');
    
    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings
    ).listen((Position position) {
      _logger.d('📍 New position: ${position.latitude}, ${position.longitude} (±${position.accuracy}m)');
      _checkProximityAndMatch(position);
    });
    
    _logger.i('✅ Background tracking with matchmaking started successfully!');
    return true;
  }
  
  /// Stop background tracking
  static void stopBackgroundTracking() {
    _logger.i('🛑 Stopping background location tracking...');
    _positionStream?.cancel();
    _positionStream = null;
    _proximityCallback = null;
    _onNewMatchCallback = null;
    _currentUserId = null;
    _currentUserProfile = null;
    _logger.i('✅ Background tracking stopped');
  }
  
  /// Check for nearby users and analyze matches
  static void _checkProximityAndMatch(Position currentPosition) async {
    if (_currentUserId == null || _currentUserProfile == null) {
      _logger.w('⚠️ Cannot check proximity - user ID or profile not set');
      return;
    }
    
    _logger.d('🔍 Checking proximity and matches at ${currentPosition.latitude}, ${currentPosition.longitude}');
    
    try {
      // Update current user's location in database
      await _updateUserLocation(_currentUserId!, currentPosition);
      
      // Get nearby users from database
      final nearbyUsers = await _getNearbyUsersFromDatabase(
        currentPosition, 
        _currentUserId!
      );
      
      _logger.i('👥 Found ${nearbyUsers.length} nearby users in database');
      
      // Filter users within 50 feet and check for matches
      final usersWithin100Feet = <Map<String, dynamic>>[];
      
      for (final user in nearbyUsers) {
        final userLat = user['latitude'] as double?;
        final userLng = user['longitude'] as double?;
        
        if (userLat != null && userLng != null) {
          final distance = distanceInFeet(
            currentPosition.latitude, 
            currentPosition.longitude,
            userLat,
            userLng
          );
          
          _logger.d('📏 Distance to ${user['name']}: ${distance.toStringAsFixed(1)} feet');
          
          if (distance <= 100.0) {
            _logger.i('🎯 User ${user['name']} is within 100 feet!');
            usersWithin100Feet.add(user);
            
            // Check if they're already matched
            final alreadyMatched = await MatchmakerService.areUsersMatched(
              _currentUserId!, 
              user['id']
            );
            
            if (!alreadyMatched) {
              _logger.i('💫 Analyzing potential match with ${user['name']}...');
              await _analyzeAndSaveMatch(user, currentPosition);
            } else {
              _logger.d('✅ Already matched with ${user['name']}');
            }
          }
        }
      }
      
      // Call the callback with users within 50 feet
      _proximityCallback?.call(usersWithin100Feet);
      
    } catch (e) {
      _logger.e('❌ Error checking proximity and matches: $e');
    }
  }
  
  /// Update user's current location in database
  static Future<void> _updateUserLocation(String userId, Position position) async {
    try {
      await _supabase
          .from('people')
          .update({
            'latitude': position.latitude,
            'longitude': position.longitude,
            'last_seen': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
      
      _logger.d('📍 Updated location for user $userId');
    } catch (e) {
      _logger.e('❌ Failed to update user location: $e');
    }
  }
  
  /// Get nearby users from database within a reasonable radius
  static Future<List<Map<String, dynamic>>> _getNearbyUsersFromDatabase(
    Position currentPosition, 
    String currentUserId
  ) async {
    try {
      // Get users within approximately 1000 feet (rough database filter)
      // We'll do precise distance checking in memory
      const double radiusInDegrees = 0.003; // Roughly 1000 feet
      
      final response = await _supabase
          .from('people')
          .select('id, name, phone, bio, latitude, longitude, last_seen')
          .neq('id', currentUserId) // Exclude current user
          .not('latitude', 'is', null)
          .not('longitude', 'is', null)
          .gte('latitude', currentPosition.latitude - radiusInDegrees)
          .lte('latitude', currentPosition.latitude + radiusInDegrees)
          .gte('longitude', currentPosition.longitude - radiusInDegrees)
          .lte('longitude', currentPosition.longitude + radiusInDegrees)
          .gte('last_seen', DateTime.now().subtract(Duration(hours: 1)).toIso8601String()); // Only active users
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      _logger.e('❌ Failed to get nearby users from database: $e');
      return [];
    }
  }
  
  /// Analyze compatibility and save match if successful
  static Future<void> _analyzeAndSaveMatch(
    Map<String, dynamic> nearbyUser, 
    Position currentPosition
  ) async {
    try {
      // Create UserProfile for nearby user
      final nearbyUserProfile = UserProfile(
        name: nearbyUser['name'] ?? 'Unknown',
        age: _extractAgeFromBio(nearbyUser['bio']),
        bio: _extractBioText(nearbyUser['bio']),
        interests: _extractInterests(nearbyUser['bio']),
      );
      
      _logger.d('🤖 Analyzing match between ${_currentUserProfile!.name} and ${nearbyUserProfile.name}');
      
      // Analyze match using AI
      final matchResult = await MatchmakerService.analyzeAndSaveMatch(
        userId1: _currentUserId!,
        userId2: nearbyUser['id'],
        user1Profile: _currentUserProfile!,
        user2Profile: nearbyUserProfile,
        latitude: currentPosition.latitude,
        longitude: currentPosition.longitude,
      );
      
      if (matchResult.isMatch) {
        _logger.i('🎉 NEW MATCH! ${_currentUserProfile!.name} ↔ ${nearbyUserProfile.name}');
        _logger.i('💝 Compatibility: ${(matchResult.compatibilityScore * 100).toStringAsFixed(1)}%');
        _logger.i('🧠 AI Reasoning: ${matchResult.reasoning}');
        
        // Send notification for the new match
        try {
          await NotificationService.sendMatchNotification(
            matchedUserName: nearbyUserProfile.name,
            compatibilityScore: matchResult.compatibilityScore,
            reasoning: matchResult.reasoning,
          );
        } catch (e) {
          _logger.e('❌ Failed to send match notification: $e');
        }
        
        // Trigger new match callback to reload page
        if (_onNewMatchCallback != null) {
          _logger.i('🔄 Triggering page reload for new match...');
          _onNewMatchCallback!();
        }
      } else {
        _logger.d('❌ No match with ${nearbyUserProfile.name} (${(matchResult.compatibilityScore * 100).toStringAsFixed(1)}%)');
      }
      
    } catch (e) {
      _logger.e('❌ Failed to analyze match: $e');
    }
  }
  
  /// Extract age from bio data
  static int _extractAgeFromBio(dynamic bio) {
    if (bio is Map && bio['age'] != null) {
      return bio['age'] is int ? bio['age'] : int.tryParse(bio['age'].toString()) ?? 25;
    }
    return 25; // Default age
  }
  
  /// Extract bio text from bio data
  static String _extractBioText(dynamic bio) {
    if (bio is Map && bio['bio'] != null) {
      return bio['bio'].toString();
    }
    if (bio is String) {
      return bio;
    }
    return 'No bio available';
  }
  
  /// Extract interests from bio data
  static List<String> _extractInterests(dynamic bio) {
    if (bio is Map && bio['interests'] != null) {
      if (bio['interests'] is List) {
        return List<String>.from(bio['interests']);
      }
      if (bio['interests'] is String) {
        return bio['interests'].toString().split(',').map((e) => e.trim()).toList();
      }
    }
    return [];
  }
  
  /// Calculate distance between two points in feet
  static double distanceInFeet(double lat1, double lng1, double lat2, double lng2) {
    double distanceInMeters = Geolocator.distanceBetween(lat1, lng1, lat2, lng2);
    return distanceInMeters * 3.28084; // Convert meters to feet
  }
  
  /// Get current matches for user (convenience method)
  static Future<List<Map<String, dynamic>>> getCurrentUserMatches() async {
    if (_currentUserId == null) {
      throw Exception('No current user set');
    }
    return await MatchmakerService.getUserMatches(_currentUserId!);
  }
}