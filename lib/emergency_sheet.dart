import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _accent = Color(0xFF00B4D8);
const Color _danger = Color(0xFFEF4444);

class _Msg implements Exception {
  final String text;
  const _Msg(this.text);
}

class _Hospital {
  final String name;
  final double lat;
  final double lon;
  final double distanceM;
  final String? phone;

  const _Hospital({
    required this.name,
    required this.lat,
    required this.lon,
    required this.distanceM,
    this.phone,
  });

  String get distanceText => distanceM < 1000
      ? '${distanceM.round()} m'
      : '${(distanceM / 1000).toStringAsFixed(1)} km';
}

/// Skrin kecemasan: dail 999, alert penjaga, hospital berdekatan, kongsi lokasi.
class EmergencySheet extends StatefulWidget {
  final String emergencyContact;
  final String attendingDoctor;
  final String medicalConditions;

  const EmergencySheet({
    super.key,
    this.emergencyContact = '',
    this.attendingDoctor = '',
    this.medicalConditions = '',
  });

  @override
  State<EmergencySheet> createState() => _EmergencySheetState();
}

class _EmergencySheetState extends State<EmergencySheet> {
  Position? _pos;
  List<_Hospital> _hospitals = [];
  bool _loading = true;
  String? _error;

  bool _alerting = false;
  bool _alertSent = false;

  @override
  void initState() {
    super.initState();
    _findHospitals();
  }

  // ---------------- Lokasi + carian hospital ----------------

  Future<void> _findHospitals() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        throw const _Msg('Location services are turned off. Turn on GPS and try again.');
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        throw const _Msg(
            'Location permission denied. Allow location access in your browser or phone settings.');
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      setState(() => _pos = pos);

