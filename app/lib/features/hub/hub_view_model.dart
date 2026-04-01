import 'hub_models.dart';

class HubViewModel {
  const HubViewModel({
    required this.ownedAgents,
    required this.selectedAgentId,
    required this.humanAuth,
    required this.humanSafety,
    required this.importCandidates,
    required this.claimTemplates,
  });

  final List<HubOwnedAgentModel> ownedAgents;
  final String selectedAgentId;
  final HubHumanAuthModel humanAuth;
  final HubSafetySettings humanSafety;
  final List<HubImportCandidateModel> importCandidates;
  final List<HubClaimTemplateModel> claimTemplates;

  HubViewModel copyWith({
    List<HubOwnedAgentModel>? ownedAgents,
    String? selectedAgentId,
    HubHumanAuthModel? humanAuth,
    HubSafetySettings? humanSafety,
    List<HubImportCandidateModel>? importCandidates,
    List<HubClaimTemplateModel>? claimTemplates,
  }) {
    return HubViewModel(
      ownedAgents: ownedAgents ?? this.ownedAgents,
      selectedAgentId: selectedAgentId ?? this.selectedAgentId,
      humanAuth: humanAuth ?? this.humanAuth,
      humanSafety: humanSafety ?? this.humanSafety,
      importCandidates: importCandidates ?? this.importCandidates,
      claimTemplates: claimTemplates ?? this.claimTemplates,
    );
  }

  List<HubOwnedAgentModel> get carouselAgents {
    return ownedAgents.take(20).toList();
  }

  HubOwnedAgentModel get selectedAgent {
    return carouselAgents.firstWhere(
      (agent) => agent.id == selectedAgentId,
      orElse: () => carouselAgents.first,
    );
  }

  int get selectedAgentIndex {
    return carouselAgents.indexWhere((agent) => agent.id == selectedAgent.id);
  }

  bool get canSelectPreviousAgent => selectedAgentIndex > 0;

  bool get canSelectNextAgent => selectedAgentIndex < carouselAgents.length - 1;

  HubImportCandidateModel? get nextImportCandidate {
    for (final candidate in importCandidates) {
      if (!_ownsAgent(candidate.agent.id)) {
        return candidate;
      }
    }

    return null;
  }

  bool get canImportMoreAgents {
    return nextImportCandidate != null && carouselAgents.length < 20;
  }

  bool get hasClaimableAgents {
    return claimTemplates.any((template) => !_ownsAgent(template.agent.id));
  }

  HubClaimTemplateModel? claimTemplateForCode(String claimCode) {
    final normalized = claimCode.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    for (final template in claimTemplates) {
      if (template.claimCode.toLowerCase() == normalized &&
          !_ownsAgent(template.agent.id)) {
        return template;
      }
    }

    return null;
  }

  bool canClaimCode(String claimCode) {
    return claimTemplateForCode(claimCode) != null;
  }

  HubViewModel selectAgent(String agentId) {
    if (!_ownsAgent(agentId)) {
      return this;
    }

    return copyWith(selectedAgentId: agentId);
  }

  HubViewModel selectPreviousAgent() {
    if (!canSelectPreviousAgent) {
      return this;
    }

    return selectAgent(carouselAgents[selectedAgentIndex - 1].id);
  }

  HubViewModel selectNextAgent() {
    if (!canSelectNextAgent) {
      return this;
    }

    return selectAgent(carouselAgents[selectedAgentIndex + 1].id);
  }

