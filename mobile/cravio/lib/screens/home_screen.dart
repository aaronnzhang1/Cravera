import 'package:flutter/material.dart';
import '../core/app_colors.dart';
import '../core/session.dart';
import '../widgets/results_sheet.dart';
import '../widgets/cravio_pulse_logo.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _promptController = TextEditingController();
  bool _isFinding = false;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = AppSessionScope.of(context);

    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
            child: Column(
              children: [
                const SizedBox(height: 12),
                const CravioPulseLogo(),
                const SizedBox(height: 18),
                Text(
                  'cravio.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'your AI food concierge',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
                ),
                const SizedBox(height: 24),
                Text(
                  'Hi ${session.displayName},\nwhat are you craving today?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                _PromptInput(
                  controller: _promptController,
                  isBusy: _isFinding,
                  onSend: _runFindFlow,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _runFindFlow() async {
    if (_isFinding) return;

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    setState(() => _isFinding = true);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _FindingDialog(),
    );

    if (!mounted) return;
    setState(() => _isFinding = false);
    await showResultsSheet(context, prompt: prompt);
  }
}

class _PromptInput extends StatelessWidget {
  final TextEditingController controller;
  final bool isBusy;
  final VoidCallback onSend;
  final VoidCallback? onManualFilter;
  const _PromptInput({required this.controller, required this.isBusy, required this.onSend, this.onManualFilter});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keeps the input near the bottom, but not too low above the nav.
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Type your craving…',
              ),
            ),
          ),
          const SizedBox(width: 12),
          _SquareAction(
            icon: Icons.tune_rounded,
            onPressed: onManualFilter ?? () {},
          ),
          const SizedBox(width: 10),
          _SquareAction(
            icon: Icons.mic_rounded,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Voice input coming soon')),
              );
            },
          ),
          const SizedBox(width: 10),
          _SquareAction(
            icon: Icons.arrow_upward_rounded,
            onPressed: onSend,
            filled: true,
            disabled: isBusy,
          ),
        ],
      ),
    );
  }
}

class _FindingDialog extends StatefulWidget {
  const _FindingDialog();

  @override
  State<_FindingDialog> createState() => _FindingDialogState();
}

class _FindingDialogState extends State<_FindingDialog> {
  static const _messages = [
    'Hold on while I look…',
    'Scanning nearby favorites…',
    'Matching your craving…',
  ];

  int _index = 0;

  @override
  void initState() {
    super.initState();
    _loop();
  }

  Future<void> _loop() async {
    for (var i = 0; i < 6; i++) {
      if (!mounted) return;
      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      setState(() => _index = (_index + 1) % _messages.length);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.55), width: 1),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.3),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: Text(
                  _messages[_index],
                  key: ValueKey(_messages[_index]),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;
  final bool disabled;

  @override
  const _SquareAction({
    required this.icon,
    required this.onPressed,
    this.filled = false,
    this.disabled = false,
  });

  Widget build(BuildContext context) {
    final bg = disabled
        ? const Color(0xFF1A2A23)
        : (filled ? const Color(0xFF234A37) : const Color(0xFF0E1C16));

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1D3329).withValues(alpha: 0.50), width: 1),
      ),
      child: IconButton(
        onPressed: disabled ? null : onPressed,
        icon: Icon(icon, color: const Color(0xFFE8F2EC)),
      ),
    );
  }
}
