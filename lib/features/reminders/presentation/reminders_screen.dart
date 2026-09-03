import 'package:flutter/material.dart';

import '../../../shared/widgets/dt_empty_state.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: DTEmptyState(
          icon: Icons.notifications_none_rounded,
          title: 'Reminders are planned',
          body: 'Maintenance and date-based reminders will live here in a later milestone.',
        ),
      ),
    );
  }
}
