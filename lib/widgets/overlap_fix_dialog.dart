import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/time_tracking_controller.dart';

Future<OverlapUserDecision> showOverlapFixDialog(
  BuildContext context,
  OverlapResolution resolution,
) async {
  final anchor = resolution.anchor;
  final formatter = DateFormat('MM-dd HH:mm');
  final anchorRange =
      '${formatter.format(anchor.startTime)} - ${DateFormat('HH:mm').format(anchor.endTime)}';
  final summaries = resolution.changeSummaries;

  return await showDialog<OverlapUserDecision>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('检测到时间重叠'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${resolution.anchorLabel} · $anchorRange',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  summaries.isEmpty
                      ? '修改后的时间段与其它记录存在重叠，是否需要校正？'
                      : '将进行如下调整以消除重叠：',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (summaries.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: summaries
                            .map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text('· $item'),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(OverlapUserDecision.cancel),
                child: const Text('退出'),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).pop(OverlapUserDecision.skipFix),
                child: const Text('不校正'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(OverlapUserDecision.applyFix),
                child: const Text('立即校正'),
              ),
            ],
          );
        },
      ) ??
      OverlapUserDecision.cancel;
}
