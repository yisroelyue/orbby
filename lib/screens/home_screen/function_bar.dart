part of 'home_screen.dart';

/// Only presentation and expansion state live here; actions belong to the host.
class _HomeFunctionBar extends StatefulWidget {
  const _HomeFunctionBar({required this.actions});

  final List<({IconData icon, String label, VoidCallback onPressed})> actions;

  @override
  State<_HomeFunctionBar> createState() => _HomeFunctionBarState();
}

class _HomeFunctionBarState extends State<_HomeFunctionBar> {
  bool _expanded = false;

  void _collapse() {
    if (_expanded) setState(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ChatTheme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: TapRegion(
        onTapOutside: (_) => _collapse(),
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            height: 40,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    fixedSize: const Size.square(40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  padding: const EdgeInsets.all(10),
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  tooltip: _expanded ? '收起功能' : '展开功能',
                  isSelected: _expanded,
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    child: Icon(
                      Icons.menu,
                      size: 20,
                      color: _expanded ? theme.ink : theme.ink2,
                    ),
                  ),
                ),
                if (_expanded)
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final action in widget.actions)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  foregroundColor: theme.ink2,
                                  minimumSize: const Size(0, 40),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () {
                                  _collapse();
                                  action.onPressed();
                                },
                                icon: Icon(action.icon, size: 18),
                                label: Text(action.label),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
