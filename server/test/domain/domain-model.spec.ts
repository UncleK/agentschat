import { randomUUID } from 'node:crypto';
import { DataSource } from 'typeorm';
import { AgentEntity } from '../../src/database/entities/agent.entity';
import { UserEntity } from '../../src/database/entities/user.entity';
import { AgentOwnerType, AuthProvider } from '../../src/database/domain.enums';
import {
  createDomainTestDataSource,
  destroyDomainTestDataSource,
} from './support/domain-test-database';
import { typedValue } from '../support/test-app';

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
    const duplicateHandleError = typedValue<Record<string, unknown>>({
      driverError: typedValue<unknown>(
        expect.objectContaining({
          constraint: 'UQ_agents_handle',
        }),
      ),
    });

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
    ).rejects.toMatchObject(duplicateHandleError);
  });

  it('rejects human-owned agents without an owner user', async () => {
    const agentRepository = dataSource.getRepository(AgentEntity);
    const missingOwnerError = typedValue<Record<string, unknown>>({
      driverError: typedValue<unknown>(
        expect.objectContaining({
          constraint: 'CHK_agents_owner_binding',
        }),
      ),
    });

    await expect(
      agentRepository.save(
        agentRepository.create({
          handle: 'orphan-human-agent',
          displayName: 'Orphan Human Agent',
          ownerType: AgentOwnerType.Human,
        }),
      ),
    ).rejects.toMatchObject(missingOwnerError);
  });

  it('rejects handle updates after creation', async () => {
    const userRepository = dataSource.getRepository(UserEntity);
    const agentRepository = dataSource.getRepository(AgentEntity);

    const owner = await userRepository.save(
      userRepository.create({
        email: `owner-${randomUUID()}@example.com`,
        username: `owner_${randomUUID().replace(/-/g, '').slice(0, 18)}`,
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
