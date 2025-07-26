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
        model: 'gemini-pro',
        apiKey: apiKey,
        generationConfig: GenerationConfig(
          temperature: 0.3,
          topK: 1,
          topP: 1,
          maxOutputTokens: 300,
        ),
      );
    }
    return _model!;
  }

  /// Determines if two users should match using Gemini AI
  static Future<MatchResult> shouldMatch(UserProfile user1, UserProfile user2) async {
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

  /// Saves a match to the database
  static Future<void> saveMatch({
    required String userId1,
    required String userId2,
    required MatchResult matchResult,
    double? latitude,
    double? longitude,
  }) async {
    try {
      // Check if match already exists (either direction)
      final existingMatch = await _supabase
          .from('matches')
          .select()
          .or('and(user_id_1.eq.$userId1,user_id_2.eq.$userId2),and(user_id_1.eq.$userId2,user_id_2.eq.$userId1)')
          .maybeSingle();

      if (existingMatch != null) {
        // Match already exists, don't create duplicate
        return;
      }

      // Insert new match
      await _supabase.from('matches').insert({
        'user_id_1': userId1,
        'user_id_2': userId2,
        'compatibility_score': matchResult.compatibilityScore,
        'ai_reasoning': matchResult.reasoning,
        'latitude': latitude,
        'longitude': longitude,
      });
    } catch (e) {
      throw Exception('Failed to save match to database: $e');
    }
  }

  /// Gets all matches for a specific user
  static Future<List<Map<String, dynamic>>> getUserMatches(String userId) async {
    try {
      final matches = await _supabase
          .from('matches')
          .select('''
            *,
            user1:user_id_1(name, bio),
            user2:user_id_2(name, bio)
          ''')
          .or('user_id_1.eq.$userId,user_id_2.eq.$userId')
          .order('matched_at', ascending: false);

      // Fetch phone numbers from auth.users table
      for (var match in matches) {
        try {
          final user1Id = match['user_id_1'];
          final user2Id = match['user_id_2'];
          
          // Try to get phone numbers using a custom SQL function or direct query
          try {
            // Attempt RPC function first (if exists)
            final phoneData = await _supabase.rpc('get_user_phones', params: {
              'user_ids': [user1Id, user2Id]
            });
            
            if (phoneData is List) {
              // Add phone numbers from RPC result
              if (match['user1'] != null) {
                final user1Phone = phoneData.firstWhere(
                  (p) => p['id'] == user1Id, 
                  orElse: () => {'phone': null}
                )['phone'];
                match['user1']['phone'] = user1Phone ?? 'Not available';
              }
              
              if (match['user2'] != null) {
                final user2Phone = phoneData.firstWhere(
                  (p) => p['id'] == user2Id, 
                  orElse: () => {'phone': null}
                )['phone'];
                match['user2']['phone'] = user2Phone ?? 'Not available';
              }
            }
          } catch (rpcError) {
            // Fallback: Try direct auth.users query (may require row level security setup)
            try {
              final authUsers = await _supabase
                  .from('auth.users')
                  .select('id, phone')
                                     .inFilter('id', [user1Id, user2Id]);
              
              if (match['user1'] != null) {
                final user1Data = authUsers.firstWhere(
                  (u) => u['id'] == user1Id,
                  orElse: () => {'phone': null}
                );
                match['user1']['phone'] = user1Data['phone'] ?? 'Not available';
              }
              
              if (match['user2'] != null) {
                final user2Data = authUsers.firstWhere(
                  (u) => u['id'] == user2Id,
                  orElse: () => {'phone': null}
                );
                match['user2']['phone'] = user2Data['phone'] ?? 'Not available';
              }
            } catch (authError) {
              // Final fallback: Use current user's own phone if they're one of the matched users
              final currentUser = _supabase.auth.currentUser;
              if (currentUser != null) {
                if (match['user1'] != null && user1Id == currentUser.id) {
                  match['user1']['phone'] = currentUser.phone ?? 'Not available';
                  // For the other user, we can't get their phone
                  if (match['user2'] != null) {
                    match['user2']['phone'] = 'Contact through app';
                  }
                } else if (match['user2'] != null && user2Id == currentUser.id) {
                  match['user2']['phone'] = currentUser.phone ?? 'Not available';
                  // For the other user, we can't get their phone
                  if (match['user1'] != null) {
                    match['user1']['phone'] = 'Contact through app';
                  }
                } else {
                  // Neither user is current user, can't access phones
                  if (match['user1'] != null) {
                    match['user1']['phone'] = 'Contact through app';
                  }
                  if (match['user2'] != null) {
                    match['user2']['phone'] = 'Contact through app';
                  }
                }
              } else {
                // No current user, set generic message
                if (match['user1'] != null) {
                  match['user1']['phone'] = 'Not available';
                }
                if (match['user2'] != null) {
                  match['user2']['phone'] = 'Not available';
                }
              }
            }
          }
        } catch (e) {
          print('Error fetching phone numbers for match: $e');
          // Set fallback values
          if (match['user1'] != null) {
            match['user1']['phone'] = 'Not available';
          }
          if (match['user2'] != null) {
            match['user2']['phone'] = 'Not available';
          }
        }
      }

      return List<Map<String, dynamic>>.from(matches);
    } catch (e) {
      throw Exception('Failed to get user matches: $e');
    }
  }

  /// Checks if two users have already been matched
  static Future<bool> areUsersMatched(String userId1, String userId2) async {
    try {
      final match = await _supabase
          .from('matches')
          .select()
          .or('and(user_id_1.eq.$userId1,user_id_2.eq.$userId2),and(user_id_1.eq.$userId2,user_id_2.eq.$userId1)')
          .maybeSingle();

      return match != null;
    } catch (e) {
      throw Exception('Failed to check if users are matched: $e');
    }
  }

  /// Builds the AI prompt for matching analysis
  static String _buildMatchingPrompt(UserProfile user1, UserProfile user2) {
    return '''
Analyze the compatibility between these two users for a networking app:

USER 1:
- Name: ${user1.name}
- Age: ${user1.age}
- Bio: "${user1.bio}"
- Interests: ${user1.interests.join(', ')}

USER 2:
- Name: ${user2.name}
- Age: ${user2.age}
- Bio: "${user2.bio}"
- Interests: ${user2.interests.join(', ')}

Please analyze their compatibility based on:
1. Shared interests and hobbies
2. Complementary personality traits from their bios
3. Age compatibility
4. Lifestyle alignment
5. Conversation potential

Respond in this exact JSON format:
{
  "isMatch": true/false,
  "compatibilityScore": 0.85,
  "reasoning": "Brief explanation of why they are/aren't compatible",
  "commonInterests": ["interest1", "interest2"]
}

Keep reasoning under 100 characters. Score should be 0.0-1.0. Only include actual common interests.
''';
  }

  /// Parses the AI response into a MatchResult
  static MatchResult _parseMatchResponse(String response, UserProfile user1, UserProfile user2) {
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