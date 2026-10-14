import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../records/providers/records_providers.dart';

/// Search input bound to the shared [searchQueryProvider]. Changes from any
/// screen (dashboard or records list) stay in sync.
class RecordSearchField extends ConsumerStatefulWidget {
  const RecordSearchField({super.key, this.focusNode, this.onSubmitted});

  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;

  @override
  ConsumerState<RecordSearchField> createState() => _RecordSearchFieldState();
}

class _RecordSearchFieldState extends ConsumerState<RecordSearchField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(searchQueryProvider));
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep the field in sync with external query changes.
    ref.listen<String>(searchQueryProvider, (previous, next) {
      if (_controller.text != next) {
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    });

    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      textInputAction: TextInputAction.search,
      onChanged: (value) =>
          ref.read(searchQueryProvider.notifier).update(value),
      onSubmitted: (value) => widget.onSubmitted?.call(value),
      decoration: InputDecoration(
        hintText: 'Search by name, mobile or Aadhaar',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) {
              return const SizedBox.shrink();
            }
            return IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear search',
              onPressed: () {
                _controller.clear();
                ref.read(searchQueryProvider.notifier).clear();
              },
            );
          },
        ),
      ),
    );
  }
}
