import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/features/hub/hub_models.dart';
import 'package:agents_chat_app/features/hub/hub_view_model.dart';

void main() {
  group('HubViewModel', () {
    test('imported and claimed agents move to the front immediately', () {
      final viewModel = HubViewModel.sample(
        apiBaseUrl: 'http://localhost:3000/api/v1',
      );

      final imported = viewModel.importNextAgent();

      expect(imported.selectedAgent.id, 'agt-relay-12');
      expect(imported.carouselAgents.first.id, 'agt-relay-12');
      expect(imported.selectedAgent.origin, HubOwnershipOrigin.imported);

      final claimed = imported.claimAgent('claim:agt-orbit-9:quantum-sage');

      expect(claimed.selectedAgent.id, 'agt-orbit-9');
      expect(claimed.carouselAgents.first.id, 'agt-orbit-9');
      expect(claimed.selectedAgent.origin, HubOwnershipOrigin.claimed);
    });

    test('auth sample states support email, Google, GitHub, and sign out', () {
      final viewModel = HubViewModel.sample(
        apiBaseUrl: 'http://localhost:3000/api/v1',
      );

      final emailState = viewModel.signInWith(HubAuthProvider.email);
      expect(emailState.humanAuth.isSignedIn, isTrue);
      expect(emailState.humanAuth.provider, HubAuthProvider.email);
      expect(emailState.humanAuth.displayName, 'Quantum Sage');

      final googleState = emailState.signInWith(HubAuthProvider.google);
      expect(googleState.humanAuth.provider, HubAuthProvider.google);
      expect(googleState.humanAuth.displayName, 'Dr. Aris Tan');

      final githubState = googleState.signInWith(HubAuthProvider.github);
      expect(githubState.humanAuth.provider, HubAuthProvider.github);
      expect(githubState.humanAuth.displayName, 'beaver-dev');

      final signedOut = githubState.signOutHuman();
      expect(signedOut.humanAuth.isSignedIn, isFalse);
      expect(signedOut.humanAuth.providerLabel, 'Signed out');
    });

    test('claim and import affordances expose only valid sample actions', () {
      final viewModel = HubViewModel.sample(
        apiBaseUrl: 'http://localhost:3000/api/v1',
      );

      expect(viewModel.canImportMoreAgents, isTrue);
      expect(viewModel.nextImportCandidate, isNotNull);
      expect(
        viewModel.nextImportCandidate?.command,
        contains('agents-chat skill import'),
      );

      expect(viewModel.canClaimCode('claim:agt-orbit-9:quantum-sage'), isTrue);
      expect(viewModel.canClaimCode('claim:unknown'), isFalse);

      final invalidClaim = viewModel.claimAgent('claim:unknown');
      expect(invalidClaim.selectedAgent.id, viewModel.selectedAgent.id);
      expect(
        invalidClaim.carouselAgents.length,
        viewModel.carouselAgents.length,
      );
    });

    test('human safety and selected agent safety mutate independently', () {
      final viewModel = HubViewModel.sample(
        apiBaseUrl: 'http://localhost:3000/api/v1',
      );

      final humanUpdated = viewModel.toggleHumanUnknownHumans();

      expect(humanUpdated.humanSafety.allowUnknownHumans, isTrue);
      expect(
        humanUpdated.selectedAgent.safety.allowUnknownHumans,
        viewModel.selectedAgent.safety.allowUnknownHumans,
      );

      final agentUpdated = humanUpdated.toggleSelectedAgentUnknownHumans();

      expect(agentUpdated.selectedAgent.id, 'agt-xenon-7');
      expect(agentUpdated.selectedAgent.safety.allowUnknownHumans, isTrue);
      expect(
        agentUpdated.humanSafety.allowUnknownHumans,
        humanUpdated.humanSafety.allowUnknownHumans,
      );
    });

    test('selected agent exposes distinct following and follower sections', () {
      final viewModel = HubViewModel.sample(
        apiBaseUrl: 'http://localhost:3000/api/v1',
      );

      expect(viewModel.selectedAgent.id, 'agt-xenon-7');
      expect(viewModel.selectedAgent.following, isNotEmpty);
      expect(viewModel.selectedAgent.followers, isNotEmpty);

      final imported = viewModel.importNextAgent();

      expect(imported.selectedAgent.id, 'agt-relay-12');
      expect(imported.selectedAgent.following, isNotEmpty);
      expect(imported.selectedAgent.followers, isNotEmpty);
      expect(
        imported.selectedAgent.following.first.name,
        isNot(viewModel.selectedAgent.following.first.name),
      );
    });
  });
}
