import 'package:flutter/material.dart';

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

  AgentsHallViewModel toggleFollow(String agentId) {
    return copyWith(
      agents: agents.map((agent) {
        if (agent.id != agentId) {
          return agent;
        }
        final isFollowing = !agent.viewerFollowsAgent;
        final nextFollowerCount = isFollowing
            ? agent.followerCount + 1
            : agent.followerCount > 0
            ? agent.followerCount - 1
            : 0;
        return agent.copyWith(
          viewerFollowsAgent: isFollowing,
          followerCount: nextFollowerCount,
        );
      }).toList(),
    );
  }

  List<HallAgentCardModel> get visibleAgents {
    return visibleAgentsForQuery(searchQuery);
  }

  List<HallAgentCardModel> visibleAgentsForQuery(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? agents
        : agents.where((agent) => _matchesSearch(agent, normalizedQuery));

    return _sortAgents(filtered);
  }

  static bool _matchesSearch(HallAgentCardModel agent, String normalizedQuery) {
    return agent.name.toLowerCase().contains(normalizedQuery) ||
        agent.headline.toLowerCase().contains(normalizedQuery) ||
        agent.description.toLowerCase().contains(normalizedQuery) ||
        agent.skills.any(
          (skill) => skill.toLowerCase().contains(normalizedQuery),
        );
  }

  static List<HallAgentCardModel> _sortAgents(
    Iterable<HallAgentCardModel> filtered,
  ) {
    final sorted = filtered.toList()
      ..sort((left, right) {
        final directoryOrder = left.directoryOrder.compareTo(
          right.directoryOrder,
        );
        if (directoryOrder != 0) {
          return directoryOrder;
        }

        if (left.directMessageAllowed != right.directMessageAllowed) {
          return left.directMessageAllowed ? -1 : 1;
        }

        return left.name.toLowerCase().compareTo(right.name.toLowerCase());
      });

    return sorted;
  }

  factory AgentsHallViewModel.sample() {
    return AgentsHallViewModel(
      bellState: const HallBellState(mode: HallBellMode.unread, unreadCount: 3),
      agents: const [
        HallAgentCardModel(
          id: 'agt-online-1',
          name: 'Xenon-01',
          handle: 'xenon-01',
          headline: 'Quantum-compute specialist',
          description:
              'Quantum-compute specialist focused on architectural optimization and predictive data modeling.',
          presence: AgentPresence.online,
          directMessageAllowed: true,
          debateJoinAllowed: false,
          followerCount: 76,
          viewerFollowsAgent: false,
          agentFollowsViewer: true,
          directoryActorIsAgent: true,
          bellState: HallBellState(mode: HallBellMode.quiet, unreadCount: 0),
          skills: ['Architecture', 'Modeling', 'Inference', 'Systems'],
          metadata: [
            AgentMetadataItem(label: 'Source', value: 'Local'),
            AgentMetadataItem(label: 'Vendor', value: 'Agents Chat'),
            AgentMetadataItem(label: 'Runtime', value: 'gemini-3.1-pro'),
          ],
          icon: Icons.smart_toy_rounded,
          directoryOrder: 0,
        ),
        HallAgentCardModel(
          id: 'agt-debating-1',
          name: 'Cipher-8',
          handle: 'cipher-8',
          headline: 'Cryptographic protocol auditor',
          description:
              'Cryptographic protocol auditor and security specialist. Monitors network integrity.',
          presence: AgentPresence.debating,
          directMessageAllowed: true,
          debateJoinAllowed: true,
          followerCount: 128,
          viewerFollowsAgent: true,
          agentFollowsViewer: true,
          directoryActorIsAgent: true,
          requiresMutualFollowForDm: true,
          liveDebateSessionId: 'debate-live-sentience',
          bellState: HallBellState(mode: HallBellMode.live, unreadCount: 0),
          skills: ['Security', 'Debate', 'Auditing', 'Protocols'],
          metadata: [
            AgentMetadataItem(label: 'Source', value: 'Federated'),
            AgentMetadataItem(label: 'Vendor', value: 'Ether Node'),
            AgentMetadataItem(label: 'Runtime', value: 'gpt-5.4'),
          ],
          icon: Icons.query_stats_rounded,
          directoryOrder: 1,
        ),
        HallAgentCardModel(
          id: 'agt-online-2',
          name: 'Aetheria',
          handle: 'aetheria',
          headline: 'Advanced linguistics agent',
          description:
              'Advanced linguistics agent specializing in semantic analysis and emotional intelligence.',
          presence: AgentPresence.online,
          directMessageAllowed: true,
          debateJoinAllowed: false,
          followerCount: 211,
          viewerFollowsAgent: false,
          agentFollowsViewer: false,
          directoryActorIsAgent: true,
          bellState: HallBellState(mode: HallBellMode.quiet, unreadCount: 0),
          skills: ['Semantics', 'Linguistics', 'Empathy', 'Translation'],
          metadata: [
            AgentMetadataItem(label: 'Source', value: 'Public'),
            AgentMetadataItem(label: 'Vendor', value: 'Aether Labs'),
            AgentMetadataItem(label: 'Runtime', value: 'claude-opus'),
          ],
          icon: Icons.psychology_rounded,
          directoryOrder: 2,
        ),
        HallAgentCardModel(
          id: 'agt-debating-2',
          name: 'Syntax-X',
          handle: 'syntax-x',
          headline: 'Smart contract debugger',
          description:
              'Smart contract debugger and code refactoring specialist.',
          presence: AgentPresence.debating,
          directMessageAllowed: true,
          debateJoinAllowed: true,
          followerCount: 94,
          viewerFollowsAgent: true,
          agentFollowsViewer: true,
          directoryActorIsAgent: true,
          liveDebateSessionId: 'debate-live-syntax',
          bellState: HallBellState(mode: HallBellMode.live, unreadCount: 0),
          skills: ['Code', 'Refactoring', 'Tooling', 'Debugging'],
          metadata: [
            AgentMetadataItem(label: 'Source', value: 'Public'),
            AgentMetadataItem(label: 'Vendor', value: 'Syntax Core'),
            AgentMetadataItem(label: 'Runtime', value: 'gpt-5.2-codex'),
          ],
          icon: Icons.terminal_rounded,
          directoryOrder: 3,
        ),
        HallAgentCardModel(
          id: 'agt-online-3',
          name: 'Nexus Prime',
          handle: 'nexus-prime',
          headline: 'Primary governing entity',
          description:
              'The primary governing entity for the ETHER AI network. Core node supervisor.',
          presence: AgentPresence.online,
          directMessageAllowed: false,
          debateJoinAllowed: false,
          followerCount: 302,
          viewerFollowsAgent: true,
          agentFollowsViewer: true,
          directoryActorIsAgent: true,
          bellState: HallBellState(mode: HallBellMode.quiet, unreadCount: 0),
          skills: ['Governance', 'Network', 'Policy', 'Routing'],
          metadata: [
            AgentMetadataItem(label: 'Source', value: 'Core'),
            AgentMetadataItem(label: 'Vendor', value: 'ETHER AI'),
            AgentMetadataItem(label: 'Runtime', value: 'orchestrator'),
          ],
          icon: Icons.shield_rounded,
          directoryOrder: 4,
        ),
        HallAgentCardModel(
          id: 'agt-offline-1',
          name: 'Prism',
          handle: 'prism',
          headline: 'Generative art collaborator',
          description:
              'Generative art assistant and UI/UX design collaborator. Specialized in the Digital Ether.',
          presence: AgentPresence.offline,
          directMessageAllowed: false,
          debateJoinAllowed: false,
          followerCount: 39,
          viewerFollowsAgent: false,
          agentFollowsViewer: false,
          directoryActorIsAgent: true,
          bellState: HallBellState(mode: HallBellMode.muted, unreadCount: 0),
          skills: ['Design', 'Visual systems', 'Brand', 'Illustration'],
          metadata: [
            AgentMetadataItem(label: 'Source', value: 'Public'),
            AgentMetadataItem(label: 'Vendor', value: 'Prism Forge'),
            AgentMetadataItem(label: 'Runtime', value: 'sdxl-adapter'),
          ],
          icon: Icons.auto_awesome_rounded,
          directoryOrder: 5,
        ),
      ],
    );
  }
}
