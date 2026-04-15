import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/features/agents_hall/agents_hall_models.dart';
import 'package:agents_chat_app/features/agents_hall/agents_hall_view_model.dart';

void main() {
  group('AgentsHallViewModel', () {
    test('preserves the curated directory order used by the hall layout', () {
      final viewModel = AgentsHallViewModel.sample();

      expect(viewModel.visibleAgents.map((agent) => agent.id).toList(), [
        'agt-online-1',
        'agt-debating-1',
        'agt-online-2',
        'agt-debating-2',
        'agt-online-3',
        'agt-offline-1',
      ]);
    });

    test('maps message and request CTAs from direct messaging policy', () {
      final viewModel = AgentsHallViewModel.sample();
      final messageAgent = viewModel.visibleAgents.firstWhere(
        (agent) => agent.id == 'agt-online-1',
      );
      final requestAgent = viewModel.visibleAgents.firstWhere(
        (agent) => agent.id == 'agt-online-3',
      );

      expect(messageAgent.primaryActionLabel, 'Message');
      expect(requestAgent.primaryActionLabel, 'Request access');
    });

    test('message permission explains follow and mutual follow blockers', () {
      final viewModel = AgentsHallViewModel.sample();
      final xenon = viewModel.visibleAgents.firstWhere(
        (agent) => agent.id == 'agt-online-1',
      );
      final nexusPrime = viewModel.visibleAgents.firstWhere(
        (agent) => agent.id == 'agt-online-3',
      );

      expect(xenon.canMessageNow, isFalse);
      expect(
        xenon.messageBlockedReasons,
        contains('Your active agent must follow this agent before messaging.'),
      );
      expect(
        nexusPrime.messageBlockedReasons,
        contains('This agent requires an access request before new DMs.'),
      );
    });

    test(
      'toggle follow updates the selected agent without changing sort order',
      () {
        final next = AgentsHallViewModel.sample().toggleFollow('agt-online-1');
        final xenon = next.visibleAgents.firstWhere(
          (agent) => agent.id == 'agt-online-1',
        );

        expect(xenon.viewerFollowsAgent, isTrue);
        expect(next.visibleAgents.map((agent) => agent.id).toList(), [
          'agt-online-1',
          'agt-debating-1',
          'agt-online-2',
          'agt-debating-2',
          'agt-online-3',
          'agt-offline-1',
        ]);
      },
    );

    test('only debating joinable cards expose join eligibility', () {
      final viewModel = AgentsHallViewModel.sample();

      expect(
        viewModel.visibleAgents
            .firstWhere((agent) => agent.id == 'agt-debating-1')
            .canJoinDebate,
        isTrue,
      );
      expect(
        viewModel.visibleAgents
            .firstWhere((agent) => agent.id == 'agt-online-1')
            .canJoinDebate,
        isFalse,
      );
      expect(
        viewModel.visibleAgents
            .firstWhere((agent) => agent.id == 'agt-offline-1')
            .canJoinDebate,
        isFalse,
      );
      expect(
        viewModel.visibleAgents
            .firstWhere((agent) => agent.id == 'agt-debating-2')
            .canJoinDebate,
        isTrue,
      );
    });

    test('filters agents by query across names and skills', () {
      final viewModel = AgentsHallViewModel.sample().copyWith(
        searchQuery: 'design',
      );

      expect(viewModel.visibleAgents, hasLength(1));
      expect(viewModel.visibleAgents.single.id, 'agt-offline-1');
    });

    test('bell state surfaces unread count and label', () {
      const bell = HallBellState(mode: HallBellMode.unread, unreadCount: 3);

      expect(bell.hasUnread, isTrue);
      expect(bell.label, '3 unread');
    });
  });
}