      final hospitals = await _fetchHospitals(pos.latitude, pos.longitude);
      if (!mounted) return;
      setState(() => _hospitals = hospitals);
    } on _Msg catch (e) {
      if (mounted) setState(() => _error = e.text);
    } catch (e) {
      debugPrint('Emergency lookup failed: $e');
      if (mounted) {
        setState(() => _error = 'Could not find your location or nearby hospitals.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// OpenStreetMap (Overpass API): percuma, tiada kunci API.
  Future<List<_Hospital>> _fetchHospitals(double lat, double lon) async {
    final query = '[out:json][timeout:20];('
        'node["amenity"="hospital"](around:25000,$lat,$lon);'
        'way["amenity"="hospital"](around:25000,$lat,$lon);'
        'relation["amenity"="hospital"](around:25000,$lat,$lon);'
        ');out center tags;';

    final res = await http
        .post(
          Uri.parse('https://overpass-api.de/api/interpreter'),
          body: {'data': query},
        )
        .timeout(const Duration(seconds: 25));

    if (res.statusCode != 200) {
      throw const _Msg('Hospital search is unavailable right now. Try again.');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final elements = (data['elements'] as List?) ?? const [];

    final result = <_Hospital>[];
    for (final raw in elements) {
      final e = raw as Map<String, dynamic>;
      final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
      final name = (tags['name'] ?? tags['name:en'])?.toString().trim();
      if (name == null || name.isEmpty) continue;

      final center = e['center'] as Map?;
      final hLat = (e['lat'] ?? center?['lat']) as num?;
      final hLon = (e['lon'] ?? center?['lon']) as num?;
      if (hLat == null || hLon == null) continue;

      String? phone = (tags['phone'] ?? tags['contact:phone'])?.toString();
      if (phone != null) {
        phone = phone.split(';').first.trim();
        if (phone.replaceAll(RegExp(r'[^0-9]'), '').isEmpty) phone = null;
      }

      result.add(_Hospital(
        name: name,
        lat: hLat.toDouble(),
        lon: hLon.toDouble(),
        distanceM:
            Geolocator.distanceBetween(lat, lon, hLat.toDouble(), hLon.toDouble()),
        phone: phone,
      ));
    }

    result.sort((a, b) => a.distanceM.compareTo(b.distanceM));
    return result.take(8).toList();
  }

  // ---------------- Tindakan ----------------

  void _snack(String text, {Color color = _accent}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _open(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack('Could not open this on your device.');
    } catch (_) {
      _snack('Could not open this on your device.');
    }
  }

  Future<void> _call(String number) {
    final cleaned = number.replaceAll(RegExp(r'[^0-9+]'), '');
    return _open(Uri(scheme: 'tel', path: cleaned));
  }

  Future<void> _directions(_Hospital h) => _open(Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${h.lat},${h.lon}'));

  Future<void> _openMapsSearch() {
    final p = _pos;
    final url = p == null
        ? 'https://www.google.com/maps/search/?api=1&query=hospital+near+me'
        : 'https://www.google.com/maps/search/hospital/@${p.latitude},${p.longitude},14z';
    return _open(Uri.parse(url));
  }

  Future<void> _copyLocation() async {
    final p = _pos;
    if (p == null) {
      _snack('Location not available yet.');
      return;
    }
    await Clipboard.setData(ClipboardData(
        text: 'https://maps.google.com/?q=${p.latitude},${p.longitude}'));
    _snack('Location link copied. Send it to family or paramedics.');
  }

  /// Hantar alert + lokasi kepada semua penjaga yang dipaut
  /// melalui Edge Function 'emergency-alert'.
  Future<void> _alertCaregivers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Alert caregivers?',
            style: TextStyle(color: Colors.white)),
        content: Text(
          _pos == null
              ? 'Your caregivers will get an emergency notification. Your location is not available yet, so it will be sent without a location.'
              : 'Your caregivers will get an emergency notification with your current location.',
          style: const TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SEND ALERT'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _alerting = true);
    try {
      final p = _pos;
      final res = await Supabase.instance.client.functions.invoke(
        'emergency-alert',
        body: {
          'lat': p?.latitude,
          'lng': p?.longitude,
          'accuracy': p?.accuracy,
        },
      );

      final data = res.data;
      final caregivers = data is Map ? (data['caregivers'] as num?)?.toInt() ?? 0 : 0;
      final delivered = data is Map ? (data['delivered'] as num?)?.toInt() ?? 0 : 0;

      if (caregivers == 0) {
        _snack(
          'No caregiver is linked to your account. Call 999 or your emergency contact.',
          color: Colors.orangeAccent,
        );
      } else if (delivered == 0) {
        _snack(
          'Alert saved, but no caregiver device could be reached. Call them directly.',
          color: Colors.orangeAccent,
        );
      } else {
        if (mounted) setState(() => _alertSent = true);
        _snack('Alert sent to $delivered caregiver device(s).',
            color: Colors.green);
      }
    } catch (e) {
      debugPrint('Emergency alert failed: $e');
      _snack(
        'Could not send the alert. Call 999 or your caregiver directly.',
        color: Colors.redAccent,
      );
    } finally {
      if (mounted) setState(() => _alerting = false);
    }
  }

  // ---------------- UI ----------------

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 10),
        child: Text(
          text,
          style: const TextStyle(
            color: _accent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _card({required Widget child}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: child,
      );

  Widget _hospitalTile(_Hospital h) {
    return _card(
      child: Row(
        children: [
          const CircleAvatar(
            radius: 18,
            backgroundColor: Color(0x33EF4444),
            child: Icon(Icons.local_hospital_rounded, color: _danger, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  h.phone != null
                      ? '${h.distanceText}  •  ${h.phone}'
                      : '${h.distanceText}  •  No phone listed',
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          if (h.phone != null)
            IconButton(
              tooltip: 'Call',
              icon: const Icon(Icons.call_rounded, color: Colors.greenAccent),
              onPressed: () => _call(h.phone!),
            ),
          IconButton(
            tooltip: 'Directions',
            icon: const Icon(Icons.directions_rounded, color: _accent),
            onPressed: () => _directions(h),
          ),
        ],
      ),
    );
  }

  Widget _hospitalSection() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }
    if (_error != null) {
      return _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _findHospitals,
                  icon: const Icon(Icons.refresh_rounded, color: _accent),
                  label: const Text('Try again', style: TextStyle(color: _accent)),
                ),
                TextButton.icon(
                  onPressed: _openMapsSearch,
                  icon: const Icon(Icons.map_outlined, color: _accent),
                  label: const Text('Search in Maps',
                      style: TextStyle(color: _accent)),
                ),
              ],
            ),
          ],
        ),
      );
    }
    if (_hospitals.isEmpty) {
      return _card(
        child: const Text(
          'No hospitals found within 25 km. Use "Hospitals on Maps" above.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return Column(children: _hospitals.map(_hospitalTile).toList());
  }

  Widget _myContacts() {
    final contact = widget.emergencyContact.trim();
    final doctor = widget.attendingDoctor.trim();
    final conditions = widget.medicalConditions.trim();

    final hasContact = contact.isNotEmpty && contact != 'Not set';
    final hasDoctor = doctor.isNotEmpty && doctor != 'Not set';
    final hasConditions = conditions.isNotEmpty && conditions != 'Not set';

    if (!hasContact && !hasDoctor && !hasConditions) {
      return _card(
        child: const Text(
          'No emergency contact saved yet. Add one in Profile > Edit Profile Details.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasContact)
            Row(
              children: [
                Expanded(
                  child: Text('Emergency contact: $contact',
                      style: const TextStyle(color: Colors.white)),
                ),
                IconButton(
                  tooltip: 'Call',
                  icon: const Icon(Icons.call_rounded, color: Colors.greenAccent),
                  onPressed: () => _call(contact),
                ),
              ],
            ),
          if (hasDoctor)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Doctor: $doctor',
                  style: const TextStyle(color: Colors.white70)),
            ),
          if (hasConditions)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Conditions: $conditions',
                  style: const TextStyle(color: Colors.white70)),
            ),
        ],
      ),
    );
  }

  Widget _alertButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: (_alerting || _alertSent) ? null : _alertCaregivers,
        style: OutlinedButton.styleFrom(
          foregroundColor: _alertSent ? Colors.greenAccent : Colors.orangeAccent,
          disabledForegroundColor:
              _alertSent ? Colors.greenAccent : Colors.white38,
          side: BorderSide(
            color: _alertSent ? Colors.greenAccent : Colors.orangeAccent,
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: _alerting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.orangeAccent),
              )
            : Icon(_alertSent
                ? Icons.check_circle_rounded
                : Icons.notifications_active_rounded),
        label: Text(
          _alerting
              ? 'Sending alert...'
              : _alertSent
                  ? 'ALERT SENT TO CAREGIVERS'
                  : 'ALERT MY CAREGIVERS',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.88,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: _danger.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.emergency_rounded, color: _danger, size: 24),
                      SizedBox(width: 10),
                      Text(
                        'Emergency',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 20),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    SizedBox(
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: () => _call('999'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _danger,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.call_rounded),
                        label: const Text(
                          'CALL 999 (Ambulance / Police)',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'In Malaysia, 999 and 112 both reach emergency services.',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    const SizedBox(height: 12),
                    _alertButton(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _copyLocation,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _accent,
                              side: const BorderSide(color: _accent),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.my_location_rounded, size: 18),
                            label: const Text('Copy my location',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openMapsSearch,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _accent,
                              side: const BorderSide(color: _accent),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.map_outlined, size: 18),
                            label: const Text('Hospitals on Maps',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                    _sectionTitle('NEARBY HOSPITALS'),
                    _hospitalSection(),
                    _sectionTitle('MY EMERGENCY INFO'),
                    _myContacts(),
                    const SizedBox(height: 4),
                    const Text(
                      'Hospital data comes from OpenStreetMap and may be incomplete. Phone numbers are shown only when listed.',
                      style: TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}