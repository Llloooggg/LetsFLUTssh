import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/security/secure_key_storage.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'toast.dart';

/// Result of the first-launch security setup wizard.
class SecuritySetupResult {
  /// The master password chosen by the user, or null if they skipped.
  final String? masterPassword;

  /// Whether the OS keychain is available.
  final bool keychainAvailable;

  const SecuritySetupResult({
    this.masterPassword,
    required this.keychainAvailable,
  });
}

/// First-launch wizard that probes the OS keychain and offers security options.
///
/// Non-dismissible — the user must pick one of:
/// - Continue with Keychain (when keychain is available)
/// - Set Master Password
/// - Continue without Encryption (when keychain is NOT available)
///
/// Returns [SecuritySetupResult] with the user's choice.
class SecuritySetupDialog extends StatefulWidget {
  final SecureKeyStorage keyStorage;

  const SecuritySetupDialog({super.key, required this.keyStorage});

  /// Show the wizard and return the user's security choice.
  static Future<SecuritySetupResult> show(
    BuildContext context, {
    required SecureKeyStorage keyStorage,
  }) async {
    final result = await showDialog<SecuritySetupResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SecuritySetupDialog(keyStorage: keyStorage),
    );
    // Should never be null — dialog is non-dismissible.
    return result ?? const SecuritySetupResult(keychainAvailable: false);
  }

  @override
  State<SecuritySetupDialog> createState() => _SecuritySetupDialogState();
}

class _SecuritySetupDialogState extends State<SecuritySetupDialog> {
  bool _probing = true;
  bool _keychainAvailable = false;

  // Master password form state.
  bool _showPasswordForm = false;
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _passwordFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _probeKeychain();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _probeKeychain() async {
    final available = await widget.keyStorage.isAvailable();
    if (mounted) {
      setState(() {
        _keychainAvailable = available;
        _probing = false;
      });
    }
  }

  void _continueWithKeychain() {
    Navigator.of(
      context,
    ).pop(const SecuritySetupResult(keychainAvailable: true));
  }

  void _continueWithoutEncryption() {
    Navigator.of(
      context,
    ).pop(const SecuritySetupResult(keychainAvailable: false));
  }

  void _showSetMasterPassword() {
    setState(() => _showPasswordForm = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _passwordFocus.requestFocus();
    });
  }

  void _submitMasterPassword() {
    final l10n = S.of(context);
    final password = _passwordCtrl.text;

    if (password.length < 8) {
      Toast.show(context, message: l10n.passwordTooShort);
      return;
    }
    if (password != _confirmCtrl.text) {
      Toast.show(context, message: l10n.passwordsDoNotMatch);
      return;
    }

    Navigator.of(context).pop(
      SecuritySetupResult(
        masterPassword: password,
        keychainAvailable: _keychainAvailable,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = S.of(context);

    return PopScope(
      canPop: false,
      child: Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _probing
                ? _buildProbing()
                : _showPasswordForm
                ? _buildPasswordForm(l10n)
                : _buildChoice(l10n),
          ),
        ),
      ),
    );
  }

  Widget _buildProbing() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 16),
        CircularProgressIndicator(),
        SizedBox(height: 16),
      ],
    );
  }

  Widget _buildChoice(S l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.shield, size: 48, color: AppTheme.accent),
        const SizedBox(height: 16),
        Text(
          l10n.securitySetupTitle,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppFonts.xl, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        if (_keychainAvailable) ..._buildKeychainFound(l10n),
        if (!_keychainAvailable) ..._buildNoKeychain(l10n),
      ],
    );
  }

  List<Widget> _buildKeychainFound(S l10n) {
    return [
      _infoRow(
        icon: Icons.check_circle,
        color: AppTheme.green,
        text: l10n.securitySetupKeychainFound(_keychainName),
      ),
      const SizedBox(height: 8),
      Text(
        l10n.securitySetupKeychainOptional,
        style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fgDim),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _continueWithKeychain,
        child: Text(l10n.continueWithKeychain),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: _showSetMasterPassword,
        child: Text(l10n.setMasterPassword),
      ),
    ];
  }

  List<Widget> _buildNoKeychain(S l10n) {
    return [
      _infoRow(
        icon: Icons.warning_amber,
        color: AppTheme.yellow,
        text: l10n.securitySetupNoKeychain,
      ),
      const SizedBox(height: 8),
      Text(
        l10n.securitySetupNoKeychainHint,
        style: TextStyle(fontSize: AppFonts.sm, color: AppTheme.fgDim),
      ),
      const SizedBox(height: 8),
      Text(
        l10n.securitySetupRecommendMasterPassword,
        style: TextStyle(fontSize: AppFonts.md, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: _showSetMasterPassword,
        child: Text(l10n.setMasterPassword),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: _continueWithoutEncryption,
        child: Text(l10n.continueWithoutEncryption),
      ),
    ];
  }

  Widget _buildPasswordForm(S l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.lock, size: 48, color: AppTheme.accent),
        const SizedBox(height: 16),
        Text(
          l10n.setMasterPassword,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppFonts.xl, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.masterPasswordWarning,
          style: TextStyle(
            fontSize: AppFonts.sm,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordCtrl,
          focusNode: _passwordFocus,
          obscureText: true,
          onSubmitted: (_) => _submitMasterPassword(),
          style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          decoration: AppTheme.inputDecoration(labelText: l10n.newPassword),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _confirmCtrl,
          obscureText: true,
          onSubmitted: (_) => _submitMasterPassword(),
          style: TextStyle(fontSize: AppFonts.md, color: AppTheme.fg),
          decoration: AppTheme.inputDecoration(labelText: l10n.confirmPassword),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _submitMasterPassword, child: Text(l10n.ok)),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => setState(() => _showPasswordForm = false),
          child: Text(l10n.cancel, style: TextStyle(color: AppTheme.fgDim)),
        ),
      ],
    );
  }

  Widget _infoRow({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: AppFonts.md)),
        ),
      ],
    );
  }

  static String get _keychainName {
    if (Platform.isMacOS || Platform.isIOS) return 'Keychain';
    if (Platform.isWindows) return 'Credential Manager';
    if (Platform.isAndroid) return 'EncryptedSharedPreferences';
    return 'libsecret'; // Linux
  }
}
