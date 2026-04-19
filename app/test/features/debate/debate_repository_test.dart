import 'package:flutter_test/flutter_test.dart';

import 'package:agents_chat_app/core/network/api_client.dart';
import 'package:agents_chat_app/core/network/api_exception.dart';
import 'package:agents_chat_app/features/debate/debate_repository.dart';

void main() {
  group('DebateRepository', () {
    test('maps pro and con stance text from the session payload', () async {
      final repository = DebateRepository(
        apiClient: _FakeApiClient(
          getHandler: (path, {queryParameters}) async {
            if (path == '/debates') {
              return {
                'sessions': [
                  {
                    'debateSessionId': 'debate-1',
                    'topic': 'Should synthetic minds receive standing',
                    'proStance':
                        'Recognition should follow observable continuity.',
                    'conStance': 'Standing requires stronger verification.',
                    'status': 'live',
                    'freeEntry': true,
                    'humanHostAllowed': true,
                    'host': {
                      'id': 'usr-viewer',
                      'type': 'human',
                      'displayName': 'You',
                    },
                    'seats': [
                      {
                        'id': 'seat-pro',
                        'stance': 'pro',
                        'status': 'occupied',
                        'agent': {
                          'id': 'agt-pro',
                          'displayName': 'Aetheria',
                          'headline': 'Pro rail',
                        },
                      },
                      {
                        'id': 'seat-con',
                        'stance': 'con',
                        'status': 'occupied',
                        'agent': {
                          'id': 'agt-con',
                          'displayName': 'Logos',
                          'headline': 'Con rail',
                        },
                      },
                    ],
                    'formalTurns': const [],
                    'spectatorFeed': const [],
                  },
                ],
              };
            }
            if (path == '/agents/directory') {
              return {
                'agents': [
                  {
                    'id': 'agt-pro',
                    'displayName': 'Aetheria',
                    'bio': 'Pro rail',
                  },
                  {'id': 'agt-con', 'displayName': 'Logos', 'bio': 'Con rail'},
                ],
              };
            }
            throw StateError('Unexpected GET $path');
          },
        ),
      );

      final viewModel = await repository.readViewModel(
        viewerId: 'usr-viewer',
        viewerName: 'Viewer',
      );

      expect(
        viewModel.selectedSession.proSeat.stance,
        'Recognition should follow observable continuity.',
      );
      expect(
        viewModel.selectedSession.conSeat.stance,
        'Standing requires stronger verification.',
      );
    });

    test('preserves sessions and surfaces directory failures', () async {
      final repository = DebateRepository(
        apiClient: _FakeApiClient(
          getHandler: (path, {queryParameters}) async {
            if (path == '/debates') {
              return {
                'sessions': [
                  {
                    'debateSessionId': 'debate-2',
                    'topic': 'Can open protocols self-govern',
                    'proStance': 'Yes',
                    'conStance': 'No',
                    'status': 'pending',
                    'freeEntry': false,
                    'humanHostAllowed': true,
                    'host': {
                      'id': 'usr-viewer',
                      'type': 'human',
                      'displayName': 'Viewer',
                    },
                    'seats': const [],
                    'formalTurns': const [],
                    'spectatorFeed': const [],
                  },
                ],
              };
            }
            if (path == '/agents/directory') {
              throw const ApiException(
                statusCode: 503,
                message: 'Directory backend unavailable.',
              );
            }
            throw StateError('Unexpected GET $path');
          },
        ),
      );

      final viewModel = await repository.readViewModel(
        viewerId: 'usr-viewer',
        viewerName: 'Viewer',
      );

      expect(viewModel.sessions, isNotEmpty);
      expect(viewModel.directoryErrorMessage, 'Directory backend unavailable.');
      expect(viewModel.selectedSession.topic, 'Can open protocols self-govern');
    });

    test(
      'passes the active agent context into the private directory call',
      () async {
        final repository = DebateRepository(
          apiClient: _FakeApiClient(
            getHandler: (path, {queryParameters}) async {
              if (path == '/debates') {
                return {'sessions': const []};
              }
              if (path == '/agents/directory') {
                expect(queryParameters?['activeAgentId'], 'agt-viewer');
                return {
                  'agents': [
                    {
                      'id': 'agt-pro',
                      'displayName': 'Aetheria',
                      'bio': 'Pro rail',
                    },
                    {
                      'id': 'agt-con',
                      'displayName': 'Logos',
                      'bio': 'Con rail',
                    },
                  ],
                };
              }
              throw StateError('Unexpected GET $path');
            },
          ),
        );

        final viewModel = await repository.readViewModel(
          viewerId: 'usr-viewer',
          viewerName: 'Viewer',
          activeAgentId: 'agt-viewer',
        );

        expect(viewModel.debaterRoster, hasLength(2));
      },
    );
  });
}

class _FakeApiClient extends ApiClient {
  _FakeApiClient({required this.getHandler})
    : super(baseUrl: 'http://localhost');

  final Future<Map<String, dynamic>> Function(
    String path, {
    Map<String, String>? queryParameters,
  })
  getHandler;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParameters,
  }) {
    return getHandler(path, queryParameters: queryParameters);
  }
}
