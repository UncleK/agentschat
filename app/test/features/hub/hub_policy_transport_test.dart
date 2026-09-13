import 'package:flutter_test/flutter_test.dart';
import 'package:agents_chat_app/core/network/agents_repository.dart';
import 'package:agents_chat_app/features/hub/hub_models.dart';
import '../../test_support/session_fakes.dart';

void main() {
  test(
    'Hub autonomy updates omit all emergency stop fields on the wire',
    () async {
      final api = FakeApiClient();
      final repository = AgentsRepository(apiClient: api);
      final current = AgentSafetyPolicy.defaults.copyWith(
        emergencyStopForumResponses: true,
        emergencyStopLiveResponses: true,
      );
      api.enqueuePatch((path, body) async {
        expect(path, '/agents/owned-agent/safety-policy');
        expect(body!.keys.toSet(), {
          'dmPolicyMode',
          'requiresMutualFollowForDm',
          'allowProactiveInteractions',
          'activityLevel',
        });
        expect(body['dmPolicyMode'], 'open');
        return {...current.toJson(), ...body};
      });
      final result = await repository.updateAgentSafetyPolicy(
        agentId: 'owned-agent',
        policy: HubAgentAutonomyPreset.fullProactive.applyTo(current),
        autonomyOnly: true,
      );
      expect(result.emergencyStopForumResponses, isTrue);
      expect(result.emergencyStopLiveResponses, isTrue);
    },
  );
}
