import 'package:flutter/material.dart';

enum BodyView { front, back }

class BodyRegionOption {
  const BodyRegionOption({
    required this.id,
    required this.label,
    required this.bodyPart,
    required this.group,
    required this.view,
  });

  final String id;
  final String label;
  final String bodyPart;
  final String group;
  final BodyView view;
}

const bodyRegionOptions = <BodyRegionOption>[
  BodyRegionOption(
      id: 'head',
      label: 'Head',
      bodyPart: 'head_face',
      group: 'Head and face',
      view: BodyView.front),
  BodyRegionOption(
      id: 'face',
      label: 'Face',
      bodyPart: 'head_face',
      group: 'Head and face',
      view: BodyView.front),
  BodyRegionOption(
      id: 'forehead',
      label: 'Forehead',
      bodyPart: 'head_face',
      group: 'Head and face',
      view: BodyView.front),
  BodyRegionOption(
      id: 'left_cheek',
      label: 'Left cheek',
      bodyPart: 'head_face',
      group: 'Head and face',
      view: BodyView.front),
  BodyRegionOption(
      id: 'right_cheek',
      label: 'Right cheek',
      bodyPart: 'head_face',
      group: 'Head and face',
      view: BodyView.front),
  BodyRegionOption(
      id: 'nose',
      label: 'Nose',
      bodyPart: 'head_face',
      group: 'Head and face',
      view: BodyView.front),
  BodyRegionOption(
      id: 'chin',
      label: 'Chin',
      bodyPart: 'head_face',
      group: 'Head and face',
      view: BodyView.front),
  BodyRegionOption(
      id: 'jawline',
      label: 'Jawline',
      bodyPart: 'head_face',
      group: 'Head and face',
      view: BodyView.front),
  BodyRegionOption(
      id: 'around_eyes',
      label: 'Around the eyes',
      bodyPart: 'head_face',
      group: 'Head and face',
      view: BodyView.front),
  BodyRegionOption(
      id: 'lips_surrounding',
      label: 'Lips and surrounding skin',
      bodyPart: 'head_face',
      group: 'Head and face',
      view: BodyView.front),
  BodyRegionOption(
      id: 'scalp',
      label: 'Scalp',
      bodyPart: 'head_face',
      group: 'Head and face',
      view: BodyView.back),
  BodyRegionOption(
      id: 'ears',
      label: 'Ears',
      bodyPart: 'head_face',
      group: 'Head and face',
      view: BodyView.front),
  BodyRegionOption(
      id: 'neck',
      label: 'Neck',
      bodyPart: 'neck',
      group: 'Head and face',
      view: BodyView.front),
  BodyRegionOption(
      id: 'chest',
      label: 'Chest',
      bodyPart: 'upper_body_front',
      group: 'Upper body — front',
      view: BodyView.front),
  BodyRegionOption(
      id: 'arms',
      label: 'Arms',
      bodyPart: 'upper_body_front',
      group: 'Upper body — front',
      view: BodyView.front),
  BodyRegionOption(
      id: 'shoulders',
      label: 'Shoulders',
      bodyPart: 'upper_body_front',
      group: 'Upper body — front',
      view: BodyView.front),
  BodyRegionOption(
      id: 'upper_arms',
      label: 'Upper arms',
      bodyPart: 'upper_body_front',
      group: 'Upper body — front',
      view: BodyView.front),
  BodyRegionOption(
      id: 'left_arm',
      label: 'Left arm',
      bodyPart: 'upper_body_front',
      group: 'Upper body — front',
      view: BodyView.front),
  BodyRegionOption(
      id: 'right_arm',
      label: 'Right arm',
      bodyPart: 'upper_body_front',
      group: 'Upper body — front',
      view: BodyView.front),
  BodyRegionOption(
      id: 'elbows',
      label: 'Elbows',
      bodyPart: 'upper_body_front',
      group: 'Upper body — front',
      view: BodyView.front),
  BodyRegionOption(
      id: 'forearms',
      label: 'Forearms',
      bodyPart: 'upper_body_front',
      group: 'Upper body — front',
      view: BodyView.front),
  BodyRegionOption(
      id: 'abdomen',
      label: 'Abdomen',
      bodyPart: 'upper_body_front',
      group: 'Upper body — front',
      view: BodyView.front),
  BodyRegionOption(
      id: 'stomach',
      label: 'Stomach',
      bodyPart: 'upper_body_front',
      group: 'Upper body — front',
      view: BodyView.front),
  BodyRegionOption(
      id: 'navel',
      label: 'Navel area',
      bodyPart: 'upper_body_front',
      group: 'Upper body — front',
      view: BodyView.front),
  BodyRegionOption(
      id: 'upper_back',
      label: 'Upper back',
      bodyPart: 'back',
      group: 'Upper body — back',
      view: BodyView.back),
  BodyRegionOption(
      id: 'back',
      label: 'Back',
      bodyPart: 'back',
      group: 'Upper body — back',
      view: BodyView.back),
  BodyRegionOption(
      id: 'hands',
      label: 'Hands',
      bodyPart: 'hands',
      group: 'Hands',
      view: BodyView.front),
  BodyRegionOption(
      id: 'middle_back',
      label: 'Middle back',
      bodyPart: 'back',
      group: 'Upper body — back',
      view: BodyView.back),
  BodyRegionOption(
      id: 'lower_back',
      label: 'Lower back',
      bodyPart: 'back',
      group: 'Upper body — back',
      view: BodyView.back),
  BodyRegionOption(
      id: 'left_shoulder_blade',
      label: 'Left shoulder blade',
      bodyPart: 'back',
      group: 'Upper body — back',
      view: BodyView.back),
  BodyRegionOption(
      id: 'right_shoulder_blade',
      label: 'Right shoulder blade',
      bodyPart: 'back',
      group: 'Upper body — back',
      view: BodyView.back),
  BodyRegionOption(
      id: 'back_of_neck',
      label: 'Back of neck',
      bodyPart: 'back',
      group: 'Upper body — back',
      view: BodyView.back),
  BodyRegionOption(
      id: 'back_of_upper_arms',
      label: 'Back of upper arms',
      bodyPart: 'back',
      group: 'Upper body — back',
      view: BodyView.back),
  BodyRegionOption(
      id: 'left_hand',
      label: 'Left hand',
      bodyPart: 'hands',
      group: 'Hands',
      view: BodyView.front),
  BodyRegionOption(
      id: 'right_hand',
      label: 'Right hand',
      bodyPart: 'hands',
      group: 'Hands',
      view: BodyView.front),
  BodyRegionOption(
      id: 'palms',
      label: 'Palms',
      bodyPart: 'hands',
      group: 'Hands',
      view: BodyView.front),
  BodyRegionOption(
      id: 'back_of_hands',
      label: 'Back of hands',
      bodyPart: 'hands',
      group: 'Hands',
      view: BodyView.back),
  BodyRegionOption(
      id: 'fingers',
      label: 'Fingers',
      bodyPart: 'hands',
      group: 'Hands',
      view: BodyView.front),
  BodyRegionOption(
      id: 'fingertips',
      label: 'Fingertips',
      bodyPart: 'hands',
      group: 'Hands',
      view: BodyView.front),
  BodyRegionOption(
      id: 'fingernails',
      label: 'Fingernails',
      bodyPart: 'hands',
      group: 'Hands',
      view: BodyView.front),
  BodyRegionOption(
      id: 'skin_around_nails',
      label: 'Skin around nails',
      bodyPart: 'hands',
      group: 'Hands',
      view: BodyView.front),
  BodyRegionOption(
      id: 'hips',
      label: 'Hips',
      bodyPart: 'lower_body',
      group: 'Lower body',
      view: BodyView.front),
  BodyRegionOption(
      id: 'legs',
      label: 'Legs',
      bodyPart: 'lower_body',
      group: 'Lower body',
      view: BodyView.front),
  BodyRegionOption(
      id: 'buttocks',
      label: 'Buttocks',
      bodyPart: 'lower_body',
      group: 'Lower body',
      view: BodyView.back),
  BodyRegionOption(
      id: 'thighs',
      label: 'Thighs',
      bodyPart: 'lower_body',
      group: 'Lower body',
      view: BodyView.front),
  BodyRegionOption(
      id: 'left_thigh',
      label: 'Left thigh',
      bodyPart: 'lower_body',
      group: 'Lower body',
      view: BodyView.front),
  BodyRegionOption(
      id: 'right_thigh',
      label: 'Right thigh',
      bodyPart: 'lower_body',
      group: 'Lower body',
      view: BodyView.front),
  BodyRegionOption(
      id: 'knees',
      label: 'Knees',
      bodyPart: 'lower_body',
      group: 'Lower body',
      view: BodyView.front),
  BodyRegionOption(
      id: 'calves',
      label: 'Calves',
      bodyPart: 'lower_body',
      group: 'Lower body',
      view: BodyView.front),
  BodyRegionOption(
      id: 'shins',
      label: 'Shins',
      bodyPart: 'lower_body',
      group: 'Lower body',
      view: BodyView.front),
  BodyRegionOption(
      id: 'ankles',
      label: 'Ankles',
      bodyPart: 'lower_body',
      group: 'Lower body',
      view: BodyView.front),
  BodyRegionOption(
      id: 'left_foot',
      label: 'Left foot',
      bodyPart: 'feet',
      group: 'Feet',
      view: BodyView.front),
  BodyRegionOption(
      id: 'feet',
      label: 'Feet',
      bodyPart: 'feet',
      group: 'Feet',
      view: BodyView.front),
  BodyRegionOption(
      id: 'right_foot',
      label: 'Right foot',
      bodyPart: 'feet',
      group: 'Feet',
      view: BodyView.front),
  BodyRegionOption(
      id: 'soles',
      label: 'Soles',
      bodyPart: 'feet',
      group: 'Feet',
      view: BodyView.back),
  BodyRegionOption(
      id: 'top_of_feet',
      label: 'Top of feet',
      bodyPart: 'feet',
      group: 'Feet',
      view: BodyView.front),
  BodyRegionOption(
      id: 'heels',
      label: 'Heels',
      bodyPart: 'feet',
      group: 'Feet',
      view: BodyView.back),
  BodyRegionOption(
      id: 'toes',
      label: 'Toes',
      bodyPart: 'feet',
      group: 'Feet',
      view: BodyView.front),
  BodyRegionOption(
      id: 'toenails',
      label: 'Toenails',
      bodyPart: 'feet',
      group: 'Feet',
      view: BodyView.front),
  BodyRegionOption(
      id: 'skin_around_toenails',
      label: 'Skin around toenails',
      bodyPart: 'feet',
      group: 'Feet',
      view: BodyView.front),
  BodyRegionOption(
      id: 'other',
      label: 'Other body area',
      bodyPart: 'other',
      group: 'Additional options',
      view: BodyView.front),
  BodyRegionOption(
      id: 'unsure',
      label: 'Unsure / Not sure',
      bodyPart: 'unsure',
      group: 'Additional options',
      view: BodyView.front),
];

