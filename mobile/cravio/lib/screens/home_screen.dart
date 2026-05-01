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
                  onSend: () => showResultsSheet(context, prompt: _promptController.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _PromptInput({required this.controller, required this.onSend});

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
          ),
        ],
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool filled;

  @override
  const _SquareAction({
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  Widget build(BuildContext context) {
    final bg = filled ? const Color(0xFF234A37) : const Color(0xFF0E1C16);

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1D3329).withValues(alpha: 0.50), width: 1),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: const Color(0xFFE8F2EC)),
      ),
    );
  }
}
