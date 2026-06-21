import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The bottom-nav tabs, in display order (drives the shell's IndexedStack and
/// nav bar). Kept in a provider so any widget can switch tabs — e.g. tapping a
/// control with no device jumps to [HomeTab.devices].
enum HomeTab { remote, touchpad, devices }

final selectedTabProvider =
    NotifierProvider<SelectedTabNotifier, HomeTab>(SelectedTabNotifier.new);

class SelectedTabNotifier extends Notifier<HomeTab> {
  @override
  HomeTab build() => HomeTab.remote;

  void select(HomeTab tab) => state = tab;
}
