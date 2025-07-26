import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logger/logger.dart';
import '../ai/matchmaker.dart';
import '../geo/geo.dart';

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
    _startLocationTracking();
  }

  @override
  void dispose() {
    _bioController.dispose();
    _interestController.dispose();
    GeoService.stopBackgroundTracking();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    _logger.i('🏠 Starting location tracking from Home page...');
    
    bool started = await GeoService.startBackgroundTracking(
      onNearbyUsers: (nearbyUsers) {
        setState(() {
          _nearbyUsers = nearbyUsers;
        });
        _logger.i('🎯 Home: Found ${nearbyUsers.length} nearby users');
        for (var user in nearbyUsers) {
          _logger.d('👤 User data: $user');
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

      final response = await supabase
          .from('people')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (response == null) {
        // No profile exists, show setup
        _showFirstTimeSetup();
      } else {
        // Profile exists, check if name or age is missing
        final name = response['name'];
        final bioData = response['bio'] as Map<String, dynamic>? ?? {};
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
              _selectedInterests.addAll(List<String>.from(bioData['interests']));
            }
            _isLoading = false;
          });
          
          // Load matches after profile is loaded
          _loadMatches();
        }
      }
    } catch (e) {
      print('Error loading profile: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMatches() async {
    setState(() => _isLoadingMatches = true);
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final matches = await MatchmakerService.getUserMatches(user.id);
      setState(() {
        _matches = matches;
        _isLoadingMatches = false;
      });
    } catch (e) {
      print('Error loading matches: $e');
      setState(() => _isLoadingMatches = false);
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

                  // Check if profile already exists
                  final existingProfile = await supabase
                      .from('people')
                      .select()
                      .eq('id', user.id)
                      .maybeSingle();

                  if (existingProfile == null) {
                    // Insert new profile (phone will be set by auth system)
                    await supabase.from('people').insert({
                      'id': user.id,
                      'name': '$firstName $lastName',
                      'bio': {
                        'age': int.tryParse(age) ?? 0,
                        'bio_text': '',
                        'interests': <String>[],
                      }
                    });
                  } else {
                    // Update existing profile (preserve existing phone)
                    final currentBio = existingProfile['bio'] as Map<String, dynamic>? ?? {};
                    await supabase.from('people').update({
                      'name': '$firstName $lastName',
                      'bio': {
                        ...currentBio,
                        'age': int.tryParse(age) ?? 0,
                      }
                    }).eq('id', user.id);
                  }

                  // Set the data directly instead of reloading from database
                  setState(() {
                    _userName = '$firstName $lastName';
                    _userAge = age;
                    _isLoading = false;
                  });

                  firstNameController.dispose();
                  lastNameController.dispose();
                  ageController.dispose();

                  Navigator.of(context).pop();

                  // Load matches after successful profile setup
                  _loadMatches();
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
    return Chip(
      label: Text(interest),
      deleteIcon: const Icon(Icons.close, size: 18),
      onDeleted: () => _removeInterest(interest),
      backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      side: BorderSide(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Streetly"),
          centerTitle: true,
          automaticallyImplyLeading: false,
        ),
        body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  // Scrollable content area
                  Expanded(
                    child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Text(
                        'Hello, $_userName!',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                                              if (_userAge.isNotEmpty)
                          Text(
                            'Age: $_userAge',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        const SizedBox(height: 32),
                      
                      // Bio field
                      TextField(
                        controller: _bioController,
                        maxLength: 70,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Bio',
                          hintText: 'Tell us about yourself...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // Interests section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Interests',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${_selectedInterests.length}/$_maxInterests',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Interest chips
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedInterests
                            .map((interest) => _buildInterestChip(interest))
                            .toList(),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _interestController,
                              maxLength: 15,
                              decoration: InputDecoration(
                                hintText: 'Add Interest',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                filled: true,
                                fillColor: Theme.of(context).colorScheme.surface,
                                counterText: '',
                              ),
                              onSubmitted: (_) => _addInterest(),
                              textCapitalization: TextCapitalization.words,
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: _selectedInterests.length < _maxInterests ? _addInterest : null,
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Add'),
                          ),
                                                ],
                      ),
                      const SizedBox(height: 32),
                      
                      // Matches section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Your Matches',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_matches.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                '${_matches.length}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Matches list
                      if (_isLoadingMatches)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (_matches.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              'No matches yet.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        Container(
                          height: 200,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListView.builder(
                            itemCount: _matches.length,
                            itemBuilder: (context, index) {
                              final match = _matches[index];
                              final user = supabase.auth.currentUser;
                              
                              // Determine which user profile to show (not the current user)
                              final isUser1 = match['user_id_1'] == user?.id;
                              final otherUser = isUser1 ? match['user2'] : match['user1'];
                              final otherUserName = otherUser?['name'] ?? 'Unknown User';
                              final otherUserPhone = otherUser?['phone'] ?? 'No phone number';
                              
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Theme.of(context).colorScheme.primary,
                                    child: Text(
                                      otherUserName.isNotEmpty ? otherUserName[0].toUpperCase() : '?',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onPrimary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    otherUserName,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        match['ai_reasoning'] ?? 'No reason provided',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.phone,
                                            size: 16,
                                            color: Theme.of(context).colorScheme.secondary,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            otherUserPhone,
                                            style: TextStyle(
                                              color: Theme.of(context).colorScheme.secondary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                ),
                              );
                            },
                          ),
                        ),
                      const SizedBox(height: 32),
                      
                                            Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Center(
                          child: ElevatedButton(
                            onPressed: () async {
                              try {
                                final user = supabase.auth.currentUser;
                                if (user == null) return;

                                await supabase.from('people').update({
                                  'bio': {
                                    'age': int.tryParse(_userAge) ?? 0,
                                    'bio_text': _bioController.text,
                                    'interests': _selectedInterests.toList(),
                                  }
                                }).eq('id', user.id);

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Profile saved!'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                
                                // Reload matches after profile update
                                _loadMatches();
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error saving: $e')),
                                );
                              }
                            },
                          style: ElevatedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Save Profile',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
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
    );
  }
}