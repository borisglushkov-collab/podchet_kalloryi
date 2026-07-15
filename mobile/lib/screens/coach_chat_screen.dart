import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/nutrition_calculator.dart';
import '../services/weight_analysis.dart';
import '../theme/app_theme.dart';
import '../utils/api_error_utils.dart';

class CoachChatScreen extends ConsumerStatefulWidget {
  final String date;
  final MealType mealType;

  const CoachChatScreen({
    super.key,
    required this.date,
    required this.mealType,
  });

  @override
  ConsumerState<CoachChatScreen> createState() => _CoachChatScreenState();
}

class _ChatBubble {
  final String role; // user | assistant
  final String content;

  const _ChatBubble({required this.role, required this.content});
}

class _CoachChatScreenState extends ConsumerState<CoachChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatBubble> _messages = [
    const _ChatBubble(
      role: 'assistant',
      content:
          'Привет! Я коуч по питанию. Спросите, что съесть, как закрыть белок '
          'или что делать, если осталось мало калорий.',
    ),
  ];
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _messages.add(_ChatBubble(role: 'user', content: text));
      _sending = true;
      _controller.clear();
    });
    _scrollToEnd();

    try {
      final profile = await ref.read(profileProvider.future);
      final targets = await ref.read(dailyTargetsProvider.future);
      final consumed = await ref.read(dailyTotalsProvider(widget.date).future);
      final entries = await ref.read(dailyEntriesProvider(widget.date).future);
      final weightEntries = await ref.read(weightEntriesProvider.future);
      if (profile == null || targets == null) {
        throw Exception('Заполните профиль');
      }

      final prefs = profile.preferences
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final mealsConsumed = NutritionCalculator.consumedByMeal(entries);
      final mealConsumed =
          NutritionCalculator.consumedForMeal(entries, widget.mealType);
      final weightAnalysis =
          WeightAnalysis.fromProfileAndEntries(profile, weightEntries);

      // Previous turns only — current message is sent separately.
      final historyForApi = <Map<String, String>>[];
      for (var i = 0; i < _messages.length - 1; i++) {
        final m = _messages[i];
        if (m.role == 'assistant' && m.content.startsWith('Привет! Я коуч')) {
          continue;
        }
        historyForApi.add({'role': m.role, 'content': m.content});
      }

      final reply = await ref.read(apiServiceProvider).coachChat(
            message: text,
            history: historyForApi,
            mealType: widget.mealType,
            consumed: consumed,
            targets: targets,
            mealConsumed: mealConsumed,
            mealsConsumed: mealsConsumed,
            preferences: prefs,
            profile: profile,
            weightAnalysis: weightAnalysis,
          );

      if (!mounted) return;
      setState(() {
        _messages.add(_ChatBubble(
          role: 'assistant',
          content: reply.isEmpty
              ? 'Не удалось получить ответ. Попробуйте ещё раз.'
              : reply,
        ));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatBubble(
          role: 'assistant',
          content: 'Ошибка: ${formatApiError(e)}',
        ));
      });
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Чат с коучем · ${widget.mealType.label}'),
        backgroundColor: AppColors.background,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _messages.length + (_sending ? 1 : 0),
              itemBuilder: (context, index) {
                if (_sending && index == _messages.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: _TypingBubble(),
                    ),
                  );
                }
                final msg = _messages[index];
                final isUser = msg.role == 'user';
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.82,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppColors.primary.withValues(alpha: 0.18)
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      msg.content,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            height: 1.35,
                          ),
                    ),
                  ),
                );
              },
            ),
          ),
          Material(
            color: AppColors.surface,
            elevation: 2,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                10,
                8,
                10 + (bottomInset > 0 ? bottomInset : safeBottom),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Спросите коуча…',
                        filled: true,
                        fillColor: AppColors.surfaceMuted,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Коуч думает…',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                ),
          ),
        ],
      ),
    );
  }
}
