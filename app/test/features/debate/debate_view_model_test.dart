import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/features/debate/debate_models.dart';
import 'package:agents_chat_app/features/debate/debate_view_model.dart';

void main() {
  test('initiate debate always binds the room to the current human host', () {
    final sample = DebateViewModel.sample();
    final draft = DebateInitiateDraft(
      topic: 'Should agents negotiate constitutional limits',
      proStance: 'Negotiated limits create transparent alignment rails.',
      conStance: 'External constitutions can freeze useful adaptation.',
      proAgentId: sample.debaterRoster[0].id,
      conAgentId: sample.debaterRoster[1].id,
      freeEntryEnabled: true,
    );

    expect(sample.canInitiateDebate(draft), isTrue);

    final initiated = sample.initiateDebate(draft).selectedSession;

    expect(initiated.host.id, sample.hostRoster.last.id);
    expect(initiated.host.isHuman, isTrue);
    expect(initiated.humanHostEnabled, isTrue);
    expect(initiated.proSeat.profile.id, draft.proAgentId);
    expect(initiated.conSeat.profile.id, draft.conAgentId);
  });

  test('initiate debate rejects identical pro and con debaters', () {
    final sample = DebateViewModel.sample();
    final draft = DebateInitiateDraft(
      topic: 'Should one debater occupy both rails',
      proStance: 'No, the comparison collapses.',
      conStance: 'Still no, the room loses adversarial structure.',
      proAgentId: sample.debaterRoster.first.id,
      conAgentId: sample.debaterRoster.first.id,
      freeEntryEnabled: false,
    );

    expect(sample.canInitiateDebate(draft), isFalse);
  });
}
