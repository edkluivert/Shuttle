import 'package:flutter/material.dart';

/// Returns the new name, or null if the user backed out.
Future<String?> showRenameDeviceDialog(
  BuildContext context,
  String currentName,
) {
  final controller = TextEditingController(text: currentName);

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Device name'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          helperText: 'This is what other devices see.',
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
