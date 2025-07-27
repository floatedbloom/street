import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import '../ai/matchmaker.dart';
import '../geo/geo.dart';
import '../services/notification_service.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> {
  final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 5,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
    ),
  );

  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _interestController = TextEditingController();

  final Set<String> _selectedInterests = <String>{};
  final int _maxInterests = 10;

  String _userName = '';
  String _userAge = '';
  bool _isLoading = true;
  bool _isLoadingMatches = false;
  List<Map<String, dynamic>> _matches = [];
  List<dynamic> _nearbyUsers = [];

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _checkForNewMatches();
  }

  Future<void> _checkForNewMatches() async {
    try {
      await Future.delayed(const Duration(seconds: 2)); // Brief delay to let things initialize
      await NotificationService.checkForNewMatches();
      
      // Start periodic checking for new matches
      NotificationService.startPeriodicMatchChecking();
    } catch (e) {
      _logger.e('Error checking for new matches: $e');
    }
  }

  @override
  void dispose() {
    _bioController.dispose();
    _interestController.dispose();
    GeoService.stopBackgroundTracking();
    NotificationService.stopPeriodicMatchChecking();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    _logger.i('🏠 Starting location tracking from Home page...');
    
    final user = supabase.auth.currentUser;
    if (user == null || _userName.isEmpty) {
      _logger.w('⚠️ Cannot start tracking - user not authenticated or profile incomplete');
      return;
    }
    
    final userProfile = UserProfile(
      name: _userName,
      age: int.tryParse(_userAge) ?? 25,
      bio: _bioController.text,
      interests: _selectedInterests.toList(),
    );
    
    bool started = await GeoService.startBackgroundTracking(
      userId: user.id,
      userProfile: userProfile,
      onNearbyUsers: (nearbyUsers) {
        setState(() {
          _nearbyUsers = nearbyUsers;
        });
        _logger.i('🎯 Home: Found ${nearbyUsers.length} nearby users');
        for (var user in nearbyUsers) {
          _logger.d('👤 User data: $user');
        }
      },
      onNewMatch: () {
        _logger.i('🔄 New match detected! Reloading matches...');
        // Reload matches when a new match is found
        _loadMatches();
        
        // Show a quick snackbar notification
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('🎉 New match found! Check your matches below.'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.green,
            ),
          );
        }
      },
    );

    if (started) {
      _logger.i('✅ Location tracking started successfully from Home');
    } else {
      _logger.e('❌ Failed to start location tracking - check permissions');
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Use the get_user_data RPC function instead of direct table query
      final response = await supabase.rpc('get_user_data', params: {
        'p_user_id': user.id,
      });

      // RPC returns an array, so get the first element
      final userData = response != null && response.isNotEmpty ? response[0] : null;

      if (userData == null) {
        // No profile exists, show setup
        _showFirstTimeSetup();
      } else {
        // Profile exists, check if name or age is missing
        final name = userData['name'];
        final bioData = userData['bio'] as Map<String, dynamic>? ?? {};
        final age = bioData['age'];

        if (name == null || name.toString().trim().isEmpty || age == null) {
          // Essential info missing, show setup
          _showFirstTimeSetup();
        } else {
          // Complete profile, load data
          setState(() {
            _userName = name;
            _userAge = age.toString();
            _bioController.text = bioData['bio_text'] ?? '';
            if (bioData['interests'] != null) {
              _selectedInterests.addAll(
                List<String>.from(bioData['interests']),
              );
            }
            _isLoading = false;
          });

          // Load matches after profile is loaded
          _loadMatches();
          
          // Start location tracking after profile is loaded
          _startLocationTracking();
        }
      }
    } catch (e) {
      _logger.e('Error loading profile: $e');
      
      // Show user-friendly error message for network issues
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('SocketException') ||
          e.toString().contains('NetworkException')) {
        _logger.w('Network connectivity issue detected. Please check your internet connection.');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Network error. Please check your internet connection and try again.'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
      
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMatches() async {
    setState(() {
      _isLoadingMatches = true;
    });

    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final matches = await MatchmakerService.getUserMatches(user.id);
        setState(() {
          _matches = matches;
        });
        print('Loaded ${matches.length} matches'); // Debug print
      }
    } catch (e) {
      print('Error loading matches: $e'); // Debug print
      
      // Show user-friendly error message for network issues
      if (mounted) {
        if (e.toString().contains('Failed host lookup') || 
            e.toString().contains('SocketException') ||
            e.toString().contains('NetworkException')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Network error loading matches. Please check your internet connection.'),
              duration: Duration(seconds: 4),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load matches: $e')),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMatches = false;
        });
      }
    }
  }

  Future<void> _showFirstTimeSetup() async {
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final ageController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Welcome to Streetly!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Please tell us a bit about yourself:'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: firstNameController,
                      decoration: const InputDecoration(
                        labelText: 'First name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: lastNameController,
                      decoration: const InputDecoration(
                        labelText: 'Last name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ageController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Age',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                final firstName = firstNameController.text.trim();
                final lastName = lastNameController.text.trim();
                final age = ageController.text.trim();

                if (firstName.isEmpty || lastName.isEmpty || age.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill in all fields')),
                  );
                  return;
                }

                try {
                  final user = supabase.auth.currentUser;
                  if (user == null) return;

                  // Check if profile already exists using RPC function
                  final existingProfileResponse = await supabase.rpc('get_user_data', params: {
                    'p_user_id': user.id,
                  });
                  
                  final existingProfile = existingProfileResponse != null && existingProfileResponse.isNotEmpty 
                      ? existingProfileResponse[0] 
                      : null;

                  if (existingProfile == null) {
                    // Insert new profile (phone will be set by auth system)
                    await supabase.from('people').insert({
                      'id': user.id,
                      'name': '$firstName $lastName',
                      'bio': {
                        'age': int.tryParse(age) ?? 0,
                        'bio_text': '',
                        'interests': <String>[],
                      },
                    });
                  } else {
                    // Update existing profile (preserve existing phone)
                    final currentBio =
                        existingProfile['bio'] as Map<String, dynamic>? ?? {};
                    await supabase
                        .from('people')
                        .update({
                          'name': '$firstName $lastName',
                          'bio': {...currentBio, 'age': int.tryParse(age) ?? 0},
                        })
                        .eq('id', user.id);
                  }

                  // Set the data directly instead of reloading from database
                  setState(() {
                    _userName = '$firstName $lastName';
                    _userAge = age;
                    _isLoading = false;
                  });

                  Navigator.of(context).pop();

                  // Dispose controllers after dialog is closed
                  firstNameController.dispose();
                  lastNameController.dispose();

                  // Load matches after successful profile setup
                  _loadMatches();
                  
                  // Start location tracking after successful profile setup
                  _startLocationTracking();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error saving profile: $e')),
                  );
                }
              },
              child: const Text('Continue'),
            ),
          ],
        );
      },
    );
  }

  void _addInterest() {
    final interest = _interestController.text.trim();
    if (interest.isNotEmpty &&
        !_selectedInterests.contains(interest) &&
        _selectedInterests.length < _maxInterests) {
      setState(() {
        _selectedInterests.add(interest);
        _interestController.clear();
      });
    }
  }

  void _removeInterest(String interest) {
    setState(() {
      _selectedInterests.remove(interest);
    });
  }

  Widget _buildInterestChip(String interest) {
    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            interest,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _removeInterest(interest),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.close,
                size: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                  Theme.of(context).colorScheme.secondary.withValues(alpha: 0.6),
                ],
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.white, Colors.white70],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ).createShader(bounds),
                  child: const Text(
                    "Streetly",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          centerTitle: true,
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
                ],
              ),
            ),
          ),
        ),
        body: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading your profile...',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            : Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).colorScheme.surface,
                      Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      // Scrollable content area
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                                                  child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Enhanced Header Card
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Theme.of(context).colorScheme.primaryContainer,
                                      Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.1),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Theme.of(context).colorScheme.primary,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(
                                            Icons.waving_hand,
                                            color: Theme.of(context).colorScheme.onPrimary,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Hello, $_userName!',
                                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                                ),
                                              ),
                                              if (_userAge.isNotEmpty)
                                                Text(
                                                  '$_userAge years old',
                                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                    color: Theme.of(context).colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 28),

                                                          // Enhanced Bio Card
                              Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.08),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.edit_outlined,
                                            color: Theme.of(context).colorScheme.primary,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            'About Me',
                                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: Theme.of(context).colorScheme.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                                      child: TextField(
                                        controller: _bioController,
                                        maxLength: 70,
                                        maxLines: 3,
                                        decoration: InputDecoration(
                                          hintText: 'Tell us about yourself...',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                            borderSide: BorderSide(
                                              color: Theme.of(context).colorScheme.primary,
                                              width: 2,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
                                          counterStyle: TextStyle(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 28),

                                                          // Enhanced Interests Card
                              Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.08),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.favorite_outline,
                                                color: Theme.of(context).colorScheme.primary,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                'Interests',
                                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context).colorScheme.onSurface,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Theme.of(context).colorScheme.primary,
                                                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                                                ],
                                              ),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              '${_selectedInterests.length}/$_maxInterests',
                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: Theme.of(context).colorScheme.onPrimary,
                                                fontWeight: FontWeight.w600,
                                                                                            ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // Interest chips
                                      if (_selectedInterests.isNotEmpty)
                                        Wrap(
                                          children: _selectedInterests
                                              .map(
                                                (interest) => _buildInterestChip(interest),
                                              )
                                              .toList(),
                                        ),
                                      if (_selectedInterests.isNotEmpty)
                                        const SizedBox(height: 16),
                                      
                                      // Add interest field
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _interestController,
                                              maxLength: 15,
                                              decoration: InputDecoration(
                                                hintText: 'Add a new interest...',
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                                                  ),
                                                ),
                                                enabledBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
                                                  ),
                                                ),
                                                focusedBorder: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                  borderSide: BorderSide(
                                                    color: Theme.of(context).colorScheme.primary,
                                                    width: 2,
                                                  ),
                                                ),
                                                filled: true,
                                                fillColor: Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
                                                counterText: '',
                                                prefixIcon: Icon(
                                                  Icons.add_circle_outline,
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                              ),
                                              onSubmitted: (_) => _addInterest(),
                                              textCapitalization: TextCapitalization.words,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Theme.of(context).colorScheme.primary,
                                                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                                                ],
                                              ),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: ElevatedButton(
                                              onPressed: _selectedInterests.length < _maxInterests ? _addInterest : null,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.transparent,
                                                shadowColor: Colors.transparent,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                              child: const Text(
                                                'Add',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 28),

                                                          // Enhanced Matches Section
                              Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.08),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Header
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: [
                                                      Colors.pink.withValues(alpha: 0.2),
                                                      Colors.purple.withValues(alpha: 0.2),
                                                    ],
                                                  ),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Icon(
                                                  Icons.check_circle,
                                                  color: Colors.green,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Text(
                                                'Your Matches',
                                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: Theme.of(context).colorScheme.onSurface,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (_matches.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Colors.pink,
                                                    Colors.purple.withValues(alpha: 0.8),
                                                  ],
                                                ),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                '${_matches.length}',
                                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),

                                      // Matches Content
                                      if (_isLoadingMatches)
                                        Center(
                                          child: Container(
                                            padding: const EdgeInsets.all(24),
                                            child: Column(
                                              children: [
                                                CircularProgressIndicator(
                                                  strokeWidth: 3,
                                                  color: Theme.of(context).colorScheme.primary,
                                                ),
                                                const SizedBox(height: 12),
                                                Text(
                                                  'Finding your matches...',
                                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      else if (_matches.isEmpty)
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(24),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                              colors: [
                                                Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
                                                Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.1),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                                            ),
                                          ),
                                          child: Column(
                                            children: [
                                              Icon(
                                                Icons.search_off,
                                                size: 48,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                              ),
                                              const SizedBox(height: 12),
                                              Text(
                                                'No matches yet',
                                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                'Get close to other users to find matches!',
                                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        SizedBox(
                                          height: 320,
                                          child: ListView.builder(
                                            padding: EdgeInsets.zero,
                                            itemCount: _matches.length,
                                            itemBuilder: (context, index) {
                                              final match = _matches[index];
                                              final user = supabase.auth.currentUser;

                                              // Determine which user profile to show (not the current user)
                                              final isUser1 = match['user_id_1'] == user?.id;
                                              final otherUser = isUser1 ? match['user2'] : match['user1'];
                                              
                                              // Safety check - if otherUser is null, skip this match
                                              if (otherUser == null) {
                                                return const SizedBox.shrink();
                                              }
                                              
                                              final otherUserName = otherUser['name'] ?? 'Unknown User';
                                              final otherUserPhone = otherUser['phone'] ?? 'No phone number';
                                              final aiReasoning = match['ai_reasoning'] ?? 'AI analysis not available';
                                              final compatibilityScore = match['compatibility_score'] ?? 0.0;
                                              
                                              // Extract bio if it's a JSONB field
                                              final bioData = otherUser['bio'];
                                              String otherUserBio = 'No bio available';
                                              List<String> otherUserInterests = [];
                                              if (bioData != null && bioData is Map) {
                                                otherUserBio = bioData['bio_text'] ?? 'No bio available';
                                                if (bioData['interests'] != null) {
                                                  otherUserInterests = List<String>.from(bioData['interests']);
                                                }
                                              }

                                              return Container(
                                                margin: const EdgeInsets.only(bottom: 16),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.1),
                                                      Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.1),
                                                    ],
                                                  ),
                                                  borderRadius: BorderRadius.circular(20),
                                                  border: Border.all(
                                                    color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.06),
                                                      blurRadius: 8,
                                                      offset: const Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(20),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      // Header with avatar and name
                                                      Row(
                                                        children: [
                                                          Container(
                                                            width: 60,
                                                            height: 60,
                                                            decoration: BoxDecoration(
                                                              gradient: LinearGradient(
                                                                colors: [
                                                                  Theme.of(context).colorScheme.primary,
                                                                  Theme.of(context).colorScheme.secondary,
                                                                ],
                                                              ),
                                                              borderRadius: BorderRadius.circular(30),
                                                              boxShadow: [
                                                                BoxShadow(
                                                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                                                  blurRadius: 8,
                                                                  offset: const Offset(0, 2),
                                                                ),
                                                              ],
                                                            ),
                                                            child: Center(
                                                              child: Text(
                                                                otherUserName.isNotEmpty ? otherUserName[0].toUpperCase() : '?',
                                                                style: const TextStyle(
                                                                  fontSize: 24,
                                                                  fontWeight: FontWeight.bold,
                                                                  color: Colors.white,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                          const SizedBox(width: 16),
                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment: CrossAxisAlignment.start,
                                                              children: [
                                                                Text(
                                                                  otherUserName,
                                                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                                    fontWeight: FontWeight.bold,
                                                                    color: Theme.of(context).colorScheme.onSurface,
                                                                  ),
                                                                ),
                                                                const SizedBox(height: 4),
                                                                Container(
                                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                                  decoration: BoxDecoration(
                                                                    gradient: LinearGradient(
                                                                      colors: [
                                                                        Colors.green.withValues(alpha: 0.2),
                                                                        Colors.teal.withValues(alpha: 0.2),
                                                                      ],
                                                                    ),
                                                                    borderRadius: BorderRadius.circular(12),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 16),
                                                      
                                                      // AI Reasoning Section
                                                      Container(
                                                        width: double.infinity,
                                                        padding: const EdgeInsets.all(12),
                                                        decoration: BoxDecoration(
                                                          color: Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
                                                          borderRadius: BorderRadius.circular(12),
                                                          border: Border.all(
                                                            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                                                          ),
                                                        ),
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Row(
                                                              children: [
                                                                Icon(
                                                                  Icons.psychology,
                                                                  size: 16,
                                                                  color: Theme.of(context).colorScheme.primary,
                                                                ),
                                                                const SizedBox(width: 6),
                                                                Text(
                                                                  'AI Analysis',
                                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                                    fontWeight: FontWeight.w600,
                                                                    color: Theme.of(context).colorScheme.primary,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                            const SizedBox(height: 6),
                                                            Text(
                                                              aiReasoning,
                                                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                                fontStyle: FontStyle.italic,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      const SizedBox(height: 12),
                                                      
                                                      // Contact Info Section
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child: Container(
                                                              padding: const EdgeInsets.all(12),
                                                              decoration: BoxDecoration(
                                                                color: Theme.of(context).colorScheme.surface,
                                                                borderRadius: BorderRadius.circular(12),
                                                                border: Border.all(
                                                                  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                                                                ),
                                                              ),
                                                              child: Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  Row(
                                                                    children: [
                                                                      Icon(
                                                                        Icons.phone,
                                                                        size: 16,
                                                                        color: Theme.of(context).colorScheme.primary,
                                                                      ),
                                                                      const SizedBox(width: 6),
                                                                      Text(
                                                                        'Contact',
                                                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                                          fontWeight: FontWeight.w600,
                                                                          color: Theme.of(context).colorScheme.primary,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  const SizedBox(height: 4),
                                                                  Text(
                                                                    otherUserPhone,
                                                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                                      color: Theme.of(context).colorScheme.onSurface,
                                                                      fontWeight: FontWeight.w500,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                          if (otherUserPhone != 'No phone number') ...[
                                                            const SizedBox(width: 12),
                                                            Container(
                                                              decoration: BoxDecoration(
                                                                gradient: LinearGradient(
                                                                  colors: [
                                                                    Theme.of(context).colorScheme.primary,
                                                                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                                                                  ],
                                                                ),
                                                                borderRadius: BorderRadius.circular(12),
                                                              ),
                                                              child: Material(
                                                                color: Colors.transparent,
                                                                child: InkWell(
                                                                  onTap: () async {
                                                                    await Clipboard.setData(ClipboardData(text: otherUserPhone));
                                                                    if (context.mounted) {
                                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                                        SnackBar(
                                                                          content: Row(
                                                                            children: [
                                                                              Icon(Icons.check_circle, color: Colors.white, size: 20),
                                                                              const SizedBox(width: 12),
                                                                              Text('Phone number copied!'),
                                                                            ],
                                                                          ),
                                                                          backgroundColor: Colors.green,
                                                                          behavior: SnackBarBehavior.floating,
                                                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                                        ),
                                                                      );
                                                                    }
                                                                  },
                                                                  borderRadius: BorderRadius.circular(12),
                                                                  child: Padding(
                                                                    padding: const EdgeInsets.all(12),
                                                                    child: Icon(
                                                                      Icons.copy,
                                                                      size: 20,
                                                                      color: Colors.white,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 32),

                            Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Center(
                                child: Container(
                                  width: double.infinity,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Theme.of(context).colorScheme.primary,
                                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () async {
                                      try {
                                        final user = supabase.auth.currentUser;
                                        if (user == null) return;

                                        await supabase
                                            .from('people')
                                            .update({
                                              'bio': {
                                                'age': int.tryParse(_userAge) ?? 0,
                                                'bio_text': _bioController.text,
                                                'interests': _selectedInterests.toList(),
                                              },
                                            })
                                            .eq('id', user.id);

                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(
                                                  Icons.check_circle,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 12),
                                                const Text(
                                                  'Profile saved successfully!',
                                                  style: TextStyle(fontWeight: FontWeight.w600),
                                                ),
                                              ],
                                            ),
                                            backgroundColor: Colors.green,
                                            behavior: SnackBarBehavior.floating,
                                            duration: const Duration(seconds: 2),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                        );

                                        // Reload matches after profile update
                                        _loadMatches();
                                      } catch (e) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(
                                                  Icons.error,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    'Error saving: $e',
                                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            backgroundColor: Colors.red,
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.save,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        const Text(
                                          'Save Profile',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                ),
              ),
      ),
    );
  }
}
