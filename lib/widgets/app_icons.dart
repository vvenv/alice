import 'package:flutter/material.dart';

/// Ionicons（RN 版用的 @expo/vector-icons）→ Material Icons 的映射。
///
/// 集中放一份，是为了迁移时能逐个对照 RN 侧的图标名，而不是在各处
/// 硬编码 Icons.xxx 之后再也说不清原来用的是哪个。
class AppIcons {
  const AppIcons._();

  static const IconData menu = Icons.menu;
  static const IconData camera = Icons.photo_camera;
  static const IconData cameraOutline = Icons.photo_camera_outlined;
  static const IconData images = Icons.photo_library_outlined;
  static const IconData time = Icons.watch_later_outlined;
  static const IconData star = Icons.star;
  static const IconData starOutline = Icons.star_border;
  static const IconData library = Icons.local_library_outlined;
  static const IconData settings = Icons.settings_outlined;
  static const IconData chevronForward = Icons.chevron_right;
  static const IconData chevronDown = Icons.keyboard_arrow_down;
  static const IconData chevronUp = Icons.keyboard_arrow_up;
  static const IconData close = Icons.close;
  static const IconData closeCircle = Icons.cancel;
  static const IconData closeCircleOutline = Icons.cancel_outlined;
  static const IconData checkmark = Icons.check;
  static const IconData checkmarkCircle = Icons.check_circle;
  static const IconData createOutline = Icons.edit_outlined;
  static const IconData infoOutline = Icons.info_outline;
  static const IconData wallet = Icons.account_balance_wallet_outlined;
  static const IconData server = Icons.dns_outlined;
  static const IconData search = Icons.search;
  static const IconData play = Icons.play_arrow;
  static const IconData pause = Icons.pause;
  static const IconData stop = Icons.stop;
  static const IconData skipBack = Icons.skip_previous;
  static const IconData skipForward = Icons.skip_next;
  static const IconData refresh = Icons.refresh;
  static const IconData arrowBack = Icons.arrow_back;
  static const IconData eye = Icons.visibility;
  static const IconData eyeOff = Icons.visibility_off;
  static const IconData eyeOutline = Icons.visibility_outlined;
  static const IconData eyeOffOutline = Icons.visibility_off_outlined;
  static const IconData sunny = Icons.light_mode;
  static const IconData moon = Icons.dark_mode;
  static const IconData musicalNotes = Icons.music_note_outlined;
  static const IconData language = Icons.translate_outlined;
  static const IconData speedometer = Icons.speed_outlined;
  static const IconData timer = Icons.timer_outlined;
  static const IconData trash = Icons.delete_outline;
  static const IconData scan = Icons.document_scanner_outlined;
  static const IconData card = Icons.credit_card_outlined;
  static const IconData alertCircle = Icons.error;
  static const IconData pricetag = Icons.local_offer_outlined;
}
