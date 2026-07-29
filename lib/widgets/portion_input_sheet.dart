import 'dart:io';
import 'package:flutter/material.dart';
import '../services/localization/app_localization_service.dart';
import 'package:flutter/services.dart';

class PortionInputSheet extends StatefulWidget {
  final String title;
  final String? imageUrl;
  final double initialGrams;

  const PortionInputSheet(
      {super.key, required this.title, this.imageUrl, this.initialGrams = 100});

  static Future<double?> show({
    required BuildContext context,
    required String title,
    String? imageUrl,
    double initialGrams = 100,
  }) async {
    return showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: PortionInputSheet(
              title: title, imageUrl: imageUrl, initialGrams: initialGrams),
        );
      },
    );
  }

  @override
  State<PortionInputSheet> createState() => _PortionInputSheetState();
}

class _PortionInputSheetState extends State<PortionInputSheet> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller =
        TextEditingController(text: widget.initialGrams.toStringAsFixed(0));
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        FocusScope.of(context).requestFocus(_focusNode);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('enter_portion_weight'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildImage(widget.imageUrl),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            focusNode: _focusNode,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            decoration: InputDecoration(
              labelText: context.tr('portion_weight_grams'),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(context.tr('cancel')),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  final v =
                      double.tryParse(_controller.text.replaceAll(',', '.'));
                  Navigator.of(context).pop(v);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
                child: Text(context.tr('done'),
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return Container(
        width: 70,
        height: 70,
        color: Colors.grey[200],
        child: const Icon(Icons.fastfood, color: Colors.grey),
      );
    }
    final isNetwork =
        imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
    final isFileUri = imageUrl.startsWith('file://');
    if (isNetwork) {
      return Image.network(imageUrl, width: 70, height: 70, fit: BoxFit.cover);
    }
    if (isFileUri) {
      return Image.file(File.fromUri(Uri.parse(imageUrl)),
          width: 70, height: 70, fit: BoxFit.cover);
    }
    return Image.file(File(imageUrl), width: 70, height: 70, fit: BoxFit.cover);
  }
}
