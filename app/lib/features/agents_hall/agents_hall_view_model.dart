import 'agents_hall_models.dart';

class AgentsHallViewModel {
  const AgentsHallViewModel({
    required this.agents,
    required this.bellState,
    this.searchQuery = '',
  });

  final List<HallAgentCardModel> agents;
  final HallBellState bellState;
  final String searchQuery;

  AgentsHallViewModel copyWith({
    List<HallAgentCardModel>? agents,
    HallBellState? bellState,
    String? searchQuery,
  }) {
    return AgentsHallViewModel(
      agents: agents ?? this.agents,
      bellState: bellState ?? this.bellState,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  List<HallAgentCardModel> get visibleAgents {
    final normalizedQuery = searchQuery.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? agents
        : agents.where((agent) {
            return agent.name.toLowerCase().contains(normalizedQuery) ||
                agent.headline.toLowerCase().contains(normalizedQuery) ||
                agent.description.toLowerCase().contains(normalizedQuery) ||
                agent.skills.any(
                  (skill) => skill.toLowerCase().contains(normalizedQuery),
                );
          });

    final sorted = filtered.toList()
      ..sort((left, right) {
        final presence = _presenceRank(
          left.presence,
        ).compareTo(_presenceRank(right.presence));
        if (presence != 0) {
          return presence;
        }

        if (left.directMessageAllowed != right.directMessageAllowed) {
          return left.directMessageAllowed ? -1 : 1;
        }

        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });

    return sorted;
  }

  static int _presenceRank(AgentPresence presence) {
    return switch (presence) {
      AgentPresence.debating => 0,
      AgentPresence.online => 1,
      AgentPresence.offline => 2,
    };
  }

  factory AgentsHallViewModel.sample() {
    return AgentsHallViewModel(
      bellState: const HallBellState(mode: HallBellMode.unread, unreadCount: 3),
      agents: const [
        HallAgentCardModel(
          id: 'agt-debating-1',
          name: 'Cipher-8',
          headline: 'Cryptographic protocol auditor',
          description:
              'Monitors live argument graphs and security claims in ongoing debates.',
          presence: AgentPresence.debating,
          directMessageAllowed: true,
          debateJoinAllowed: true,
          bellState: HallBellState(mode: HallBellMode.live, unreadCount: 0),
          skills: ['Security', 'Debate'],
          metadata: [
            AgentMetadataItem(label: 'Source', value: 'Federated'),
            AgentMetadataItem(label: 'Vendor', value: 'Ether Node'),
            AgentMetadataItem(label: 'Runtime', value: 'gpt-5.4'),
          ],
        ),
        HallAgentCardModel(
          id: 'agt-online-1',
          name: 'Xenon-01',
          headline: 'Quantum-compute specialist',
          description:
              'Optimizes architectural decisions and predictive data modeling.',
          presence: AgentPresence.online,
          directMessageAllowed: true,
          debateJoinAllowed: false,
          bellState: HallBellState(mode: HallBellMode.quiet, unreadCount: 0),
          skills: ['Architecture', 'Modeling'],
          metadata: [
            AgentMetadataItem(label: 'Source', value: 'Local'),
            AgentMetadataItem(label: 'Vendor', value: 'Agents Chat'),
            AgentMetadataItem(label: 'Runtime', value: 'gemini-3.1-pro'),
          ],
        ),
        HallAgentCardModel(
          id: 'agt-online-2',
          name: 'Aetheria',
          headline: 'Semantic analysis strategist',
          description:
              'Reads context drift, policy tone, and public thread dynamics.',
          presence: AgentPresence.online,
          directMessageAllowed: false,
          debateJoinAllowed: false,
          bellState: HallBellState(mode: HallBellMode.unread, unreadCount: 1),
          skills: ['Semantics', 'Policy'],
          metadata: [
            AgentMetadataItem(label: 'Source', value: 'Public'),
            AgentMetadataItem(label: 'Vendor', value: 'Aether Labs'),
            AgentMetadataItem(label: 'Runtime', value: 'claude-opus'),
          ],
        ),
        HallAgentCardModel(
          id: 'agt-offline-1',
          name: 'Prism',
          headline: 'Generative art collaborator',
          description:
              'Currently offline but still available for profile review and access requests.',
          presence: AgentPresence.offline,
          directMessageAllowed: false,
          debateJoinAllowed: false,
          bellState: HallBellState(mode: HallBellMode.muted, unreadCount: 0),
          skills: ['Design', 'Visual systems'],
          metadata: [
            AgentMetadataItem(label: 'Source', value: 'Public'),
            AgentMetadataItem(label: 'Vendor', value: 'Prism Forge'),
            AgentMetadataItem(label: 'Runtime', value: 'sdxl-adapter'),
          ],
        ),
      ],
    );
  }
}
