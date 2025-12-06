// lib/screens/admin_portal_screen.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../utils/background_utils.dart';

class AdminPortalScreen extends StatefulWidget {
  const AdminPortalScreen({super.key});

  @override
  State<AdminPortalScreen> createState() => _AdminPortalScreenState();
}

class _AdminPortalScreenState extends State<AdminPortalScreen> {
  bool _isAuthenticated = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  // Login controllers
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  // Alert form controllers
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  // Admin credentials (in production, use secure backend auth)
  static const String _adminUsername = 'Mashhood';
  static const String _adminPassword = '22881212';

  // Alert form state
  String _selectedCity = 'Islamabad';
  String _selectedType = 'rain';
  String _selectedSeverity = 'medium';
  double _radius = 40.0;

  // City coordinates
  final Map<String, Map<String, double>> _cityCoordinates = {
    'Islamabad': {'lat': 33.6844, 'lng': 73.0479},
    'Rawalpindi': {'lat': 33.5651, 'lng': 73.0169},
    'Lahore': {'lat': 31.5204, 'lng': 74.3587},
    'Karachi': {'lat': 24.8607, 'lng': 67.0011},
    'Peshawar': {'lat': 34.0151, 'lng': 71.5249},
    'Quetta': {'lat': 30.1798, 'lng': 66.9750},
    'Multan': {'lat': 30.1575, 'lng': 71.5249},
    'Faisalabad': {'lat': 31.4504, 'lng': 73.1350},
    'Sialkot': {'lat': 32.4945, 'lng': 74.5229},
    'Gwadar': {'lat': 25.1264, 'lng': 62.3225},
  };

  final List<String> _alertTypes = [
    'rain',
    'storm',
    'heat',
    'cold',
    'wind',
    'fog',
    'dust',
    'snow',
    'flood',
    'other'
  ];

  final List<String> _severityLevels = ['low', 'medium', 'high', 'extreme'];

  @override
  void initState() {
    super.initState();
    _checkSavedLogin();
  }

