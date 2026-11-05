import 'dart:ui';
import 'package:flutter/material.dart';
import 'main.dart'; // Mengakses instance global 'supabase'

class DispenserStatusPage extends StatefulWidget {
  final String dispenserId;

  const DispenserStatusPage({
    super.key,
    this.dispenserId = 'dispensers_01',
  });

  @override
  State<DispenserStatusPage> createState() => _DispenserStatusPageState();
}

class _DispenserStatusPageState extends State<DispenserStatusPage> {
  int? _dispensingSlot; // Menjejaki slot yang sedang melakukan dispense

  // Pembolehubah untuk menyimpan stream supaya tidak di-reset bila page reload
  late final Stream<List<Map<String, dynamic>>> _medicationsStream;
  late final Stream<List<Map<String, dynamic>>> _stokStream;

  @override
  void initState() {
    super.initState();
    final user = supabase.auth.currentUser;

    // Initialize stream SEKALI SAHAJA masa page mula-mula dibuka
    _medicationsStream = supabase
        .from('medications')
        .stream(primaryKey: ['id'])
        .eq('user_id', user?.id ?? '');

    _stokStream = supabase
        .from('stok_kompartmen')
        .stream(primaryKey: ['id']);
  }

  // Pengendali manual dispense ubat menggunakan Supabase
  Future<void> _handleManualDispense({
    required int slotNumber,
    required String medicationName,
    required int currentCount,
  }) async {
    // Halang jika slot kosong atau sedang pusing
    if (currentCount <= 0 || _dispensingSlot != null) return;

    final user = supabase.auth.currentUser;
    if (user == null) {
      _showSnackBar('Sila log masuk semula.', isError: true);
      return;
    }

    setState(() => _dispensingSlot = slotNumber);

    try {
      // 1. Merekod aktiviti ke dalam jadual 'pill_logs' Supabase
      await supabase.from('pill_logs').insert({
        'user_id': user.id,
        'medication_name': medicationName,
        'status': 'DISPENSED (Slot $slotNumber)',
      });

      // 2. Hantar isyarat ke Raspberry Pi (Jadual 'kawalan')
      // NOTA: Kita tak perlu tolak baki stok di sini lagi kerana skrip Python 
      // di Raspberry Pi akan tolak stok secara automatik selepas motor habis berpusing!
      await supabase.from('kawalan').update({
        'trigger_dispense': true,
        'motor_pilihan': slotNumber.toString(),
      }).eq('id', 1);

      if (!mounted) return;

      _showSnackBar('Mengarahkan Smart Pill mengeluarkan $medicationName dari Slot $slotNumber...');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Gagal menghantar arahan: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _dispensingSlot = null);
      }
    }
  }

  void _showSnackBar(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF00B4D8),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Dispenser Cartridge Status',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
        ),
        backgroundColor: Colors.black.withValues(alpha: 0.3),
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF0284C7)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: SafeArea(
          // STREAM 1: Menggunakan pembolehubah stream yang telah di-init
          child: StreamBuilder<List<dynamic>>(
            stream: _medicationsStream,
            builder: (context, medSnapshot) {
              
              // STREAM 2: Menggunakan pembolehubah stream stok yang telah di-init
              return StreamBuilder<List<dynamic>>(
                stream: _stokStream,
                builder: (context, stokSnapshot) {
                  
                  if (medSnapshot.hasError || stokSnapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Ralat brader 😢. refresh page balik ler.',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    );
                  }

                  if (medSnapshot.connectionState == ConnectionState.waiting && 
                      stokSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF00B4D8)),
                    );
                  }

                  final medications = medSnapshot.data ?? [];
                  final stokData = stokSnapshot.data ?? [];

                  // Petakan nama ubat mengikut slot (1 hingga 4)
                  final Map<int, String> slotNames = {1: '', 2: '', 3: '', 4: ''};
                  for (var med in medications) {
                    final slotNum = med['slot_number'] as int?;
                    if (slotNum != null && slotNum >= 1 && slotNum <= 4) {
                      slotNames[slotNum] = med['medication_name']?.toString() ?? '';
                    }
                  }

                  // Petakan jumlah baki stok (live dari sensor Pi) mengikut slot (1 hingga 4)
                  final Map<int, int> slotStocks = {1: 0, 2: 0, 3: 0, 4: 0};
                  for (var stok in stokData) {
                    final id = stok['id'] as int?;
                    if (id != null && id >= 1 && id <= 4) {
                      slotStocks[id] = stok['jumlah_baki'] as int? ?? 0;
                    }
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildOverviewHeader(),
                        const SizedBox(height: 20),
                        const Text(
                          'Physical Cartridge Slots (Max 6 Bekas)',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF00B4D8),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...List.generate(4, (index) {
                          final slotNumber = index + 1;
                          final medicationName = slotNames[slotNumber]!.isEmpty 
                              ? 'Empty' 
                              : slotNames[slotNumber]!;
                          final currentStock = slotStocks[slotNumber]!;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: _buildSlotCard(
                              context,
                              slotNumber: slotNumber,
                              medicationName: medicationName,
                              stockCount: currentStock,
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewHeader() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF00B4D8).withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00B4D8).withValues(alpha: 0.2),
                  border: Border.all(color: const Color(0xFF00B4D8)),
                ),
                child: const Icon(
                  Icons.precision_manufacturing_rounded,
                  color: Color(0xFF00B4D8),
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unit Status: Online',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Sensors detecting real-time stock via Supabase',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white54,
                      ),
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

  Widget _buildSlotCard(
    BuildContext context, {
    required int slotNumber,
    required String medicationName,
    required int stockCount,
  }) {
    final bool isEmpty = stockCount <= 0;
    final bool isFull = stockCount >= 6;
    final bool isLow = stockCount > 0 && stockCount <= 2;
    final bool isDispensing = _dispensingSlot == slotNumber;

    Color statusColor = const Color(0xFF00B4D8);
    String statusText = 'Normal';

    if (isEmpty) {
      statusColor = Colors.redAccent;
      statusText = 'KOSONG (Sila isi bekas)';
    } else if (isFull) {
      statusColor = Colors.greenAccent;
      statusText = 'PENUH (Maksimum)';
    } else if (isLow) {
      statusColor = Colors.orangeAccent;
      statusText = 'Hampir Habis';
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: statusColor.withValues(alpha: 0.4),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(color: statusColor),
                    ),
                    child: Center(
                      child: Text(
                        'S$slotNumber',
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
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
                          medicationName == 'Empty' ? 'Slot $slotNumber (Unassigned)' : medicationName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            decoration: medicationName == 'Empty' ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start, 
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 4), 
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded( 
                              child: Text(
                                '$statusText\n$stockCount/6 bekas dalam unit',
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                softWrap: true, 
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (isEmpty || isDispensing)
                      ? null
                      : () => _handleManualDispense(
                            slotNumber: slotNumber,
                            medicationName: medicationName,
                            currentCount: stockCount,
                          ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: statusColor.withValues(alpha: 0.25),
                    foregroundColor: Colors.white,
                    side: BorderSide(color: statusColor.withValues(alpha: 0.6)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: isDispensing
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: statusColor,
                          ),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    isDispensing ? 'Motor Berpusing...' : 'DISPENSE SLOT $slotNumber NOW',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
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