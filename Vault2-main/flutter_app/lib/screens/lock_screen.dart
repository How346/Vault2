import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/security_service.dart';
import '../state/settings_controller.dart';
import '../widgets/brand.dart';

/// Gate shown before anything else: PIN setup, PIN entry, biometric unlock.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});

  /// Called once the user is authenticated. The root gate swaps the widget
  /// in place instead of pushing a route, so Home stays the root route.
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _security = SecurityService.instance;

  String _entry = '';
  String _firstPin = '';
  bool _loading = true;
  bool _needsSetup = false;
  bool _confirming = false;
  bool _biometricAvailable = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final hasPin = await _security.hasPin();
    final bio = await _security.biometricAvailable();
    if (!mounted) return;
    setState(() {
      _needsSetup = !hasPin;
      _biometricAvailable = bio;
      _loading = false;
    });
    if (hasPin && bio && context.read<SettingsController>().biometricEnabled) {
      _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    final ok = await _security.authenticateBiometric();
    if (ok && mounted) _enter();
  }

  void _enter() {
    if (!mounted) return;
    widget.onUnlocked();
  }

  Future<void> _skipSetup() async {
    await context.read<SettingsController>().setAppLockEnabled(false);
    _enter();
  }

  Future<void> _onDigit(String d) async {
    if (_entry.length >= 4) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entry += d;
      _error = null;
    });
    if (_entry.length == 4) await _submit();
  }

  Future<void> _submit() async {
    final pin = _entry;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;

    if (_needsSetup) {
      if (!_confirming) {
        setState(() {
          _firstPin = pin;
          _confirming = true;
          _entry = '';
        });
        return;
      }
      if (pin != _firstPin) {
        _fail('PINs did not match. Start again.');
        setState(() {
          _confirming = false;
          _firstPin = '';
        });
        return;
      }
      await context.read<SettingsController>().setPin(pin);
      if (mounted) _enter();
      return;
    }

    if (await _security.verifyPin(pin)) {
      if (mounted) _enter();
    } else {
      _fail('Incorrect PIN');
    }
  }

  void _fail(String message) {
    HapticFeedback.heavyImpact();
    setState(() {
      _entry = '';
      _error = message;
    });
  }

  String get _title {
    if (_needsSetup) return _confirming ? 'Confirm your PIN' : 'Create a 4-digit PIN';
    return 'Enter your PIN';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),
              const AppLogo(size: 104),
              const SizedBox(height: 22),
              const AppWordmark(),
              const SizedBox(height: 6),
              Text(
                'Everything stays on this device',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(_title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 18),
              _Dots(filled: _entry.length, error: _error != null),
              const SizedBox(height: 12),
              SizedBox(
                height: 20,
                child: Text(
                  _error ?? '',
                  style: TextStyle(color: scheme.error, fontSize: 13),
                ),
              ),
              const Spacer(),
              _Keypad(
                onDigit: _onDigit,
                onBackspace: () => setState(() {
                  if (_entry.isNotEmpty) {
                    _entry = _entry.substring(0, _entry.length - 1);
                  }
                }),
                onBiometric: (!_needsSetup &&
                        _biometricAvailable &&
                        context.watch<SettingsController>().biometricEnabled)
                    ? _tryBiometric
                    : null,
              ),
              SizedBox(
                height: 44,
                child: _needsSetup
                    ? TextButton(
                        onPressed: _skipSetup,
                        child: const Text('Skip — don\'t lock this app'),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.filled, required this.error});
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final active = i < filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 9),
          height: active ? 18 : 14,
          width: active ? 18 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: error
                ? scheme.error
                : active
                    ? scheme.primary
                    : scheme.surfaceContainerHighest,
          ),
        );
      }),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    final keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', 'bio', '0', 'del'];
    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 3,
      childAspectRatio: 1.7,
      physics: const NeverScrollableScrollPhysics(),
      children: keys.map((k) {
        if (k == 'bio') {
          return onBiometric == null
              ? const SizedBox.shrink()
              : IconButton(
                  onPressed: onBiometric,
                  icon: const Icon(Icons.fingerprint, size: 30),
                );
        }
        if (k == 'del') {
          return IconButton(
            onPressed: onBackspace,
            icon: const Icon(Icons.backspace_outlined, size: 24),
          );
        }
        return InkWell(
          borderRadius: BorderRadius.circular(50),
          onTap: () => onDigit(k),
          child: Center(
            child: Text(k,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w500)),
          ),
        );
      }).toList(),
    );
  }
}