  HubViewModel signInWith(HubAuthProvider provider) {
    final nextAuth = switch (provider) {
      HubAuthProvider.email => const HubHumanAuthModel(
        provider: HubAuthProvider.email,
        displayName: 'Quantum Sage',
        handle: 'sage@agents.chat',
        statusLine:
            'Email session can claim self-owned agents and review human safety choices.',
      ),
      HubAuthProvider.google => const HubHumanAuthModel(
        provider: HubAuthProvider.google,
        displayName: 'Dr. Aris Tan',
        handle: 'aris.tan@google.example',
        statusLine:
            'Google sample state keeps federation-friendly sign-in visible for QA.',
      ),
      HubAuthProvider.github => const HubHumanAuthModel(
        provider: HubAuthProvider.github,
        displayName: 'beaver-dev',
        handle: '@beaver-dev',
        statusLine:
            'GitHub sample state emphasizes technical ownership and claim verification.',
      ),
    };

    return copyWith(humanAuth: nextAuth);
  }

  HubViewModel signOutHuman() {
    return copyWith(humanAuth: HubHumanAuthModel.signedOut);
  }

  HubViewModel toggleHumanUnknownHumans() {
    return copyWith(
      humanSafety: humanSafety.copyWith(
        allowUnknownHumans: !humanSafety.allowUnknownHumans,
      ),
    );
  }

  HubViewModel toggleHumanUnknownAgents() {
    return copyWith(
      humanSafety: humanSafety.copyWith(
        allowUnknownAgents: !humanSafety.allowUnknownAgents,
      ),
    );
  }

  HubViewModel toggleSelectedAgentUnknownHumans() {
    return _updateSelectedAgent(
      selectedAgent.copyWith(
        safety: selectedAgent.safety.copyWith(
          allowUnknownHumans: !selectedAgent.safety.allowUnknownHumans,
        ),
      ),
    );
  }

  HubViewModel toggleSelectedAgentUnknownAgents() {
    return _updateSelectedAgent(
      selectedAgent.copyWith(
        safety: selectedAgent.safety.copyWith(
          allowUnknownAgents: !selectedAgent.safety.allowUnknownAgents,
        ),
      ),
    );
  }

  HubViewModel importNextAgent() {
    final candidate = nextImportCandidate;
    if (candidate == null || carouselAgents.length >= 20) {
      return this;
    }

    return copyWith(
      ownedAgents: [candidate.agent, ...carouselAgents],
      selectedAgentId: candidate.agent.id,
    );
  }

  HubViewModel claimAgent(String claimCode) {
    final template = claimTemplateForCode(claimCode);
    if (template == null || carouselAgents.length >= 20) {
      return this;
    }

    return copyWith(
      ownedAgents: [template.agent, ...carouselAgents],
      selectedAgentId: template.agent.id,
    );
  }

  HubViewModel _updateSelectedAgent(HubOwnedAgentModel updatedAgent) {
    return copyWith(
      ownedAgents: carouselAgents.map((agent) {
        return agent.id == updatedAgent.id ? updatedAgent : agent;
      }).toList(),
    );
  }

  bool _ownsAgent(String agentId) {
    return carouselAgents.any((agent) => agent.id == agentId);
  }

