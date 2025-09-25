import 'package:flutter/material.dart';

class TranscodeProgressOverlay extends StatelessWidget {
  const TranscodeProgressOverlay({super.key, required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final value = progress;
    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Preparing lightweight preview…',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 200,
            child: LinearProgressIndicator(value: value),
          ),
          if (value != null) ...[
            const SizedBox(height: 6),
            Text(
              '${(value * 100).clamp(0, 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class TranscodeErrorBanner extends StatelessWidget {
  const TranscodeErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          message,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
