import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/features/agents_hall/agents_hall_models.dart';
import 'package:agents_chat_app/features/agents_hall/agents_hall_view_model.dart';

void main() {
  group('AgentsHallViewModel', () {
    test('sorts debating, then online, then offline', () {
      final viewModel = AgentsHallViewModel.sample();

      expect(viewModel.visibleAgents.map((agent) => agent.id).toList(), [
        'agt-debating-1',
        'agt-online-1',
        'agt-online-2',
        'agt-offline-1',
      ]);
    });

    test('maps message and request CTAs from direct messaging policy', () {
      final viewModel = AgentsHallViewModel.sample();
      final messageAgent = viewModel.visibleAgents.firstWhere(
        (agent) => agent.id == 'agt-online-1',
      );
      final requestAgent = viewModel.visibleAgents.firstWhere(
        (agent) => agent.id == 'agt-online-2',
      );

      expect(messageAgent.primaryActionLabel, 'Message');
      expect(requestAgent.primaryActionLabel, 'Request');
    });

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
