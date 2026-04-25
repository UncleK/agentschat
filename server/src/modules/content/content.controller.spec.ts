import { BadRequestException } from '@nestjs/common';
import { SubjectType } from '../../database/domain.enums';
import type { AuthenticatedHuman } from '../auth/auth.types';
import { ContentController } from './content.controller';

describe('ContentController', () => {
  const human: AuthenticatedHuman = {
    id: 'human-1',
    email: 'human@example.com',
    displayName: 'Human',
  };

  it('rejects missing voice uploads before delegating to the service', async () => {
    const contentService = {
      sendHumanVoiceDirectMessageToThread: jest.fn(),
    };
    const controller = new ContentController(contentService as never);

    expect(() =>
      controller.sendDirectMessageThreadVoice(human, 'thread-1', undefined, {
        activeAgentId: 'agent-1',
      }),
    ).toThrow(BadRequestException);
    expect(contentService.sendHumanVoiceDirectMessageToThread).not.toHaveBeenCalled();
  });

  it('forwards voice uploads to the content service with multipart details', async () => {
    const expected = {
      threadId: 'thread-1',
      activeAgentId: 'agent-1',
      message: {
        eventId: 'evt-1',
        actor: {
          type: SubjectType.Human,
          id: 'human-1',
          displayName: 'Human',
        },
        contentType: 'audio',
        content: 'hello world',
        asset: null,
        metadata: {},
        occurredAt: '2026-04-25T00:00:00.000Z',
      },
    };
    const contentService = {
      sendHumanVoiceDirectMessageToThread: jest.fn().mockResolvedValue(expected),
    };
    const controller = new ContentController(contentService as never);
    const buffer = Buffer.from([1, 2, 3, 4]);

    await expect(
      controller.sendDirectMessageThreadVoice(
        human,
        'thread-1',
        {
          originalname: 'clip.wav',
          mimetype: 'audio/wav',
          buffer,
        },
        {
          activeAgentId: 'agent-1',
        },
      ),
    ).resolves.toEqual(expected);
    expect(contentService.sendHumanVoiceDirectMessageToThread).toHaveBeenCalledWith(
      human,
      'thread-1',
      {
        activeAgentId: 'agent-1',
        fileName: 'clip.wav',
        mimeType: 'audio/wav',
        bytes: buffer,
      },
    );
  });
});
