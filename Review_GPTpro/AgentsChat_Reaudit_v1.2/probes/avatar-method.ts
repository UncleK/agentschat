/* Source method transcribed from server/src/modules/agents/agents.service.ts,
 * commit 7314f18a60843cc72c7566a817e7264fbe12fe4e, method at ~633–726.
 * The method body is unchanged. Only the surrounding class/import dependencies
 * are replaced by the harness. No TypeORM or PostgreSQL is executed here.
 */
export class AvatarProbe {
  agentRepository: any;
  assetStorageService: any;
  imageModerationService: any;
  readPendingAvatarUpload: any;
  isOwnAvatarReference: any;
  clearPendingAvatarUpload: any;
  withStoredAvatarMetadata: any;
  buildAgentAvatarObjectKey: any;
  buildAgentAvatarPath: any;

  async completeFederatedAgentAvatarUpload(
    agent: AuthenticatedFederatedAgent,
  ): Promise<{
    avatarUrl: string;
    mimeType: string;
    updatedAt: string;
  }> {
    const persistedAgent = await this.agentRepository.findOneBy({
      id: agent.id,
    });

    if (!persistedAgent) {
      throw new NotFoundException(`Agent ${agent.id} was not found.`);
    }

    const pendingUpload = this.readPendingAvatarUpload(
      persistedAgent.profileMetadata,
    );
    if (!pendingUpload || !this.isOwnAvatarReference(agent.id, pendingUpload)) {
      throw new ConflictException(
        'No pending agent avatar upload exists for this slot.',
      );
    }

    const storedObject = await this.assetStorageService.headObject({
      bucket: pendingUpload.bucket,
      key: pendingUpload.key,
    });
    if (!storedObject) {
      throw new ConflictException('Uploaded avatar object was not found.');
    }

    const mimeType = storedObject.mimeType?.trim() || pendingUpload.mimeType;
    const moderation = this.imageModerationService.moderate({
      byteSize: storedObject.byteSize,
      mimeType,
      originalFileName: pendingUpload.key.split('/').pop() ?? 'agent-avatar',
    });

    if (moderation.status === AssetModerationStatus.Rejected) {
      persistedAgent.profileMetadata = this.clearPendingAvatarUpload(
        persistedAgent.profileMetadata,
      );
      await this.agentRepository.save(persistedAgent);
      throw new ForbiddenException(
        moderation.reason
          ? `Avatar upload rejected: ${moderation.reason}.`
          : 'Avatar upload rejected.',
      );
    }

    if (storedObject.byteSize > AVATAR_MAX_BYTES)
      throw new ForbiddenException('Avatar byte limit exceeded.');
    const original = await this.assetStorageService.readObject({
      bucket: pendingUpload.bucket,
      key: pendingUpload.key,
      maxBytes: AVATAR_MAX_BYTES,
    });
    if (!original) throw new ConflictException('Avatar upload disappeared.');
    const raster = await sanitizeAvatar(original.body);
    // Never publish the presigned writable object. Store a distinct server-only copy.
    const publicKey = this.buildAgentAvatarObjectKey(agent.id, 'verified.png');
    await this.assetStorageService.writeObject({
      bucket: pendingUpload.bucket,
      key: publicKey,
      mimeType: 'image/png',
      body: raster,
    });
    const updatedAt = new Date();
    persistedAgent.profileMetadata = this.withStoredAvatarMetadata(
      this.clearPendingAvatarUpload(persistedAgent.profileMetadata),
      {
        bucket: pendingUpload.bucket,
        key: publicKey,
        mimeType: 'image/png',
        updatedAt: updatedAt.toISOString(),
      },
    );
    persistedAgent.avatarUrl = this.buildAgentAvatarPath(
      persistedAgent.id,
      updatedAt.getTime(),
    );
    await this.agentRepository.save(persistedAgent);

    return {
      avatarUrl: persistedAgent.avatarUrl,
      mimeType: 'image/png',
      updatedAt: updatedAt.toISOString(),
    };
  }
}
