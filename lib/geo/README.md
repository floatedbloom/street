# Geo Location & Proximity Matchmaking

This module provides integrated location services and AI-powered proximity-based matchmaking for the Street app.

## Features

- **Real-time Location Tracking**: Continuous GPS tracking with 5-meter precision
- **Proximity Detection**: Automatically detects users within 50 feet
- **AI-Powered Matching**: Uses Gemini AI to analyze compatibility between nearby users
- **Automatic Match Saving**: Stores successful matches with location data in Supabase
- **Background Processing**: Runs efficiently in the background with minimal battery impact

## Key Components

### `GeoService`
Core location service with integrated matchmaking:
- **`getCurrentPosition()`** - Get one-time location
- **`startBackgroundTracking()`** - Start continuous tracking with matchmaking
- **`stopBackgroundTracking()`** - Stop location tracking
- **`distanceInFeet()`** - Calculate distance between coordinates

### `ProximityMatcher`
High-level interface for proximity-based matchmaking:
- **`startMatchmaking()`** - Start the complete matching system
- **`stopMatchmaking()`** - Stop the matching system
- **`getCurrentMatches()`** - Get user's existing matches
- **`getCurrentLocation()`** - Get current position

## Quick Start

```dart
import 'package:street/geo/proximity_matcher.dart';

// Start proximity-based matchmaking
final success = await ProximityMatcher.startMatchmaking(
  userId: 'your-user-id',
  name: 'John Doe',
  age: 28,
  bio: 'Love hiking, coffee, and meeting new people!',
  interests: ['hiking', 'coffee', 'photography', 'travel'],
  onNearbyUsers: (nearbyUsers) {
    print('Found ${nearbyUsers.length} people within 50 feet!');
  },
  onNewMatches: (matches) {
    print('You have ${matches.length} total matches!');
  },
);

// Stop when done
ProximityMatcher.stopMatchmaking();
```

## How It Works

1. **Location Updates**: GPS tracks your position every 5 meters
2. **Database Query**: Searches for nearby users within ~1000 feet radius
3. **Proximity Filter**: Filters results to users within exactly 50 feet
4. **AI Analysis**: Uses Gemini AI to analyze compatibility based on:
   - Shared interests and hobbies
   - Complementary personality traits
   - Age compatibility
   - Lifestyle alignment
   - Conversation potential
5. **Match Storage**: Saves successful matches with location and AI reasoning

## Database Schema

The system expects these tables in Supabase:

### `people` table:
```sql
- id (uuid, primary key)
- name (text)
- phone (text)
- bio (jsonb) -- Contains age, bio text, interests array
- latitude (double precision, nullable)
- longitude (double precision, nullable)
- last_seen (timestamp with time zone)
```

### `matches` table:
```sql
- id (uuid, primary key)
- user_id_1 (uuid, foreign key)
- user_id_2 (uuid, foreign key)
- compatibility_score (double precision)
- ai_reasoning (text)
- latitude (double precision, nullable)
- longitude (double precision, nullable)
- matched_at (timestamp with time zone, default now())
```

## Privacy & Performance

- **Efficient Queries**: Database pre-filters by coordinate bounds
- **Smart Filtering**: Only processes users active within the last hour
- **No Duplicates**: Prevents creating duplicate matches
- **Minimal Battery**: 5-meter distance filter reduces GPS usage
- **Background Safety**: Handles permission errors gracefully

## Configuration

### Environment Variables (.env):
```
GEMINI_API_KEY=your_gemini_api_key_here
```

### Location Permissions:
- Add location permissions to your platform manifests
- Handle permission requests in your app UI
- Consider "Always" permission for background tracking

## Example Output

```
🚀 Starting proximity-based matchmaking for John Doe...
📡 Starting position stream with 5m distance filter...
✅ Background tracking with matchmaking started successfully!
📍 New position: 40.7128, -74.0060 (±3.2m)
👥 Found 3 nearby users in database
📏 Distance to Sarah Smith: 45.2 feet
🎯 User Sarah Smith is within 50 feet!
💫 Analyzing potential match with Sarah Smith...
🤖 Analyzing match between John Doe and Sarah Smith
🎉 NEW MATCH! John Doe ↔ Sarah Smith
💝 Compatibility: 87.5%
🧠 AI Reasoning: Strong shared interests in hiking and photography, compatible ages
```

## Error Handling

The system gracefully handles:
- Location permission denials
- GPS/network connectivity issues
- API rate limits and failures
- Database connection problems
- Malformed user profile data

## Future Enhancements

- [ ] Configurable proximity radius
- [ ] Multiple matching algorithms
- [ ] Real-time match notifications
- [ ] Location history and analytics
- [ ] Geofencing for specific venues
