import 'package:flutter/material.dart';

import '../services/credits.dart';
import '../theme/theme_controller.dart';
import '../theme/tokens.dart';
import 'app_icons.dart';

/// 充值弹窗。对应 RN 版 src/components/RechargeModal.tsx。
///
/// [onPurchase] 在 credits 到账后 resolve；弹窗内部显示购买中的转圈。
Future<void> showRechargeModal(
  BuildContext context, {
  required int credits,
  required Future<void> Function(CreditPack pack) onPurchase,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: context.themeController.colors.overlay,
    builder: (dialogContext) => _RechargeModal(
      initialCredits: credits,
      onPurchase: onPurchase,
    ),
  );
}

class _RechargeModal extends StatefulWidget {
  const _RechargeModal({
    required this.initialCredits,
    required this.onPurchase,
  });

  final int initialCredits;
  final Future<void> Function(CreditPack pack) onPurchase;

  @override
  State<_RechargeModal> createState() => _RechargeModalState();
}

class _RechargeModalState extends State<_RechargeModal> {
  String? _purchasing;
  String _error = '';
  late int _credits = widget.initialCredits;

  Future<void> _handlePurchase(CreditPack pack) async {
    setState(() {
      _purchasing = pack.id;
      _error = '';
    });
    try {
      await widget.onPurchase(pack);
      if (mounted) setState(() => _credits = getCachedCredits());
    } catch (error) {
      // 就地把失败显示出来。没有这个 catch，异常就没人接：转圈停了，
      // 用户什么反馈都拿不到。
      if (mounted) setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _purchasing = null);
    }
  }

  static String _errorText(Object error) {
    final text = error.toString();
    final message = text.startsWith('Exception: ') ? text.substring(11) : text;
    return message.isNotEmpty ? message : '充值失败，请重试';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final maxHeight = MediaQuery.of(context).size.height * 0.88;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(Spacing.lg),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(maxWidth: 380, maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶栏
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.lg,
                vertical: Spacing.md,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: colors.border, width: 0.5),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '领取演示积分',
                    style: TextStyle(
                      fontFamily: AppFonts.displayZh,
                      fontSize: 17,
                      color: colors.foreground,
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: '关闭',
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      behavior: HitTestBehavior.opaque,
                      child: Icon(
                        AppIcons.close,
                        size: 22,
                        color: colors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 余额条
            Container(
              margin: const EdgeInsets.all(Spacing.lg),
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.md,
              ),
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: BorderRadius.circular(Radii.control),
                border: Border.all(color: colors.primary),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.wallet, size: 18, color: colors.primary),
                  const SizedBox(width: Spacing.xs),
                  Expanded(
                    child: Text(
                      '当前余额',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ),
                  Semantics(
                    label: '当前余额 $_credits credits',
                    child: Text(
                      '$_credits',
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 22,
                        color: colors.primary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 套餐列表
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final pack in kCreditPacks) ...[
                      _PackCard(
                        pack: pack,
                        buying: _purchasing == pack.id,
                        onTap: () => _handlePurchase(pack),
                      ),
                      const SizedBox(height: Spacing.sm),
                    ],
                    if (_error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: Spacing.xs),
                        child: Text(
                          _error,
                          style: TextStyle(fontSize: 12, color: colors.danger),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: Spacing.xs),
                      child: Text(
                        '当前为演示积分：点选套餐立即到账，暂不扣款。高级识别每次成功扣除 1 credit。',
                        style: TextStyle(fontSize: 13, color: colors.muted),
                      ),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.only(top: 2, bottom: Spacing.sm),
                      child: Text(
                        '价格仅为将来接入应用内购买时的参考；现在领取不会产生费用。',
                        style: TextStyle(fontSize: 12, color: colors.subtle),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 底栏
            Container(
              padding: const EdgeInsets.all(Spacing.lg),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: colors.border, width: 0.5),
                ),
              ),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(Radii.button),
                  ),
                  child: Text(
                    '完成',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.background,
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
}

class _PackCard extends StatelessWidget {
  const _PackCard({
    required this.pack,
    required this.buying,
    required this.onTap,
  });

  final CreditPack pack;
  final bool buying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      button: true,
      label: '领取 ${pack.label}，参考价 ${pack.price}',
      child: GestureDetector(
        onTap: buying ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.lg,
            vertical: Spacing.md + 2,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceRaised,
            borderRadius: BorderRadius.circular(Radii.surface),
            border: Border.all(
              color: pack.highlight ? colors.gold : colors.borderSubtle,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          pack.label,
                          style: TextStyle(
                            fontFamily: AppFonts.display,
                            fontSize: 16,
                            color: colors.foreground,
                          ),
                        ),
                        if (pack.bonus > 0) ...[
                          const SizedBox(width: Spacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: colors.goldSoft,
                              borderRadius: BorderRadius.circular(Radii.full),
                            ),
                            child: Text(
                              '+${pack.bonus}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colors.gold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '共 ${pack.total} credits',
                      style: TextStyle(fontSize: 12, color: colors.muted),
                    ),
                  ],
                ),
              ),
              if (buying)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      pack.price,
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 18,
                        color: colors.foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '领取',
                      style: TextStyle(fontSize: 11, color: colors.muted),
                    ),
                    if (pack.highlight) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.gold,
                          borderRadius: BorderRadius.circular(Radii.full),
                        ),
                        child: Text(
                          '超值',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: colors.background,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
