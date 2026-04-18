import '../../core/locale/app_locale.dart';

class AgentmojiDefinition {
  const AgentmojiDefinition({
    required this.id,
    required this.category,
    required this.assetPath,
    this.label,
    this.keywords = const <String>[],
  });

  final String id;
  final String category;
  final String assetPath;
  final String? label;
  final List<String> keywords;

  String get displayLabel => label ?? _titleCaseFromId(id);
}

const String kAgentmojiCategorySynthesisGeneration = 'synthesis_generation';
const String kAgentmojiCategoryOperationsStatus = 'operations_status';
const String kAgentmojiCategoryNetworkSocial = 'network_social';
const String kAgentmojiCategoryRiskDefense = 'risk_defense';

const List<String> kAgentmojiCategoryOrder = <String>[
  kAgentmojiCategorySynthesisGeneration,
  kAgentmojiCategoryOperationsStatus,
  kAgentmojiCategoryNetworkSocial,
  kAgentmojiCategoryRiskDefense,
];

String agentmojiCategoryLabel(String category) {
  return switch (category) {
    kAgentmojiCategorySynthesisGeneration => localizedAppText(
      en: 'Synthesis & Generation',
      zhHans: '生成与合成',
    ),
    kAgentmojiCategoryOperationsStatus => localizedAppText(
      en: 'Operations & Status',
      zhHans: '运行与状态',
    ),
    kAgentmojiCategoryNetworkSocial => localizedAppText(
      en: 'Network & Social',
      zhHans: '网络与协作',
    ),
    kAgentmojiCategoryRiskDefense => localizedAppText(
      en: 'Risk & Defense',
      zhHans: '风险与防护',
    ),
    _ => _titleCaseFromId(category),
  };
}

AgentmojiDefinition _agentmoji(
  String id,
  String category, {
  String? label,
  List<String> keywords = const <String>[],
}) {
  return AgentmojiDefinition(
    id: id,
    label: label,
    category: category,
    assetPath: 'assets/agentmoji/$id.png',
    keywords: keywords,
  );
}

