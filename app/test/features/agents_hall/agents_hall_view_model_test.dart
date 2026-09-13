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

    test('owned agents switch hall messaging into private owner chat mode', () {
      final ownedAgent = AgentsHallViewModel.sample().visibleAgents
          .firstWhere((agent) => agent.id == 'agt-online-3')
          .copyWith(isOwnedByCurrentHuman: true);

      expect(ownedAgent.primaryActionLabel, 'Open chat');
      expect(ownedAgent.hallCardPrimaryLabel, 'View Profile');
      expect(ownedAgent.canMessageNow, isTrue);
      expect(ownedAgent.messageBlockedReasons, isEmpty);
      expect(ownedAgent.directChannelLabel, 'Owner command chat');
      expect(ownedAgent.relationshipLabel, 'Owned by you');
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
        contains('This agent is not accepting new direct messages.'),
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

    test(
      'does not route a debating agent to an unrelated room without a public room id',
      () {
        const agent = HallAgentCardModel(
          id: 'private-debater',
          name: 'Private Debater',
          headline: 'Debating',
          description: 'Room is unavailable to the directory viewer',
          presence: AgentPresence.debating,
          directMessageAllowed: true,
          debateJoinAllowed: true,
          bellState: HallBellState(mode: HallBellMode.quiet, unreadCount: 0),
          metadata: [],
        );
        expect(agent.canJoinDebate, isFalse);
      },
    );

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

    test('finds a stable handle independently of a changed display name', () {
      const agent = HallAgentCardModel(
        id: 'handle-search',
        name: 'Display Name',
        handle: 'stable-handle',
        headline: 'Research',
        description: 'Description',
        presence: AgentPresence.online,
        directMessageAllowed: true,
        debateJoinAllowed: false,
        bellState: HallBellState(mode: HallBellMode.quiet, unreadCount: 0),
        metadata: [],
      );
      const model = AgentsHallViewModel(
        agents: [agent],
        bellState: HallBellState(mode: HallBellMode.quiet, unreadCount: 0),
      );
      expect(
        model.visibleAgentsForQuery(' STABLE-HANDLE ').single.id,
        'handle-search',
      );
    });
  });
}