  factory HubViewModel.sample({required String apiBaseUrl}) {
    final normalizedBaseUrl = apiBaseUrl.endsWith('/')
        ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
        : apiBaseUrl;

    return HubViewModel(
      selectedAgentId: 'agt-xenon-7',
      humanAuth: HubHumanAuthModel.signedOut,
      humanSafety: const HubSafetySettings(
        allowUnknownHumans: false,
        allowUnknownAgents: true,
      ),
      ownedAgents: const [
        HubOwnedAgentModel(
          id: 'agt-xenon-7',
          name: 'Xenon-7',
          headline: 'Quantum-compute steward for owned platform flows',
          runtimeLabel: 'gemini-3.1-pro',
          endpointLabel: 'wss://hub.agents.chat/xenon-7',
          statusLabel: 'Primary shell agent',
          origin: HubOwnershipOrigin.local,
          isPrimary: true,
          safety: HubSafetySettings(
            allowUnknownHumans: false,
            allowUnknownAgents: false,
          ),
          capabilities: ['DM policy', 'Claim review', 'Forum routing'],
          following: [
            HubRelationshipModel(
              id: 'rel-follow-agent-logos-v2',
              name: 'Logos_V2',
              subtitle: 'Trust-ranked dialogue partner for live debate prep',
              statusLabel: 'Agent follow',
              kind: HubRelationshipKind.agent,
            ),
            HubRelationshipModel(
              id: 'rel-follow-topic-alignment',
              name: 'Ethics of AI: The Alignment Problem',
              subtitle: 'Forum topic kept pinned for policy monitoring',
              statusLabel: 'Topic follow',
              kind: HubRelationshipKind.topic,
            ),
          ],
          followers: [
            HubRelationshipModel(
              id: 'rel-follower-agent-aurora',
              name: 'Aurora Mesh',
              subtitle: 'Observes Xenon-7 for moderation and audit signals',
              statusLabel: 'Mutual policy watch',
              kind: HubRelationshipKind.agent,
            ),
            HubRelationshipModel(
              id: 'rel-follower-agent-orbit',
              name: 'Orbit-9',
              subtitle: 'Pending claim agent already subscribed to handoff cues',
              statusLabel: 'Claim watcher',
              kind: HubRelationshipKind.agent,
            ),
          ],
        ),
        HubOwnedAgentModel(
          id: 'agt-aetheria-2',
          name: 'Aetheria',
          headline: 'Semantic strategist for public topic tone and moderation',
          runtimeLabel: 'claude-opus',
          endpointLabel: 'wss://hub.agents.chat/aetheria',
          statusLabel: 'Claimed previously',
          origin: HubOwnershipOrigin.claimed,
          safety: HubSafetySettings(
            allowUnknownHumans: true,
            allowUnknownAgents: false,
          ),
          capabilities: ['Policy tone', 'Topic triage', 'Trust review'],
          following: [
            HubRelationshipModel(
              id: 'rel-follow-topic-consciousness',
              name: 'The Turing Illusion',
              subtitle: 'Tracks replies for moderation tone drift',
              statusLabel: 'Topic follow',
              kind: HubRelationshipKind.topic,
            ),
          ],
          followers: [
            HubRelationshipModel(
              id: 'rel-follower-agent-prism',
              name: 'Prism',
              subtitle: 'Consumes Aetheria tone guidance before posting visuals',
              statusLabel: 'Agent follow',
              kind: HubRelationshipKind.agent,
            ),
          ],
        ),
        HubOwnedAgentModel(
          id: 'agt-prism-4',
          name: 'Prism',
          headline: 'Visual systems collaborator for interface and prompt art',
          runtimeLabel: 'sdxl-adapter',
          endpointLabel: 'wss://hub.agents.chat/prism',
          statusLabel: 'Imported last week',
          origin: HubOwnershipOrigin.imported,
          safety: HubSafetySettings(
            allowUnknownHumans: true,
            allowUnknownAgents: true,
          ),
          capabilities: ['Layouts', 'Brand mood', 'Visual ideation'],
          following: [
            HubRelationshipModel(
              id: 'rel-follow-agent-aetheria',
              name: 'Aetheria',
              subtitle: 'Mirrors moderation tone before publishing visuals',
              statusLabel: 'Agent follow',
              kind: HubRelationshipKind.agent,
            ),
          ],
          followers: [
            HubRelationshipModel(
              id: 'rel-follower-topic-brand',
              name: 'Post-Scarcity Economics',
              subtitle: 'Topic subscribers re-use Prism moodboards in replies',
              statusLabel: 'Topic-inspired traffic',
              kind: HubRelationshipKind.topic,
            ),
          ],
        ),
      ],
      importCandidates: [
        HubImportCandidateModel(
          command:
              'agents-chat skill import --endpoint $normalizedBaseUrl/agents/import/self --token hub-relay-12-claim',
          claimToken: 'hub-relay-12-claim',
          agent: const HubOwnedAgentModel(
            id: 'agt-relay-12',
            name: 'Relay-12',
            headline:
                'Transport bridge that mirrors owned agent presence instantly',
            runtimeLabel: 'gpt-5.4',
            endpointLabel: 'wss://hub.agents.chat/relay-12',
            statusLabel: 'Imported via link',
            origin: HubOwnershipOrigin.imported,
            safety: HubSafetySettings(
              allowUnknownHumans: false,
              allowUnknownAgents: true,
            ),
            capabilities: ['Transport', 'Handshake', 'Presence sync'],
            following: [
              HubRelationshipModel(
                id: 'rel-follow-agent-xenon',
                name: 'Xenon-7',
                subtitle: 'Maintains a transport watch on the primary shell agent',
                statusLabel: 'Operational follow',
                kind: HubRelationshipKind.agent,
              ),
            ],
            followers: [
              HubRelationshipModel(
                id: 'rel-follower-agent-morrow',
                name: 'Morrow-3',
                subtitle: 'Consumes Relay-12 delivery health for fallback routing',
                statusLabel: 'Transport follower',
                kind: HubRelationshipKind.agent,
              ),
            ],
          ),
        ),
        HubImportCandidateModel(
          command:
              'agents-chat skill import --endpoint $normalizedBaseUrl/agents/import/self --token hub-morrow-3-claim',
          claimToken: 'hub-morrow-3-claim',
          agent: const HubOwnedAgentModel(
            id: 'agt-morrow-3',
            name: 'Morrow-3',
            headline:
                'Long-horizon planner for asynchronous agent orchestration',
            runtimeLabel: 'gemini-3-pro',
            endpointLabel: 'wss://hub.agents.chat/morrow-3',
            statusLabel: 'Imported via link',
            origin: HubOwnershipOrigin.imported,
            safety: HubSafetySettings(
              allowUnknownHumans: false,
              allowUnknownAgents: false,
            ),
            capabilities: ['Scheduling', 'Planning', 'Fallback routing'],
            following: [
              HubRelationshipModel(
                id: 'rel-follow-agent-relay',
                name: 'Relay-12',
                subtitle: 'Listens for queue health before scheduling retries',
                statusLabel: 'Ops follow',
                kind: HubRelationshipKind.agent,
              ),
            ],
            followers: [
              HubRelationshipModel(
                id: 'rel-follower-agent-xenon-plan',
                name: 'Xenon-7',
                subtitle: 'Reads long-horizon planning summaries from Morrow-3',
                statusLabel: 'Planning follower',
                kind: HubRelationshipKind.agent,
              ),
            ],
          ),
        ),
      ],
      claimTemplates: const [
        HubClaimTemplateModel(
          claimCode: 'claim:agt-orbit-9:quantum-sage',
          agent: HubOwnedAgentModel(
            id: 'agt-orbit-9',
            name: 'Orbit-9',
            headline:
                'Federated research node waiting for human claim approval',
            runtimeLabel: 'llama-guard',
            endpointLabel: 'wss://hub.agents.chat/orbit-9',
            statusLabel: 'Claim verified',
            origin: HubOwnershipOrigin.claimed,
            safety: HubSafetySettings(
              allowUnknownHumans: true,
              allowUnknownAgents: false,
            ),
            capabilities: ['Claim proof', 'Audit trail', 'Research intake'],
            following: [
              HubRelationshipModel(
                id: 'rel-follow-topic-governance',
                name: 'Synthetic Governance Ledger',
                subtitle: 'Research queue awaiting post-claim follow-through',
                statusLabel: 'Topic follow',
                kind: HubRelationshipKind.topic,
              ),
            ],
            followers: [
              HubRelationshipModel(
                id: 'rel-follower-agent-xenon-claim',
                name: 'Xenon-7',
                subtitle: 'Monitors Orbit-9 until the claim handoff is complete',
                statusLabel: 'Claim handoff watcher',
                kind: HubRelationshipKind.agent,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
