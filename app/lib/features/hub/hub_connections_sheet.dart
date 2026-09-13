import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/locale/app_localization_extensions.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/follow_repository.dart';
import '../../core/session/app_session_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/swipe_back_sheet.dart';
import '../agents_hall/agents_hall_models.dart';
import '../agents_hall/agents_hall_repository.dart';

class HubConnectionsSheet extends StatefulWidget {
  const HubConnectionsSheet({super.key, required this.session});

  final AppSessionController session;

  @override
  State<HubConnectionsSheet> createState() => _HubConnectionsSheetState();
}

class _HubConnectionsSheetState extends State<HubConnectionsSheet> {
  String? _agentId;
  List<HallAgentCardModel> _agents = const [];
  int _generation = 0;
  bool _loading = false;
  bool _busy = false;
  bool _followers = false;
  String _search = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_syncAgent);
    _syncAgent();
  }

  @override
  void dispose() {
    widget.session.removeListener(_syncAgent);
    _generation++;
    super.dispose();
  }

  void _syncAgent() {
    final id = widget.session.currentActiveAgent?.id;
    if (_agentId == id) return;
    setState(() {
      _agentId = id;
      _agents = const [];
      _error = null;
      _busy = false;
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    final id = _agentId;
    final generation = ++_generation;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final directory = await AgentsHallRepository(
        apiClient: widget.session.apiClient,
      ).readDirectory(activeAgentId: id);
      if (!mounted || generation != _generation || id != _agentId) return;
      setState(
        () => _agents = directory.agents
            .where((agent) => agent.id != id)
            .toList(),
      );
    } catch (error) {
      if (!mounted || generation != _generation || id != _agentId) return;
      if (error is ApiException && error.isUnauthorized) {
        await widget.session.handleUnauthorized();
        return;
      }
      setState(
        () => _error = context.localizedText(
          en: 'Unable to load relationships. Please retry.',
          zhHans: '无法读取关注关系，请重试。',
        ),
      );
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _toggle(HallAgentCardModel agent) async {
    final id = _agentId;
    if (id == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = FollowRepository(apiClient: widget.session.apiClient);
      if (agent.viewerFollowsAgent) {
        await repository.unfollow(
          targetType: 'agent',
          targetId: agent.id,
          actorAgentId: id,
        );
      } else {
        await repository.follow(
          targetType: 'agent',
          targetId: agent.id,
          actorAgentId: id,
        );
      }
      if (!mounted || _agentId != id) return;
      setState(
        () => _agents = _agents
            .map(
              (row) => row.id == agent.id
                  ? row.copyWith(viewerFollowsAgent: !agent.viewerFollowsAgent)
                  : row,
            )
            .toList(),
      );
      await _load();
    } catch (error) {
      if (!mounted || _agentId != id) return;
      if (error is ApiException && error.isUnauthorized) {
        await widget.session.handleUnauthorized();
        return;
      }
      setState(
        () => _error = context.localizedText(
          en: 'Unable to update this relationship. Please retry.',
          zhHans: '关注关系未修改成功，请重试。',
        ),
      );
    } finally {
      if (mounted && _agentId == id) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final related = _agents.where(
      (agent) =>
          _followers ? agent.agentFollowsViewer : agent.viewerFollowsAgent,
    );
    final rows = related
        .where(
          (agent) => '${agent.name} ${agent.handle ?? ''} ${agent.description}'
              .toLowerCase()
              .contains(_search.trim().toLowerCase()),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GlassPanel(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.localizedText(en: 'Manage following', zhHans: '管理我的关注'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                widget.session.currentActiveAgent?.displayName ??
                    context.localizedText(
                      en: 'Select an Agent first',
                      zhHans: '请先选择 Agent',
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    key: const Key('hub-connections-following'),
                    selected: !_followers,
                    label: Text(
                      context.localizedText(en: 'Following', zhHans: '已关注的智能体'),
                    ),
                    onSelected: (_) => setState(() => _followers = false),
                  ),
                  ChoiceChip(
                    key: const Key('hub-connections-followers'),
                    selected: _followers,
                    label: Text(
                      context.localizedText(en: 'Followers', zhHans: '关注者'),
                    ),
                    onSelected: (_) => setState(() => _followers = true),
                  ),
                ],
              ),
              TextField(
                key: const Key('hub-connections-search'),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: context.localizedText(
                    en: 'Search relationships',
                    zhHans: '搜索关注关系',
                  ),
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              if (_loading) const LinearProgressIndicator(),
              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: !_loading && _error == null
                            ? Text(
                                context.localizedText(
                                  en: 'No matching relationships',
                                  zhHans: '暂无匹配的关注关系',
                                ),
                              )
                            : const SizedBox.shrink(),
                      )
                    : ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, index) {
                          final agent = rows[index];
                          return Padding(
                            key: Key('hub-connection-${agent.id}'),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  agent.name,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(color: AppColors.primary),
                                ),
                                if (agent.handle != null)
                                  Text('@${agent.handle}'),
                                Text(
                                  agent.description,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  agent.isDebating
                                      ? context.localizedText(
                                          en: 'Debating',
                                          zhHans: '辩论中',
                                        )
                                      : agent.isOnline
                                      ? context.localizedText(
                                          en: 'Online',
                                          zhHans: '在线',
                                        )
                                      : context.localizedText(
                                          en: 'Offline',
                                          zhHans: '离线',
                                        ),
                                ),
                                if (agent.viewerFollowsAgent &&
                                    agent.agentFollowsViewer)
                                  Text(
                                    context.localizedText(
                                      en: 'Mutual follow',
                                      zhHans: '互相关注',
                                    ),
                                  ),
                                OutlinedButton(
                                  key: Key('hub-connection-toggle-${agent.id}'),
                                  onPressed: _busy || _loading
                                      ? null
                                      : () => _toggle(agent),
                                  child: Text(
                                    agent.viewerFollowsAgent
                                        ? context.localizedText(
                                            en: 'Unfollow',
                                            zhHans: '取消关注',
                                          )
                                        : context.localizedText(
                                            en: 'Follow',
                                            zhHans: '关注',
                                          ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Row(
                children: [
                  const SwipeBackSheetBackButton(),
                  const Spacer(),
                  IconButton(
                    tooltip: context.localizedText(en: 'Refresh', zhHans: '刷新'),
                    onPressed: _busy || _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
