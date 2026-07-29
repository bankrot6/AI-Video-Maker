import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';

import '../../services/localization/app_localization_service.dart';
import '../home/home_providers.dart' as home;
import '../../models/measurement_entry_model.dart';

class MeasurementsInputScreen extends ConsumerStatefulWidget {
  const MeasurementsInputScreen({super.key});

  @override
  ConsumerState<MeasurementsInputScreen> createState() =>
      _MeasurementsInputScreenState();
}

class _MeasurementsInputScreenState
    extends ConsumerState<MeasurementsInputScreen> {
  double? _chest, _waist, _hips, _leg, _arm, _shoulders, _abdomen;
  double? _prevChest,
      _prevWaist,
      _prevHips,
      _prevLeg,
      _prevArm,
      _prevShoulders,
      _prevAbdomen;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final repo = ref.read(home.measurementRepositoryProvider);
      final latest = await repo.getLatestEntry();
      if (!mounted) return;
      setState(() {
        _chest = latest?.chest;
        _waist = latest?.waist;
        _hips = latest?.hips;
        _leg = latest?.leg;
        _arm = latest?.arm;
        _shoulders = latest?.shoulders;
        _abdomen = latest?.abdomen;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          context.tr('body_measurements_title'),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                children: [
                  _buildSectionCard(children: [
                    _buildMeasurementTile(
                      icon: Icons.monitor_heart_outlined,
                      title: context.tr('chest_circumference'),
                      value: _formatCm(_chest, context),
                      caption: _formatWas(_prevChest, context),
                      onTap: () async {
                        final v = await _showDoubleInputSheet(
                          title: context.tr('chest_circumference'),
                          suffix: context.tr('centimeters_short'),
                          initialValue: _chest,
                          min: 0,
                          max: 400,
                        );
                        if (v != null)
                          setState(() {
                            _prevChest = _chest;
                            _chest = v;
                          });
                      },
                    ),
                    _divider(),
                    _buildMeasurementTile(
                      icon: Icons.straighten,
                      title: context.tr('waist_circumference'),
                      value: _formatCm(_waist, context),
                      caption: _formatWas(_prevWaist, context),
                      onTap: () async {
                        final v = await _showDoubleInputSheet(
                          title: context.tr('waist_circumference'),
                          suffix: context.tr('centimeters_short'),
                          initialValue: _waist,
                          min: 0,
                          max: 400,
                        );
                        if (v != null)
                          setState(() {
                            _prevWaist = _waist;
                            _waist = v;
                          });
                      },
                    ),
                    _divider(),
                    _buildMeasurementTile(
                      icon: Icons.accessibility_new_outlined,
                      title: context.tr('hips_circumference'),
                      value: _formatCm(_hips, context),
                      caption: _formatWas(_prevHips, context),
                      onTap: () async {
                        final v = await _showDoubleInputSheet(
                          title: context.tr('hips_circumference'),
                          suffix: context.tr('centimeters_short'),
                          initialValue: _hips,
                          min: 0,
                          max: 400,
                        );
                        if (v != null)
                          setState(() {
                            _prevHips = _hips;
                            _hips = v;
                          });
                      },
                    ),
                    _divider(),
                    _buildMeasurementTile(
                      icon: Icons.directions_walk,
                      title: context.tr('leg_circumference'),
                      value: _formatCm(_leg, context),
                      caption: _formatWas(_prevLeg, context),
                      onTap: () async {
                        final v = await _showDoubleInputSheet(
                          title: context.tr('leg_circumference'),
                          suffix: context.tr('centimeters_short'),
                          initialValue: _leg,
                          min: 0,
                          max: 400,
                        );
                        if (v != null)
                          setState(() {
                            _prevLeg = _leg;
                            _leg = v;
                          });
                      },
                    ),
                    _divider(),
                    _buildMeasurementTile(
                      icon: Icons.fitness_center,
                      title: context.tr('arm_circumference'),
                      value: _formatCm(_arm, context),
                      caption: _formatWas(_prevArm, context),
                      onTap: () async {
                        final v = await _showDoubleInputSheet(
                          title: context.tr('arm_circumference'),
                          suffix: context.tr('centimeters_short'),
                          initialValue: _arm,
                          min: 0,
                          max: 400,
                        );
                        if (v != null)
                          setState(() {
                            _prevArm = _arm;
                            _arm = v;
                          });
                      },
                    ),
                    _divider(),
                    _buildMeasurementTile(
                      icon: Icons.accessibility_new,
                      title: context.tr('shoulders_circumference'),
                      value: _formatCm(_shoulders, context),
                      caption: _formatWas(_prevShoulders, context),
                      onTap: () async {
                        final v = await _showDoubleInputSheet(
                          title: context.tr('shoulders_circumference'),
                          suffix: context.tr('centimeters_short'),
                          initialValue: _shoulders,
                          min: 0,
                          max: 400,
                        );
                        if (v != null)
                          setState(() {
                            _prevShoulders = _shoulders;
                            _shoulders = v;
                          });
                      },
                    ),
                    _divider(),
                    _buildMeasurementTile(
                      icon: Icons.monitor_weight,
                      title: context.tr('abdomen_circumference'),
                      value: _formatCm(_abdomen, context),
                      caption: _formatWas(_prevAbdomen, context),
                      onTap: () async {
                        final v = await _showDoubleInputSheet(
                          title: context.tr('abdomen_circumference'),
                          suffix: context.tr('centimeters_short'),
                          initialValue: _abdomen,
                          min: 0,
                          max: 400,
                        );
                        if (v != null)
                          setState(() {
                            _prevAbdomen = _abdomen;
                            _abdomen = v;
                          });
                      },
                    ),
                  ]),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: SizedBox(
                width: double.infinity,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF86A8FF), Color(0xFF5E7FE1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF86A8FF).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _onSave,
                    child: Text(
                      context.tr('save'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    final entry = MeasurementEntryModel(
      id: const Uuid().v4(),
      dateTime: DateTime.now(),
      chest: _chest,
      waist: _waist,
      hips: _hips,
      leg: _leg,
      arm: _arm,
      shoulders: _shoulders,
      abdomen: _abdomen,
    );

    final repo = ref.read(home.measurementRepositoryProvider);
    await repo.addEntry(entry);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Widget _buildSectionCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(0.8),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(children: children),
      ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        thickness: 0.5,
        color: Colors.grey.withOpacity(0.2),
        indent: 18,
        endIndent: 18,
      );

  Widget _buildMeasurementTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
    String? caption,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF86A8FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: const Color(0xFF5E7FE1),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Color(0xFF86A8FF),
                    size: 20,
                  ),
                ],
              ),
              if (caption != null && caption.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        caption,
                        maxLines: 1,
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF999999),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatCm(double? v, BuildContext context) {
    if (v == null) return '—';
    final unit = context.tr('centimeters_short');
    final str = v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '$str $unit';
  }

  String? _formatWas(double? prev, BuildContext context) {
    if (prev == null) return null;
    return '${context.tr('was_prefix')} ${_formatCm(prev, context)}';
  }

  Future<double?> _showDoubleInputSheet({
    required String title,
    required String suffix,
    required double? initialValue,
    required double min,
    required double max,
  }) async {
    final controller = TextEditingController(
        text: initialValue == null
            ? ''
            : (initialValue % 1 == 0
                ? initialValue.toStringAsFixed(0)
                : initialValue.toStringAsFixed(1)));

    double? parsed;
    bool isValid(String value) {
      final normalized = value.replaceAll(',', '.');
      final v = double.tryParse(normalized);
      if (v == null) return false;
      parsed = v;
      return v >= min && v <= max;
    }

    bool valid = controller.text.isEmpty ? true : isValid(controller.text);

    return await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      alignment: Alignment.center,
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: valid
                              ? const Color(0xFF86A8FF).withOpacity(0.3)
                              : Colors.red.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              autofocus: true,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              textInputAction: TextInputAction.done,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]')),
                                _OneDecimalInputFormatter(),
                              ],
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                              ),
                              onChanged: (t) => setState(() {
                                valid = t.isEmpty ? true : isValid(t);
                              }),
                              onSubmitted: (_) {
                                if (valid) {
                                  Navigator.of(ctx).pop(parsed ??
                                      double.tryParse(controller.text
                                          .replaceAll(',', '.')));
                                }
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 16),
                            child: Text(
                              suffix,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              context.tr('cancel'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: valid
                                  ? const LinearGradient(
                                      colors: [
                                        Color(0xFF86A8FF),
                                        Color(0xFF5E7FE1)
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              color: valid ? null : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ElevatedButton(
                              onPressed: valid
                                  ? () {
                                      Navigator.of(ctx).pop(parsed ??
                                          double.tryParse(controller.text
                                              .replaceAll(',', '.')));
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                disabledBackgroundColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: Text(
                                context.tr('done'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }
}

class _OneDecimalInputFormatter extends TextInputFormatter {
  static final RegExp _pattern = RegExp(r'^\d{0,3}(?:[.,]\d?)?');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final String text = newValue.text.replaceAll(' ', '');
    if (text.isEmpty) {
      return newValue.copyWith(text: text);
    }
    if (_pattern.hasMatch(text)) {
      return newValue.copyWith(text: text, selection: newValue.selection);
    }
    return oldValue;
  }
}
