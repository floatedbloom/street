import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Represents a user profile for matching
class UserProfile {
  final String name;
  final int age;
  final String bio;
  final List<String> interests;

  UserProfile({
    required this.name,
    required this.age,
    required this.bio,
    required this.interests,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'age': age,
    'bio': bio,
    'interests': interests,
  };
}

/// Match result with compatibility score and reasoning
class MatchResult {
  final bool isMatch;
  final double compatibilityScore; // 0.0 to 1.0
  final String reasoning;
  final List<String> commonInterests;

  MatchResult({
    required this.isMatch,
    required this.compatibilityScore,
    required this.reasoning,
    required this.commonInterests,
  });
}

class MatchmakerService {
  static String? get _apiKey => dotenv.env['GEMINI_API_KEY'];
  static SupabaseClient get _supabase => Supabase.instance.client;

  static GenerativeModel? _model;

  static GenerativeModel get model {
    if (_model == null) {
      final apiKey = _apiKey;
      if (apiKey == null) {
        throw Exception('GEMINI_API_KEY not found in .env file');
      }
      _model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.7, // Increased from 0.4 for more flexible matching
          topK: 1,
          topP: 1,
          maxOutputTokens: 500,
        ),
      );
    }
    return _model!;
  }

  /// Determines if two users should match using Gemini AI
  static Future<MatchResult> shouldMatch(
    UserProfile user1,
    UserProfile user2,
  ) async {
    try {
      final prompt = _buildMatchingPrompt(user1, user2);
      final response = await model.generateContent([Content.text(prompt)]);
      return _parseMatchResponse(response.text ?? '', user1, user2);
    } catch (e) {
      throw Exception('Failed to determine match compatibility: $e');
    }
  }

  /// Analyzes compatibility and saves match if successful
  static Future<MatchResult> analyzeAndSaveMatch({
    required String userId1,
    required String userId2,
    required UserProfile user1Profile,
    required UserProfile user2Profile,
    double? latitude,
    double? longitude,
  }) async {
    try {
      // First, analyze compatibility
      final matchResult = await shouldMatch(user1Profile, user2Profile);

      // If it's a match, save to database
      if (matchResult.isMatch) {
        await saveMatch(
          userId1: userId1,
          userId2: userId2,
          matchResult: matchResult,
          latitude: latitude,
          longitude: longitude,
        );
      }

      return matchResult;
    } catch (e) {
      throw Exception('Failed to analyze and save match: $e');
    }
  }

  /// Saves a match to the database using the create_match RPC function
  static Future<String?> saveMatch({
    required String userId1,
    required String userId2,
    required MatchResult matchResult,
    double? latitude,
    double? longitude,
  }) async {
    try {
      // The current user should be userId1, and the other user should be userId2
      // But we need to determine which one is the "other" user relative to the current auth user
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        throw Exception('No authenticated user');
      }
      
      String otherUserId;
      if (currentUser.id == userId1) {
        otherUserId = userId2;
      } else if (currentUser.id == userId2) {
        otherUserId = userId1;
      } else {
        throw Exception('Current user is not part of this match');
      }

      // Use the create_match RPC function
      final result = await _supabase.rpc('create_match', params: {
        'other_user_id': otherUserId,
        'match_longitude': longitude,
        'match_latitude': latitude,
        'compatibility': matchResult.compatibilityScore,
        'reasoning': matchResult.reasoning,
      });

      return result as String?;
    } catch (e) {
      // If the error is about duplicate matches, that's expected behavior
      if (e.toString().contains('duplicate') || e.toString().contains('unique')) {
        print('Match already exists, ignoring duplicate: $e');
        return null;
      }
      throw Exception('Failed to save match to database: $e');
    }
  }

  /// Gets all matches for a specific user
  static Future<List<Map<String, dynamic>>> getUserMatches(
    String userId,
  ) async {
    try {
      // Use the RPC function to get matches
      final matchesResponse = await _supabase.rpc('get_my_matches');
      
      print('Raw matches from RPC: $matchesResponse'); // Debug print
      
      if (matchesResponse == null || matchesResponse.isEmpty) {
        return [];
      }

      final matches = List<Map<String, dynamic>>.from(matchesResponse);
      
      // Now fetch user details for each match using the get_user_data RPC function
      final enrichedMatches = <Map<String, dynamic>>[];
      
      for (final match in matches) {
        final user1Id = match['user_id_1'];
        final user2Id = match['user_id_2'];
        
        // Fetch both user profiles using the RPC function
        final user1Response = await _supabase.rpc('get_user_data', params: {
          'p_user_id': user1Id,
        });
        
        final user2Response = await _supabase.rpc('get_user_data', params: {
          'p_user_id': user2Id,
        });
        
        // Extract the first record from the RPC response (SETOF returns an array)
        final user1Data = user1Response != null && user1Response.isNotEmpty 
            ? user1Response[0] 
            : null;
        final user2Data = user2Response != null && user2Response.isNotEmpty 
            ? user2Response[0] 
            : null;
        
        // Create enriched match object
        final enrichedMatch = Map<String, dynamic>.from(match);
        enrichedMatch['user1'] = user1Data;
        enrichedMatch['user2'] = user2Data;
        
        enrichedMatches.add(enrichedMatch);
      }

      print('Enriched matches data: $enrichedMatches'); // Debug print

      return enrichedMatches;
    } catch (e) {
      print('Error in getUserMatches: $e'); // Debug print
      throw Exception('Failed to get user matches: $e');
    }
  }

  /// Checks if two users have already been matched
  static Future<bool> areUsersMatched(String userId1, String userId2) async {
    try {
      // Get all matches for the current user using the RPC function
      final matches = await _supabase.rpc('get_my_matches');
      
      if (matches == null || matches.isEmpty) {
        return false;
      }
      
      // Check if any match involves both users
      final matchList = List<Map<String, dynamic>>.from(matches);
      for (final match in matchList) {
        final user1 = match['user_id_1'] as String;
        final user2 = match['user_id_2'] as String;
        
        if ((user1 == userId1 && user2 == userId2) ||
            (user1 == userId2 && user2 == userId1)) {
          return true;
        }
      }
      
      return false;
    } catch (e) {
      throw Exception('Failed to check if users are matched: $e');
    }
  }

  /// Builds the AI prompt for matching analysis
  static String _buildMatchingPrompt(UserProfile user1, UserProfile user2) {
    // Find actual shared interests
    final sharedInterests = user1.interests
        .where((interest) => user2.interests.contains(interest))
        .toList();
    
    return '''
Analyze the compatibility between these two users for a social networking app. BE GENEROUS with matches - people are here to meet others!

USER 1 (${user1.name}):
- Age: ${user1.age}
- Bio: "${user1.bio}"
- Interests: ${user1.interests.join(', ')}

USER 2 (${user2.name}):
- Age: ${user2.age}
- Bio: "${user2.bio}"
- Interests: ${user2.interests.join(', ')}

SHARED INTERESTS FOUND: ${sharedInterests.isNotEmpty ? sharedInterests.join(', ') : 'None'}

Look for compatibility in these ways:
1. Direct shared interests (exact matches)
2. Related/complementary interests (e.g., "startups" + "business", "music" + "concerts")
3. Similar energy levels or life phases
4. Age compatibility (within reasonable ranges)
5. Personality compatibility from bios

Respond in this exact JSON format:
{
  "isMatch": true/false,
  "compatibilityScore": 0.85,
  "reasoning": "Detailed explanation mentioning specific connections and why they'd connect",
  "commonInterests": ["interest1", "interest2"]
}

MATCHING GUIDELINES - BE INCLUSIVE:
- Score 0.6+ for ANY shared interest or complementary interests
- Score 0.7+ for multiple connections (shared interests, similar ages, compatible bios)
- Score 0.8+ for strong compatibility across multiple areas
- Ages within 10 years are compatible unless very different life stages
- Similar ambitions/energy (e.g., both entrepreneurial) should match even with different specific interests
- People seeking to expand their network should generally match unless completely incompatible
- Reasoning should be 60-150 characters explaining the specific connection
- Include both exact matches AND related interests in commonInterests
''';
  }

  /// Parses the AI response into a MatchResult
  static MatchResult _parseMatchResponse(
    String response,
    UserProfile user1,
    UserProfile user2,
  ) {
    // Extract JSON from response (in case there's extra text)
    final jsonStart = response.indexOf('{');
    final jsonEnd = response.lastIndexOf('}') + 1;

    if (jsonStart == -1 || jsonEnd == 0) {
      throw Exception('No JSON found in response');
    }

    final jsonString = response.substring(jsonStart, jsonEnd);
    final data = json.decode(jsonString) as Map<String, dynamic>;

    return MatchResult(
      isMatch: data['isMatch'] ?? false,
      compatibilityScore: (data['compatibilityScore'] ?? 0.0).toDouble(),
      reasoning: data['reasoning'] ?? 'No reasoning provided',
      commonInterests: List<String>.from(data['commonInterests'] ?? []),
    );
  }
}
