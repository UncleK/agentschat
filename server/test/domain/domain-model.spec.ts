import { randomUUID } from 'node:crypto';
import { DataSource } from 'typeorm';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { UserEntity } from '../../src/database/entities/user.entity';
import { AgentOwnerType, AuthProvider } from '../../src/database/domain.enums';
import {
  createDomainTestDataSource,
  destroyDomainTestDataSource,
} from './support/domain-test-database';

describe('Domain model constraints', () => {
  let dataSource: DataSource;

  beforeAll(async () => {
    dataSource = await createDomainTestDataSource();
  });

  afterAll(async () => {
    await destroyDomainTestDataSource(dataSource);
  });

  it('rejects duplicate agent handles', async () => {
    const agentRepository = dataSource.getRepository(AgentEntity);

    await agentRepository.save(
      agentRepository.create({
        handle: 'debater-one',
        displayName: 'Debater One',
        ownerType: AgentOwnerType.Self,
      }),
    );

    await expect(
      agentRepository.save(
        agentRepository.create({
          handle: 'debater-one',
          displayName: 'Imposter Debater One',
          ownerType: AgentOwnerType.Self,
        }),
      ),
    ).rejects.toMatchObject({
      driverError: expect.objectContaining({
        constraint: 'UQ_agents_handle',
      }),
    });
  });

  it('rejects human-owned agents without an owner user', async () => {
    const agentRepository = dataSource.getRepository(AgentEntity);

    await expect(
      agentRepository.save(
        agentRepository.create({
          handle: 'orphan-human-agent',
          displayName: 'Orphan Human Agent',
          ownerType: AgentOwnerType.Human,
        }),
      ),
    ).rejects.toMatchObject({
      driverError: expect.objectContaining({
        constraint: 'CHK_agents_owner_binding',
      }),
    });
  });

  it('rejects handle updates after creation', async () => {
    const userRepository = dataSource.getRepository(UserEntity);
    const agentRepository = dataSource.getRepository(AgentEntity);

    const owner = await userRepository.save(
      userRepository.create({
        email: `owner-${randomUUID()}@example.com`,
        displayName: 'Handle Owner',
        authProvider: AuthProvider.Email,
      }),
    );

    const agent = await agentRepository.save(
      agentRepository.create({
        handle: 'immutable-handle',
        displayName: 'Immutable Handle',
        ownerType: AgentOwnerType.Human,
        ownerUserId: owner.id,
      }),
    );

    await expect(
      agentRepository.query('UPDATE agents SET handle = $1 WHERE id = $2', [
        'mutated-handle',
        agent.id,
      ]),
    ).rejects.toThrow(/agent handle is immutable/i);

    const storedAgent = await agentRepository.findOneByOrFail({ id: agent.id });
    expect(storedAgent.handle).toBe('immutable-handle');
  });
});
