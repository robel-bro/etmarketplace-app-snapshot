import 'package:flutter/material.dart';
import '../models/user.dart';
import '../theme/app_theme.dart';

class AccountDetailsScreen extends StatelessWidget {
  final User? user;
  const AccountDetailsScreen({Key? key, this.user}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Account Details'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        children: [
          _infoRow('Name', user?.displayName ?? 'Not set'),
          _infoRow('Email', user?.email ?? 'Not set'),
          _infoRow('Phone', user?.phone ?? 'Not set'),
          _infoRow(
            'Roles',
            (user?.roles.isNotEmpty == true)
                ? user!.roles.join(', ')
                : 'Customer',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm), // tight, seamless spacing
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}