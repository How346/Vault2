import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/transfer_service.dart';
import '../state/wallet_controller.dart';
import '../widgets/brand.dart';

/// Entry point: choose to send or receive data, fully offline.
class TransferScreen extends StatelessWidget {
  const TransferScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Move to a new phone')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppLogo(size: 74),
                const SizedBox(height: 16),
                const Text(
                  'Offline device transfer',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Both phones need to be on the same Wi-Fi or hotspot. '
                  'Nothing ever leaves your local network.',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ActionCard(
            icon: Icons.upload_rounded,
            title: 'Send data',
            subtitle: 'This is my old phone',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SendTransferScreen(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.download_rounded,
            title: 'Receive data',
            subtitle: 'This is my new phone',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ReceiveTransferScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------- send

class SendTransferScreen extends StatefulWidget {
  const SendTransferScreen({super.key});

  @override
  State<SendTransferScreen> createState() => _SendTransferScreenState();
}

class _SendTransferScreenState extends State<SendTransferScreen> {
  late final String _code =
      (Random.secure().nextInt(900000) + 100000).toString();

  String? _ip;
  String? _error;
  double _progress = 0;
  bool _done = false;
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final ip = await TransferService.instance.startServer(
        code: _code,
        onProgress: (p) {
          if (mounted) {
            setState(() => _progress = p);
          }
        },
        onCompleted: () {
          if (mounted) {
            setState(() => _done = true);
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _ip = ip;
        _starting = false;
      });
    } on TransferException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _starting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Connection failed. Try again.';
          _starting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    TransferService.instance.stopServer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final docs = context.read<WalletController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Send data')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_error != null)
            _ErrorPanel(
              message: _error!,
              onRetry: () {
                setState(() {
                  _error = null;
                  _starting = true;
                  _done = false;
                  _progress = 0;
                });
                _start();
              },
            )
          else if (_starting)
            const _GlassPanel(
              child: Row(
                children: [
                  SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                    ),
                  ),
                  SizedBox(width: 14),
                  Text('Preparing your data…'),
                ],
              ),
            )
          else ...[
            _GlassPanel(
              child: Column(
                children: [
                  Text(
                    'Enter this code on the new phone',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _CodeDisplay(code: _code),
                  const SizedBox(height: 16),
                  if (!_done)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _progress > 0
                              ? 'Sending… ${(_progress * 100).round()}%'
                              : 'Waiting for connection…',
                        ),
                      ],
                    )
                  else
                    const _SuccessBadge(
                      label: 'Data sent successfully',
                    ),
                  const SizedBox(height: 14),
                  _Progress(value: _progress),
                  const SizedBox(height: 12),
                  Text(
                    'This phone: ${_ip ?? '-'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _GlassPanel(
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '${docs.profiles.length} profiles · '
                      '${docs.allDocuments.length} documents in this profile '
                      'will be packed with all files and settings.',
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- receive

class ReceiveTransferScreen extends StatefulWidget {
  const ReceiveTransferScreen({super.key});

  @override
  State<ReceiveTransferScreen> createState() =>
      _ReceiveTransferScreenState();
}

enum _RxStage {
  idle,
  searching,
  downloading,
  restoring,
  done,
}

class _ReceiveTransferScreenState extends State<ReceiveTransferScreen> {
  final _codeCtrl = TextEditingController();

  _RxStage _stage = _RxStage.idle;
  double _progress = 0;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final code = _codeCtrl.text.trim();

    if (code.length != 6 || int.tryParse(code) == null) {
      setState(() {
        _error = 'Enter the 6-digit code shown on the old phone.';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _error = null;
      _progress = 0;
      _stage = _RxStage.searching;
    });

    try {
      final host = await TransferService.instance.discover(
        code,
        onProgress: (p) {
          if (mounted) {
            setState(() => _progress = p);
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _stage = _RxStage.downloading;
        _progress = 0;
      });

      final bytes = await TransferService.instance.download(
        host,
        code,
        onProgress: (p) {
          if (mounted) {
            setState(() => _progress = p);
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _stage = _RxStage.restoring;
        _progress = 1;
      });

      await TransferService.instance.restorePayload(bytes);

      if (!mounted) return;

      context.read<WalletController>().refresh();

      setState(() {
        _stage = _RxStage.done;
      });
    } on TransferException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _stage = _RxStage.idle;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Transfer interrupted. Try again.';
          _stage = _RxStage.idle;
        });
      }
    }
  }

  String get _statusLabel => switch (_stage) {
        _RxStage.searching =>
          'Looking for the old phone… ${(_progress * 100).round()}%',
        _RxStage.downloading =>
          'Receiving data… ${(_progress * 100).round()}%',
        _RxStage.restoring => 'Restoring your wallet…',
        _RxStage.done => 'Transfer complete',
        _RxStage.idle => '',
      };

  @override
  Widget build(BuildContext context) {
    final busy =
        _stage != _RxStage.idle && _stage != _RxStage.done;

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Receive data')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_stage == _RxStage.done)
            _GlassPanel(
              child: Column(
                children: [
                  const _SuccessBadge(
                    label: 'All data restored',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Please close and reopen Wallet on this phone '
                    'to finish the migration.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => Navigator.of(context)
                        .popUntil((route) => route.isFirst),
                    child: const Text('Back to wallet'),
                  ),
                ],
              ),
            )
          else ...[
            _GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enter the 6-digit code',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _codeCtrl,
                    enabled: !busy,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 10,
                    ),
                    decoration: const InputDecoration(
                      counterText: '',
                      hintText: '000000',
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: busy ? null : _start,
                    icon: const Icon(
                      Icons.wifi_tethering_rounded,
                    ),
                    label: Text(
                      busy ? 'Connecting…' : 'Connect & receive',
                    ),
                  ),
                ],
              ),
            ),
            if (busy) ...[
              const SizedBox(height: 16),
              _GlassPanel(
                child: Column(
                  children: [
                    Text(_statusLabel),
                    const SizedBox(height: 12),
                    _Progress(
                      value: _stage == _RxStage.restoring
                          ? null
                          : _progress,
                    ),
                  ],
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorPanel(
                message: _error!,
                onRetry: _start,
              ),
            ],
            const SizedBox(height: 16),
            _GlassPanel(
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Receiving replaces everything currently stored '
                      'on this phone.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- pieces

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeDisplay extends StatelessWidget {
  const _CodeDisplay({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: code.split('').map((d) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          height: 56,
          width: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            d,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value});

  final double? value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 10,
      ),
    );
  }
}

class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.elasticOut,
      builder: (_, t, child) => Transform.scale(
        scale: t.clamp(0, 1.2),
        child: child,
      ),
      child: Column(
        children: [
          Container(
            height: 66,
            width: 66,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 38,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: scheme.onErrorContainer,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.onErrorContainer,
                height: 1.3,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
