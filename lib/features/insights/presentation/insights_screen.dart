import 'package:flutter/material.dart';

import '../../../shared/widgets/dt_empty_state.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: DTEmptyState(
          icon: Icons.insights_rounded,
          title: 'Insights will grow here',
          body: 'Fuel, maintenance and expense insights will appear after those records exist.',
        ),
      ),
    );
  }
}
