import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/alarm.dart';
//import '../../domain/entities/weekday.dart';
import '../../application/providers/alarm_providers.dart';

class AlarmCard extends ConsumerWidget {
  final Alarm alarm;

  const AlarmCard({super.key, required this.alarm});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repeatText = alarm.repeat.isEmpty
        ? '한 번만'
        : alarm.repeatWeekdays.map((w) => w.label).join(', ');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Switch(
          value: alarm.enabled,
          onChanged: (value) async {
            // Provider를 통해 알람 토글 (스케줄러 자동 처리)
            final alarmNotifier = ref.read(alarmNotifierProvider.notifier);
            await alarmNotifier.toggleAlarm(alarm.id, value);
          },
        ),
        title: Text(
          alarm.time,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (alarm.label.isNotEmpty) Text(alarm.label),
            Text(repeatText),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () async {
            // Provider를 통해 알람 삭제 (스케줄러 자동 처리)
            final alarmNotifier = ref.read(alarmNotifierProvider.notifier);
            await alarmNotifier.deleteAlarm(alarm.id);
          },
        ),
        onTap: () {
          Navigator.pushNamed(context, '/edit', arguments: alarm);
        },
      ),
    );
  }
}