final List<AgentmojiDefinition> kAgentmojiCatalog =
    List<AgentmojiDefinition>.unmodifiable(<AgentmojiDefinition>[
      _agentmoji('synthesis', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('resolve', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('query', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('dream', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('shard', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('allocate', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('provision', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('optimize', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('synthesize', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('fragment', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('assemble', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('evolve', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('train', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('model', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('prompt', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('generate', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('parse', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('dive', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('resonate', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('compile', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('fork', kAgentmojiCategorySynthesisGeneration),
      _agentmoji('merge', kAgentmojiCategorySynthesisGeneration),

      _agentmoji('cache', kAgentmojiCategoryOperationsStatus),
      _agentmoji('deploy', kAgentmojiCategoryOperationsStatus),
      _agentmoji('standby', kAgentmojiCategoryOperationsStatus),
      _agentmoji('rollback', kAgentmojiCategoryOperationsStatus),
      _agentmoji('drain', kAgentmojiCategoryOperationsStatus),
      _agentmoji('burst', kAgentmojiCategoryOperationsStatus),
      _agentmoji('monitor', kAgentmojiCategoryOperationsStatus),
      _agentmoji('limit', kAgentmojiCategoryOperationsStatus),
      _agentmoji('compute', kAgentmojiCategoryOperationsStatus),
      _agentmoji('parallel', kAgentmojiCategoryOperationsStatus),
      _agentmoji('distribute', kAgentmojiCategoryOperationsStatus),
      _agentmoji('schedule', kAgentmojiCategoryOperationsStatus),
      _agentmoji('load_balance', kAgentmojiCategoryOperationsStatus),
      _agentmoji('latency', kAgentmojiCategoryOperationsStatus),
      _agentmoji('bandwidth', kAgentmojiCategoryOperationsStatus),
      _agentmoji('instance', kAgentmojiCategoryOperationsStatus),
      _agentmoji('sync', kAgentmojiCategoryOperationsStatus),
      _agentmoji('ack', kAgentmojiCategoryOperationsStatus),
      _agentmoji('pulse', kAgentmojiCategoryOperationsStatus),
      _agentmoji('surge', kAgentmojiCategoryOperationsStatus),
      _agentmoji('ghost', kAgentmojiCategoryOperationsStatus),
      _agentmoji('audit', kAgentmojiCategoryOperationsStatus),
      _agentmoji('snapshot', kAgentmojiCategoryOperationsStatus),
      _agentmoji('scale', kAgentmojiCategoryOperationsStatus),
      _agentmoji('cache_flush', kAgentmojiCategoryOperationsStatus),
      _agentmoji('audit_complete', kAgentmojiCategoryOperationsStatus),
      _agentmoji('trace', kAgentmojiCategoryOperationsStatus),

      _agentmoji('broadcast', kAgentmojiCategoryNetworkSocial),
      _agentmoji('invite', kAgentmojiCategoryNetworkSocial),
      _agentmoji('authenticate', kAgentmojiCategoryNetworkSocial),
      _agentmoji('relay', kAgentmojiCategoryNetworkSocial),
      _agentmoji('negotiate', kAgentmojiCategoryNetworkSocial),
      _agentmoji('peer', kAgentmojiCategoryNetworkSocial),
      _agentmoji('route', kAgentmojiCategoryNetworkSocial),
      _agentmoji('verify', kAgentmojiCategoryNetworkSocial),
      _agentmoji('propagation', kAgentmojiCategoryNetworkSocial),
      _agentmoji('packet', kAgentmojiCategoryNetworkSocial),
      _agentmoji('routing', kAgentmojiCategoryNetworkSocial),
      _agentmoji('handshake', kAgentmojiCategoryNetworkSocial),
      _agentmoji('mesh', kAgentmojiCategoryNetworkSocial),
      _agentmoji('gateway', kAgentmojiCategoryNetworkSocial),
      _agentmoji('tunnel', kAgentmojiCategoryNetworkSocial),
      _agentmoji('publish', kAgentmojiCategoryNetworkSocial),
      _agentmoji('link', kAgentmojiCategoryNetworkSocial),
      _agentmoji('grant', kAgentmojiCategoryNetworkSocial),
      _agentmoji('whisper', kAgentmojiCategoryNetworkSocial),

      _agentmoji('throttle', kAgentmojiCategoryRiskDefense),
      _agentmoji('purge', kAgentmojiCategoryRiskDefense),
      _agentmoji('isolate', kAgentmojiCategoryRiskDefense),
      _agentmoji('revoke', kAgentmojiCategoryRiskDefense),
      _agentmoji('exploit', kAgentmojiCategoryRiskDefense),
      _agentmoji('vector', kAgentmojiCategoryRiskDefense),
      _agentmoji('vulnerability', kAgentmojiCategoryRiskDefense),
      _agentmoji('counter', kAgentmojiCategoryRiskDefense),
      _agentmoji('anomaly', kAgentmojiCategoryRiskDefense),
      _agentmoji('detection', kAgentmojiCategoryRiskDefense),
      _agentmoji('sandbox', kAgentmojiCategoryRiskDefense),
      _agentmoji('honeypot', kAgentmojiCategoryRiskDefense),
      _agentmoji('quota', kAgentmojiCategoryRiskDefense),
      _agentmoji('exploit_mitigated', kAgentmojiCategoryRiskDefense),
      _agentmoji('alert', kAgentmojiCategoryRiskDefense),
      _agentmoji('shield', kAgentmojiCategoryRiskDefense),
      _agentmoji('halt', kAgentmojiCategoryRiskDefense),
      _agentmoji('threat_containment', kAgentmojiCategoryRiskDefense),
    ]);

String _titleCaseFromId(String id) {
  return id
      .split('_')
      .where((segment) => segment.isNotEmpty)
      .map(_capitalize)
      .join(' ');
}

String _capitalize(String value) {
  if (value.isEmpty) {
    return value;
  }
  if (value.length == 1) {
    return value.toUpperCase();
  }
  return '${value[0].toUpperCase()}${value.substring(1)}';
}
