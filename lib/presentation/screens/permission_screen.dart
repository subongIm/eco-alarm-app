import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../infrastructure/services/alarm_scheduler.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final hasPermission = await Permission.scheduleExactAlarm.isGranted;
    setState(() {
      _hasPermission = hasPermission;
    });
  }

  Future<void> _requestPermission() async {
    final granted = await AlarmScheduler.requestExactAlarmPermission();
    setState(() {
      _hasPermission = granted;
    });

    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('정확한 알람 권한이 필요합니다. 설정에서 권한을 허용해주세요.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('권한 설정'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '정확한 알람 권한',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Android 12 이상에서는 정확한 알람을 위해 권한이 필요합니다.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(
                  _hasPermission ? Icons.check_circle : Icons.cancel,
                  color: _hasPermission ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  _hasPermission ? '권한이 허용되었습니다' : '권한이 필요합니다',
                  style: TextStyle(
                    fontSize: 16,
                    color: _hasPermission ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _hasPermission ? null : _requestPermission,
              child: const Text('권한 요청'),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _openSettings,
              child: const Text('설정 열기'),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              '배터리 최적화 해제',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '알람이 정확하게 울리려면 배터리 최적화를 해제하는 것이 좋습니다.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _openSettings,
              child: const Text('배터리 최적화 설정 열기'),
            ),
          ],
        ),
      ),
    );
  }
}

