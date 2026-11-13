import 'package:flutter/material.dart';

/// Static Home action: no ambient glow, repeating ticker, or per-frame rebuild.
class AiAssistantButton extends StatelessWidget {
  const AiAssistantButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: SizedBox(
          width: 44,
          height: 44,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: const Color(0xFF10B981),
            elevation: 3,
            tooltip: 'My AI Assistant',
            onPressed: onPressed,
            child: const Icon(Icons.auto_awesome_rounded,
                color: Colors.white, size: 20),
          ),
        ),
      );
}
