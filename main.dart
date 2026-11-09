import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BiplexApp());
}

const platform = MethodChannel('com.biplob.biplex/alarms');

class RoutineItem {
  String id;
  String title;
  String message;
  int hour;
  int minute;
  bool enabled;

  RoutineItem({
    required this.id,
    required this.title,
    required this.message,
    required this.hour,
    required this.minute,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'hour': hour,
        'minute': minute,
        'enabled': enabled,
      };

  factory RoutineItem.fromJson(Map<String, dynamic> json) {
    return RoutineItem(
      id: json['id'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      enabled: json['enabled'] as bool? ?? true,
    );
  }

  String get time {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m ${hour >= 12 ? 'PM' : 'AM'}';
  }
}

class BiplexApp extends StatelessWidget {
  const BiplexApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BIPLEX Assistant',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF08111F),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD6AD60),
          brightness: Brightness.dark,
        ),
      ),
      home: const Dashboard(),
    );
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  static const gold = Color(0xFFD6AD60);
  static const panel = Color(0xFF111F32);

  List<RoutineItem> routines = [];
  bool loading = true;
  bool voiceActive = false;
  String currentTime = '--:--';
  Timer? clockTimer;

  @override
  void initState() {
    super.initState();
    updateClock();
    clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(updateClock);
    });
    loadData();
  }

  @override
  void dispose() {
    clockTimer?.cancel();
    super.dispose();
  }

  List<RoutineItem> defaultRoutine() {
    // This schedule deliberately protects adequate sleep and breaks.
    final data = [
      ['ঘুম থেকে ওঠা', 'সকাল সাড়ে পাঁচটা। ঘুম থেকে ওঠার সময় হয়েছে।', 5, 30],
      ['হালকা ব্যায়াম ও হাঁটা', 'এখন শরীরচর্চা ও হাঁটার সময়। নিজের সামর্থ্য অনুযায়ী করো।', 6, 0],
      ['গোসল ও প্রস্তুতি', 'এখন গোসল ও দিনের প্রস্তুতি নেওয়ার সময়।', 6, 30],
      ['নাশতা', 'নাশতার সময় হয়েছে। পর্যাপ্ত খাবার খেয়ে নাও।', 7, 0],
      ['Study Session 1 — Bare Act', 'প্রথম পড়ার সেশন শুরু করো। Bare Act-এর ধারা মনোযোগ দিয়ে পড়ো।', 7, 30],
      ['বিরতি', 'এখন ১৫ মিনিট বিরতি নাও। পানি পান করো এবং চোখকে বিশ্রাম দাও।', 9, 30],
      ['Study Session 2 — আইন পাঠ', 'দ্বিতীয় পড়ার সেশন শুরু করো। আইন পাঠ থেকে নির্ধারিত অংশ পড়ো।', 9, 45],
      ['বিরতি', 'এখন ১৫ মিনিট বিশ্রাম নাও।', 11, 45],
      ['Study Session 3 — MCQ', 'এখন MCQ অনুশীলন করো এবং ভুলের কারণ লিখে রাখো।', 12, 0],
      ['দুপুরের খাবার ও বিশ্রাম', 'দুপুরের খাবার খাও এবং বিশ্রাম নাও।', 13, 30],
      ['Study Session 4 — CPC ও CrPC', 'এখন CPC ও CrPC পড়ার সময়। ধারা, Order এবং Rule মিলিয়ে পড়ো।', 14, 15],
      ['বিরতি', 'এখন ১৫ মিনিট বিরতি নাও।', 16, 15],
      ['Study Session 5 — Penal ও Evidence', 'এখন Penal Code এবং Evidence Act পড়ো।', 16, 30],
      ['নাশতা ও হাঁটা', 'এখন নাশতা, অল্প হাঁটা ও বিশ্রামের সময়।', 18, 0],
      ['Study Session 6 — Written', 'এখন Written Answer অনুশীলন করো। নিজের ভাষায় আইনের বিধান ব্যাখ্যা করো।', 18, 45],
      ['রাতের খাবার', 'রাতের খাবার খাও এবং কিছুক্ষণ বিশ্রাম নাও।', 20, 15],
      ['Study Session 7 — Revision', 'এখন সারাদিনের পড়া পুনরাবৃত্তি করো।', 21, 0],
      ['ঘুম', 'এখন ঘুমানোর সময়। আগামী দিনের জন্য পর্যাপ্ত বিশ্রাম নাও।', 22, 0],
    ];

    return List.generate(data.length, (i) {
      return RoutineItem(
        id: 'routine_$i',
        title: data[i][0] as String,
        message: data[i][1] as String,
        hour: data[i][2] as int,
        minute: data[i][3] as int,
      );
    });
  }

  Future<void> loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('routines');

    if (saved == null) {
      routines = defaultRoutine();
      await saveData();
    } else {
      try {
        final list = jsonDecode(saved) as List;
        routines = list
            .map((e) => RoutineItem.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ))
            .toList();
      } catch (_) {
        routines = defaultRoutine();
        await saveData();
      }
    }

    voiceActive = prefs.getBool('voice_active') ?? false;

    if (voiceActive) {
      final ok = await activateVoice(silent: true);
      if (!ok) voiceActive = false;
    }

    if (mounted) setState(() => loading = false);
  }

  void updateClock() {
    final now = TimeOfDay.now();
    final h = now.hourOfPeriod == 0 ? 12 : now.hourOfPeriod;
    final m = now.minute.toString().padLeft(2, '0');
    currentTime = '$h:$m ${now.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  Future<void> saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'routines',
      jsonEncode(routines.map((e) => e.toJson()).toList()),
    );
    await prefs.setBool('voice_active', voiceActive);
  }

  Future<bool> activateVoice({bool silent = false}) async {
    try {
      final result = await platform.invokeMethod<bool>(
        'scheduleAll',
        {
          'json': jsonEncode(
            routines.where((e) => e.enabled).map((e) => e.toJson()).toList(),
          ),
        },
      );

      if (result == true) {
        voiceActive = true;
        await saveData();
        if (!silent && mounted) showMessage('Voice Assistant চালু হয়েছে।');
        if (mounted) setState(() {});
        return true;
      }

      if (!silent && mounted) {
        showMessage('Permission চালু করে আবার Voice Assistant বাটনে চাপো।');
      }
    } on PlatformException catch (e) {
      if (!silent && mounted) showMessage('সমস্যা: ${e.message}');
    } catch (e) {
      if (!silent && mounted) showMessage('অ্যালার্ম চালু করা যায়নি: $e');
    }
    return false;
  }

  Future<void> deactivateVoice() async {
    try {
      await platform.invokeMethod('cancelAll');
      voiceActive = false;
      await saveData();
      if (mounted) {
        setState(() {});
        showMessage('Voice Assistant বন্ধ করা হয়েছে।');
      }
    } catch (e) {
      if (mounted) showMessage('বন্ধ করতে সমস্যা হয়েছে: $e');
    }
  }

  void showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> editRoutine([RoutineItem? item]) async {
    final titleController = TextEditingController(text: item?.title ?? '');
    final messageController =
        TextEditingController(text: item?.message ?? '');
    TimeOfDay selectedTime = item == null
        ? TimeOfDay.now()
        : TimeOfDay(hour: item.hour, minute: item.minute);

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: panel,
              title: Text(item == null ? 'নতুন কাজ যোগ করো' : 'কাজ পরিবর্তন'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(labelText: 'কাজের নাম'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: messageController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Voice Reminder Message',
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setDialogState(() => selectedTime = picked);
                        }
                      },
                      icon: const Icon(Icons.access_time),
                      label: Text(selectedTime.format(context)),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('বাতিল'),
                ),
                FilledButton(
                  onPressed: () {
                    if (titleController.text.trim().isEmpty ||
                        messageController.text.trim().isEmpty) {
                      return;
                    }
                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('সংরক্ষণ'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true) {
      titleController.dispose();
      messageController.dispose();
      return;
    }

    setState(() {
      if (item == null) {
        routines.add(
          RoutineItem(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            title: titleController.text.trim(),
            message: messageController.text.trim(),
            hour: selectedTime.hour,
            minute: selectedTime.minute,
          ),
        );
      } else {
        item.title = titleController.text.trim();
        item.message = messageController.text.trim();
        item.hour = selectedTime.hour;
        item.minute = selectedTime.minute;
      }

      routines.sort((a, b) {
        final x = a.hour * 60 + a.minute;
        final y = b.hour * 60 + b.minute;
        return x.compareTo(y);
      });
    });

    titleController.dispose();
    messageController.dispose();
    await saveData();
    if (voiceActive) await activateVoice(silent: true);
  }

  Future<void> deleteRoutine(RoutineItem item) async {
    setState(() => routines.remove(item));
    await saveData();
    if (voiceActive) await activateVoice(silent: true);
  }

  Future<void> toggleRoutine(RoutineItem item, bool value) async {
    setState(() => item.enabled = value);
    await saveData();
    if (voiceActive) await activateVoice(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BIPLEX ASSISTANT',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.4),
        ),
        centerTitle: true,
        backgroundColor: panel,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: gold,
        foregroundColor: Colors.black,
        onPressed: () => editRoutine(),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF172B45), Color(0xFF263B53)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: gold.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  const Text(
                    'PERSONAL DAILY ASSISTANT',
                    style: TextStyle(
                      color: gold,
                      letterSpacing: 1.8,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    currentTime,
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Your time. Your discipline. Your mission.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: voiceActive
                            ? Colors.red.shade700
                            : gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: () async {
                        if (voiceActive) {
                          await deactivateVoice();
                        } else {
                          await activateVoice();
                        }
                      },
                      icon: Icon(
                        voiceActive ? Icons.volume_off : Icons.volume_up,
                      ),
                      label: Text(
                        voiceActive
                            ? 'TURN VOICE ASSISTANT OFF'
                            : 'ACTIVATE VOICE ASSISTANT',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    voiceActive
                        ? 'Daily voice reminders are active'
                        : 'Voice reminders are currently inactive',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Row(
              children: [
                Icon(Icons.calendar_month, color: gold),
                SizedBox(width: 8),
                Text(
                  'DAILY SCHEDULE',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...routines.map((item) {
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  leading: CircleAvatar(
                    backgroundColor: gold.withValues(alpha: 0.15),
                    child: const Icon(Icons.alarm, color: gold),
                  ),
                  title: Text(
                    item.title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    item.time,
                    style: const TextStyle(color: gold),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: item.enabled,
                        activeColor: gold,
                        onChanged: (value) => toggleRoutine(item, value),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            editRoutine(item);
                          } else if (value == 'delete') {
                            deleteRoutine(item);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