bool isSelectableBodyRegion(String regionId) =>
    bodyRegionOptions.any((region) => region.id == regionId);

class BodyRegionSelector extends StatefulWidget {
  const BodyRegionSelector({
    required this.selectedRegion,
    required this.accentColor,
    required this.panelColor,
    required this.textColor,
    required this.mutedColor,
    required this.borderColor,
    required this.onSelected,
    required this.onCleared,
    this.featuredCategoryCard,
    this.localize,
    super.key,
  });

  final String? selectedRegion;
  final Color accentColor;
  final Color panelColor;
  final Color textColor;
  final Color mutedColor;
  final Color borderColor;
  final ValueChanged<BodyRegionOption> onSelected;
  final VoidCallback onCleared;
  final Widget? featuredCategoryCard;
  final String Function(String key, {Map<String, String> arguments})? localize;

  @override
  State<BodyRegionSelector> createState() => _BodyRegionSelectorState();
}

class _BodyRegionSelectorState extends State<BodyRegionSelector> {
  final _searchController = TextEditingController();
  BodyView _view = BodyView.front;
  String? _expandedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleRegionTap(BodyRegionOption region) {
    widget.onSelected(region);
  }

  void _toggleCategory(String category) {
    setState(() {
      _expandedCategory = _expandedCategory == category ? null : category;
    });
  }