  Future<void> _checkSavedLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('admin_logged_in') ?? false;
    if (isLoggedIn) {
      setState(() => _isAuthenticated = true);
    }
  }

  Future<void> _login() async {
    if (_usernameController.text.trim() == _adminUsername &&
        _passwordController.text == _adminPassword) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('admin_logged_in', true);
      setState(() => _isAuthenticated = true);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid credentials'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('admin_logged_in', false);
    setState(() => _isAuthenticated = false);
    _usernameController.clear();
    _passwordController.clear();
  }

  Future<void> _sendAlert() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter alert title'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter alert message'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final coords = _cityCoordinates[_selectedCity]!;

      await FirebaseFirestore.instance.collection('manual_alerts').add({
        'title': _titleController.text.trim(),
        'message': _messageController.text.trim(),
        'type': _selectedType,
        'severity': _selectedSeverity,
        'location': {
          'city': _selectedCity,
          'lat': coords['lat'],
          'lng': coords['lng'],
          'radius': _radius.toInt(),
        },
        'timestamp': FieldValue.serverTimestamp(),
        'sentBy': 'admin_app',
        'status': 'pending',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Alert sent to $_selectedCity!'),
            backgroundColor: Colors.green,
          ),
        );

        // Clear form
        _titleController.clear();
        _messageController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const isDay = true;
    final fg = foregroundForCard(isDay);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.deepPurple.shade700,
              Colors.deepPurple.shade900,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App Bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.admin_panel_settings,
                        color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    const Text(
                      'Admin Portal',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_isAuthenticated)
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white),
                        onPressed: _logout,
                        tooltip: 'Logout',
                      ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: _isAuthenticated
                    ? _buildAlertForm(fg)
                    : _buildLoginForm(fg),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(Color fg) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    color: Colors.white,
                    size: 64,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Admin Login',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter credentials to access admin portal',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Username
                  TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Username',
                      labelStyle:
                          TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.person,
                          color: Colors.white.withValues(alpha: 0.7)),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle:
                          TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                      prefixIcon: Icon(Icons.lock,
                          color: Colors.white.withValues(alpha: 0.7)),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white),
                      ),
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 32),

                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlertForm(Color fg) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Recent Alerts Summary
          _buildRecentAlerts(),
          const SizedBox(height: 20),

          // Alert Form Card
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.send, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          'Send New Alert',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // City Selection
                    _buildLabel('Target City'),
                    const SizedBox(height: 8),
                    _buildDropdown<String>(
                      value: _selectedCity,
                      items: _cityCoordinates.keys.toList(),
                      onChanged: (v) => setState(() => _selectedCity = v!),
                      icon: Icons.location_city,
                    ),
                    const SizedBox(height: 16),

                    // Radius Slider
                    _buildLabel('Radius: ${_radius.toInt()} km'),
                    Slider(
                      value: _radius,
                      min: 5,
                      max: 100,
                      divisions: 19,
                      activeColor: Colors.white,
                      inactiveColor: Colors.white.withValues(alpha: 0.3),
                      onChanged: (v) => setState(() => _radius = v),
                    ),
                    const SizedBox(height: 16),

                    // Alert Type & Severity Row
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Alert Type'),
                              const SizedBox(height: 8),
                              _buildDropdown<String>(
                                value: _selectedType,
                                items: _alertTypes,
                                onChanged: (v) =>
                                    setState(() => _selectedType = v!),
                                icon: Icons.warning_amber,
                                getLabel: _getTypeEmoji,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Severity'),
                              const SizedBox(height: 8),
                              _buildDropdown<String>(
                                value: _selectedSeverity,
                                items: _severityLevels,
                                onChanged: (v) =>
                                    setState(() => _selectedSeverity = v!),
                                icon: Icons.priority_high,
                                getLabel: (s) => s.toUpperCase(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Title
                    _buildLabel('Alert Title'),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _titleController,
                      hint: 'e.g., Heavy Rain Warning',
                    ),
                    const SizedBox(height: 16),

                    // Message
                    _buildLabel('Alert Message'),
                    const SizedBox(height: 8),
                    _buildTextField(
                      controller: _messageController,
                      hint: 'Detailed alert message...',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),

                    // Send Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _sendAlert,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.deepPurple,
                                ),
                              )
                            : const Icon(Icons.send),
                        label: Text(_isLoading ? 'Sending...' : 'Send Alert'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _getSeverityColor(_selectedSeverity),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentAlerts() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.history, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Recent Alerts',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => _showAllAlerts(),
                    icon:
                        const Icon(Icons.list, color: Colors.white70, size: 16),
                    label: const Text('View All',
                        style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('manual_alerts')
                    .orderBy('timestamp', descending: true)
                    .limit(5)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Text(
                      'No recent alerts',
                      style:
                          TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                    );
                  }

                  return Column(
                    children: snapshot.data!.docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final location =
                          data['location'] as Map<String, dynamic>?;
                      return Dismissible(
                        key: Key(doc.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) =>
                            _confirmDelete(doc.id, data['title'] ?? 'Alert'),
                        onDismissed: (direction) => _deleteAlert(doc.id),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              left: BorderSide(
                                color: _getSeverityColor(
                                    data['severity'] ?? 'medium'),
                                width: 3,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      data['title'] ?? 'Alert',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${location?['city'] ?? 'Unknown'} • ${location?['radius'] ?? 0}km',
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.5),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.map,
                                    color: Colors.white.withValues(alpha: 0.7),
                                    size: 20),
                                onPressed: () => _showMapPreview(
                                  location?['city'] ?? 'Unknown',
                                  location?['lat'] ?? 33.6844,
                                  location?['lng'] ?? 73.0479,
                                  (location?['radius'] ?? 40).toDouble(),
                                ),
                                tooltip: 'View on Map',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: Colors.red.withValues(alpha: 0.7),
                                    size: 20),
                                onPressed: () async {
                                  final confirm = await _confirmDelete(
                                      doc.id, data['title'] ?? 'Alert');
                                  if (confirm == true) {
                                    _deleteAlert(doc.id);
                                  }
                                },
                                tooltip: 'Delete',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(String docId, String title) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.deepPurple.shade800,
        title:
            const Text('Delete Alert?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete "$title"?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAlert(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('manual_alerts')
          .doc(docId)
          .delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alert deleted'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showMapPreview(String city, double lat, double lng, double radius) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Colors.deepPurple.shade900,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.map, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          city,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Radius: ${radius.toInt()}km • ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                child: _MapPreviewWidget(
                  lat: lat,
                  lng: lng,
                  radius: radius,
                  city: city,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAllAlerts() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: Colors.deepPurple.shade900,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Colors.white),
                  const SizedBox(width: 12),
                  const Text(
                    'All Sent Alerts',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('manual_alerts')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                        child: CircularProgressIndicator(color: Colors.white));
                  }

                  if (snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text('No alerts sent yet',
                          style: TextStyle(color: Colors.white70)),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      final doc = snapshot.data!.docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final location =
                          data['location'] as Map<String, dynamic>?;
                      final timestamp = data['timestamp'] as Timestamp?;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border(
                            left: BorderSide(
                              color: _getSeverityColor(
                                  data['severity'] ?? 'medium'),
                              width: 4,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getSeverityColor(
                                            data['severity'] ?? 'medium')
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    (data['severity'] ?? 'medium')
                                        .toUpperCase(),
                                    style: TextStyle(
                                      color: _getSeverityColor(
                                          data['severity'] ?? 'medium'),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _getTypeEmoji(data['type'] ?? 'other'),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red, size: 20),
                                  onPressed: () async {
                                    final confirm = await _confirmDelete(
                                        doc.id, data['title'] ?? 'Alert');
                                    if (confirm == true) {
                                      _deleteAlert(doc.id);
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              data['title'] ?? 'Alert',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              data['message'] ?? '',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.location_on,
                                    size: 14,
                                    color: Colors.white.withValues(alpha: 0.5)),
                                const SizedBox(width: 4),
                                Text(
                                  '${location?['city'] ?? 'Unknown'} • ${location?['radius'] ?? 0}km radius',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
                                      fontSize: 12),
                                ),
                                const Spacer(),
                                if (timestamp != null)
                                  Text(
                                    _formatTimestamp(timestamp),
                                    style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.4),
                                        fontSize: 11),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimestamp(Timestamp timestamp) {
    final date = timestamp.toDate();
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.8),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.1),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required Function(T?) onChanged,
    required IconData icon,
    String Function(T)? getLabel,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: Colors.deepPurple.shade800,
          icon: Icon(Icons.arrow_drop_down,
              color: Colors.white.withValues(alpha: 0.7)),
          items: items.map((item) {
            return DropdownMenuItem<T>(
              value: item,
              child: Row(
                children: [
                  Icon(icon,
                      size: 18, color: Colors.white.withValues(alpha: 0.7)),
                  const SizedBox(width: 8),
                  Text(
                    getLabel?.call(item) ?? item.toString(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  String _getTypeEmoji(String type) {
    switch (type) {
      case 'rain':
        return '🌧️ Rain';
      case 'storm':
        return '⛈️ Storm';
      case 'heat':
        return '🌡️ Heat';
      case 'cold':
        return '❄️ Cold';
      case 'wind':
        return '💨 Wind';
      case 'fog':
        return '🌫️ Fog';
      case 'dust':
        return '🌪️ Dust';
      case 'snow':
        return '🌨️ Snow';
      case 'flood':
        return '🌊 Flood';
      default:
        return '⚠️ Other';
    }
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'extreme':
        return Colors.red.shade700;
      case 'high':
        return Colors.orange.shade700;
      case 'medium':
        return Colors.amber.shade700;
      case 'low':
        return Colors.green.shade600;
      default:
        return Colors.amber.shade700;
    }
  }
}

/// Map preview widget using webview with OpenStreetMap/Leaflet
class _MapPreviewWidget extends StatefulWidget {
  final double lat;
  final double lng;
  final double radius;
  final String city;

  const _MapPreviewWidget({
    required this.lat,
    required this.lng,
    required this.radius,
    required this.city,
  });

  @override
  State<_MapPreviewWidget> createState() => _MapPreviewWidgetState();
}

class _MapPreviewWidgetState extends State<_MapPreviewWidget> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
        },
      ))
      ..loadHtmlString(_buildMapHtml());
  }

  String _buildMapHtml() {
    // Calculate zoom level based on radius
    // Approximate: larger radius = lower zoom
    int zoom = 11;
    if (widget.radius <= 10) {
      zoom = 13;
    } else if (widget.radius <= 25) {
      zoom = 12;
    } else if (widget.radius <= 50) {
      zoom = 11;
    } else {
      zoom = 10;
    }

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    * { margin: 0; padding: 0; }
    html, body, #map { width: 100%; height: 100%; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var map = L.map('map').setView([${widget.lat}, ${widget.lng}], $zoom);
    
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap'
    }).addTo(map);
    
    // Add marker
    var marker = L.marker([${widget.lat}, ${widget.lng}]).addTo(map);
    marker.bindPopup('<b>${widget.city}</b><br>Radius: ${widget.radius.toInt()}km').openPopup();
    
    // Add circle for radius
    var circle = L.circle([${widget.lat}, ${widget.lng}], {
      color: '#3b82f6',
      fillColor: '#3b82f680',
      fillOpacity: 0.3,
      radius: ${widget.radius * 1000}
    }).addTo(map);
  </script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          Container(
            color: Colors.deepPurple.shade800,
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Loading map...',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
