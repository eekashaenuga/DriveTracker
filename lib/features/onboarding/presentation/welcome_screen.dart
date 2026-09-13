import 'package:flutter/material.dart';

import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../data_safety/domain/data_safety_service.dart';
import '../../data_safety/presentation/restore_backup_flow.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isRestoring = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(DTSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildIntro(theme),
                      Padding(
                        padding: const EdgeInsets.only(top: DTSpacing.xxxl),
                        child: _buildActions(theme),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildIntro(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.route_rounded, size: 48, color: theme.colorScheme.primary),
        const SizedBox(height: DTSpacing.xl),
        Text(
          'DriveTracker',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: DTSpacing.md),
        Text(
          'Everything about your vehicle,\nin one place.',
          style: theme.textTheme.headlineSmall?.copyWith(
            height: 1.15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: DTSpacing.lg),
        Text(
          'Track mileage, fuel, maintenance and costs without an account or cloud dependency.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildActions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DTPrimaryButton(
          key: const Key('addFirstVehicleButton'),
          label: 'Add your first vehicle',
          icon: Icons.add_rounded,
          onPressed: _isRestoring
              ? null
              : () => AppNavigation.openAddVehicle(context, firstVehicle: true),
        ),
        const SizedBox(height: DTSpacing.md),
        Text(
          'Already use DriveTracker? Restore an existing backup.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: DTSpacing.sm),
        OutlinedButton.icon(
          key: const Key('welcomeRestoreBackupButton'),
          onPressed: _isRestoring ? null : _restoreBackup,
          icon: _isRestoring
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : const Icon(Icons.restore_rounded),
          label: Text(
            _isRestoring ? 'Restoring...' : 'Restore from backup',
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _restoreBackup() async {
    setState(() {
      _isRestoring = true;
    });
    try {
      await runRestoreBackupFlow(context, clearControllerErrorOnFailure: true);
    } on DataSafetyException catch (error) {
      if (mounted) {
        _showSnack(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showSnack('Restore failed. Your existing data was kept.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRestoring = false;
        });
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