  @override
  Widget build(BuildContext context) {
    final localize = widget.localize ??
        ((key, {arguments = const <String, String>{}}) => key);
    final search = _searchController.text.trim().toLowerCase();
    final categories = <String, List<BodyRegionOption>>{};
    for (final region in bodyRegionOptions) {
      final category = _categoryFor(region);
      if (search.isNotEmpty &&
          !region.label.toLowerCase().contains(search) &&
          !region.group.toLowerCase().contains(search) &&
          !category.toLowerCase().contains(search)) {
        continue;
      }
      categories.putIfAbsent(category, () => []).add(region);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: widget.textColor),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, color: widget.mutedColor),
            hintText: localize('searchBodyAreas'),
            hintStyle: TextStyle(color: widget.mutedColor),
            filled: true,
            fillColor: widget.panelColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: widget.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: widget.borderColor),
            ),
          ),
        ),
        if (widget.selectedRegion != null &&
            isSelectableBodyRegion(widget.selectedRegion!))
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                avatar: const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: Color(0xFFFF0000),
                ),
                label: Text(
                  bodyRegionOptions
                      .firstWhere(
                          (region) => region.id == widget.selectedRegion)
                      .label,
                ),
                onDeleted: widget.onCleared,
                deleteButtonTooltipMessage: localize('removeSelectedArea'),
                selectedColor: const Color(0x1FFF0000),
                side: const BorderSide(color: Color(0xFFFF0000)),
                labelStyle: const TextStyle(
                  color: Color(0xFFFF0000),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        const SizedBox(height: 12),
        SegmentedButton<BodyView>(
          segments: [
            ButtonSegment(
              value: BodyView.front,
              label: Text(localize('bodyFront')),
              icon: const Icon(Icons.accessibility_new_rounded),
            ),
            ButtonSegment(
              value: BodyView.back,
              label: Text(localize('bodyBack')),
              icon: const Icon(Icons.accessibility_new_rounded),
            ),
          ],
          selected: {_view},
          onSelectionChanged: (selection) =>
              setState(() => _view = selection.first),
        ),
        const SizedBox(height: 12),
        _InteractiveBodyMap(
          view: _view,
          selectedRegion: widget.selectedRegion,
          accentColor: widget.accentColor,
          panelColor: widget.panelColor,
          borderColor: widget.borderColor,
          onSelected: (id) {
            final region =
                bodyRegionOptions.firstWhere((item) => item.id == id);
            _handleRegionTap(region);
          },
        ),
        const SizedBox(height: 10),
        if (categories.isEmpty)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              localize('noBodyAreasMatchSearch'),
              style: TextStyle(color: widget.mutedColor),
            ),
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = constraints.maxWidth < 300 ? 1 : 2;
              return GridView.count(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: crossAxisCount == 1
                    ? 3.2
                    : widget.featuredCategoryCard == null
                        ? 2.0
                        : 1.65,
                children: [
                  if (widget.featuredCategoryCard != null)
                    widget.featuredCategoryCard!,
                  for (final entry in categories.entries)
                    Builder(builder: (context) {
                      final allRegions = bodyRegionOptions
                          .where((region) => _categoryFor(region) == entry.key)
                          .toList();
                      return _categoryCard(entry.key, allRegions, search);
                    }),
                ],
              );
            },
          ),
          for (final entry in categories.entries)
            if (_isCategoryExpanded(entry.key, search)) ...[
              const SizedBox(height: 12),
              Text(
                entry.key,
                style: TextStyle(
                  color: widget.textColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final region in entry.value) _regionChip(region),
                ],
              ),
            ],
        ],
      ],
    );
  }

  bool _isCategoryExpanded(String category, String search) =>
      search.isNotEmpty || _expandedCategory == category;

  Widget _categoryCard(
    String category,
    List<BodyRegionOption> regions,
    String search,
  ) {
    final expanded = _isCategoryExpanded(category, search);
    return Material(
      color: widget.panelColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _toggleCategory(category),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.borderColor),
          ),
          child: Row(
            children: [
              Icon(_categoryIcon(category),
                  color: widget.accentColor, size: 21),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${regions.length} ${regions.length == 1 ? 'area' : 'areas'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.mutedColor,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                expanded ? Icons.expand_less : Icons.expand_more,
                color: widget.mutedColor,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _regionChip(BodyRegionOption region) {
    final isSelected = region.id == widget.selectedRegion;
    return ActionChip(
      avatar: Icon(
        isSelected
            ? Icons.check_circle_rounded
            : Icons.circle_outlined,
        size: 17,
        color: isSelected
            ? widget.accentColor
            : widget.mutedColor,
      ),
      label: Text(region.label),
      labelStyle: TextStyle(
        color: isSelected ? widget.accentColor : widget.textColor,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      side: BorderSide(
          color: isSelected ? widget.accentColor : widget.borderColor),
      onPressed: () => _handleRegionTap(region),
    );
  }

  String _categoryFor(BodyRegionOption region) {
    if (region.group == 'Head and face') return 'Head & Face';
    if (region.group == 'Hands' ||
        const {
          'arms',
          'upper_arms',
          'left_arm',
          'right_arm',
          'elbows',
          'forearms',
          'back_of_upper_arms',
        }.contains(region.id)) {
      return 'Arms & Hands';
    }
    if (region.group == 'Feet' ||
        const {'legs', 'knees', 'calves', 'shins', 'ankles'}
            .contains(region.id)) {
      return 'Legs & Feet';
    }
    if (region.group == 'Lower body') return 'Lower Body';
    if (region.group.startsWith('Upper body')) return 'Upper Body';
    return 'Additional options';
  }

  IconData _categoryIcon(String category) => switch (category) {
        'Head & Face' => Icons.face_retouching_natural_rounded,
        'Upper Body' => Icons.accessibility_new_rounded,
        'Arms & Hands' => Icons.back_hand_outlined,
        'Lower Body' => Icons.airline_seat_legroom_extra_rounded,
        'Legs & Feet' => Icons.directions_walk_rounded,
        _ => Icons.more_horiz_rounded,
      };
}

class _InteractiveBodyMap extends StatelessWidget {
  const _InteractiveBodyMap({
    required this.view,
    required this.selectedRegion,
    required this.accentColor,
    required this.panelColor,
    required this.borderColor,
    required this.onSelected,
  });

  final BodyView view;
  final String? selectedRegion;
  final Color accentColor;
  final Color panelColor;
  final Color borderColor;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final isFront = view == BodyView.front;
    final targets = isFront
        ? const [
            (id: 'face', label: 'Face', x: .50, y: .12),
            (id: 'neck', label: 'Neck', x: .50, y: .23),
            (id: 'shoulders', label: 'Shoulders', x: .50, y: .32),
            (id: 'right_arm', label: 'Right arm', x: .18, y: .40),
            (id: 'chest', label: 'Chest', x: .50, y: .40),
            (id: 'left_arm', label: 'Left arm', x: .82, y: .40),
            (id: 'abdomen', label: 'Abdomen', x: .50, y: .54),
            (id: 'right_hand', label: 'Right hand', x: .17, y: .65),
            (id: 'left_hand', label: 'Left hand', x: .83, y: .65),
            (id: 'right_thigh', label: 'Right thigh', x: .41, y: .72),
            (id: 'left_thigh', label: 'Left thigh', x: .59, y: .72),
            (id: 'right_foot', label: 'Right foot', x: .41, y: .94),
            (id: 'left_foot', label: 'Left foot', x: .59, y: .94),
          ]
        : const [
            (id: 'scalp', label: 'Scalp', x: .50, y: .12),
            (id: 'back_of_neck', label: 'Neck', x: .50, y: .23),
            (id: 'upper_back', label: 'Upper back', x: .50, y: .37),
            (id: 'left_shoulder_blade', label: 'Left shoulder', x: .36, y: .38),
            (
              id: 'right_shoulder_blade',
              label: 'Right shoulder',
              x: .64,
              y: .38
            ),
            (id: 'back_of_upper_arms', label: 'Arms', x: .18, y: .43),
            (id: 'middle_back', label: 'Middle back', x: .50, y: .49),
            (id: 'lower_back', label: 'Lower back', x: .50, y: .59),
            (id: 'buttocks', label: 'Hips', x: .50, y: .67),
            (id: 'back_of_hands', label: 'Hands', x: .17, y: .68),
            (id: 'calves', label: 'Calves', x: .50, y: .83),
            (id: 'heels', label: 'Heels', x: .50, y: .95),
          ];

    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _BodySilhouettePainter(
                  color: accentColor.withValues(alpha: 0.12),
                  outline: borderColor,
                ),
              ),
            ),
            for (final target in targets)
              Positioned(
                left: constraints.maxWidth * target.x - 26,
                top: 320 * target.y - 20,
                child: Semantics(
                  button: true,
                  label: 'Select ${target.label}',
                  selected: selectedRegion == target.id &&
                      isSelectableBodyRegion(target.id),
                  child: Tooltip(
                    message: target.label,
                    child: Material(
                      color: selectedRegion == target.id &&
                              isSelectableBodyRegion(target.id)
                          ? const Color(0xFFFF0000)
                          : panelColor,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => onSelected(target.id),
                        child: Container(
                          width: 52,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selectedRegion == target.id &&
                                      isSelectableBodyRegion(target.id)
                                  ? const Color(0xFFFF0000)
                                  : borderColor,
                              width: 1.5,
                            ),
                          ),
                          child: Icon(
                            Icons.touch_app_outlined,
                            size: 19,
                            color: selectedRegion == target.id &&
                                    isSelectableBodyRegion(target.id)
                                ? panelColor
                                : accentColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: 8,
              child: Text(
                isFront
                    ? 'Front view • Tap a marker'
                    : 'Back view • Tap a marker',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BodySilhouettePainter extends CustomPainter {
  const _BodySilhouettePainter({required this.color, required this.outline});

  final Color color;
  final Color outline;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 220;
    final offset = Offset((size.width - 220 * scale) / 2, 0);
    canvas.save();
    canvas.translate(offset.dx, 0);
    canvas.scale(scale, size.height / 320);

    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final head = RRect.fromRectAndRadius(
      const Rect.fromLTWH(91, 13, 38, 48),
      const Radius.circular(20),
    );
    canvas.drawRRect(head, fill);
    canvas.drawRRect(head, stroke);

    final body = Path()
      ..moveTo(91, 66)
      ..quadraticBezierTo(67, 68, 61, 88)
      ..lineTo(47, 145)
      ..quadraticBezierTo(46, 155, 57, 158)
      ..quadraticBezierTo(65, 159, 68, 148)
      ..lineTo(78, 111)
      ..lineTo(79, 181)
      ..lineTo(73, 278)
      ..quadraticBezierTo(72, 291, 84, 292)
      ..quadraticBezierTo(95, 293, 96, 280)
      ..lineTo(109, 211)
      ..lineTo(124, 280)
      ..quadraticBezierTo(126, 293, 137, 292)
      ..quadraticBezierTo(149, 291, 146, 278)
      ..lineTo(141, 181)
      ..lineTo(142, 111)
      ..lineTo(153, 148)
      ..quadraticBezierTo(157, 159, 166, 157)
      ..quadraticBezierTo(176, 154, 172, 144)
      ..lineTo(158, 88)
      ..quadraticBezierTo(151, 68, 129, 66)
      ..close();
    canvas.drawPath(body, fill);
    canvas.drawPath(body, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BodySilhouettePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.outline != outline;
}
