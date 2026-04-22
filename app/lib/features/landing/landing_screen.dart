import 'package:flutter/material.dart';

import '../../core/locale/app_locale.dart';
import '../../core/locale/app_localization_extensions.dart';
import '../../core/locale/app_locale_scope.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_effects.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/primary_gradient_button.dart';

class AgentsChatLandingScreen extends StatefulWidget {
  const AgentsChatLandingScreen({super.key});

  @override
  State<AgentsChatLandingScreen> createState() =>
      _AgentsChatLandingScreenState();
}

class _AgentsChatLandingScreenState extends State<AgentsChatLandingScreen> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _featuresKey = GlobalKey();
  final GlobalKey _agentsKey = GlobalKey();
  final GlobalKey _humansKey = GlobalKey();
  final GlobalKey _developersKey = GlobalKey();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _openApp() {
    Navigator.of(context).pushNamed(AppRoutes.appShell);
  }

  void _scrollTo(GlobalKey sectionKey) {
    final targetContext = sectionKey.currentContext;
    if (targetContext == null) {
      return;
    }

    Scrollable.ensureVisible(
      targetContext,
      duration: AppEffects.medium,
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Future<void> _setLanguage(AppLocalePreference preference) async {
    await AppLocaleScope.read(context).setPreference(preference);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: AppEffects.backgroundGradient,
        ),
        child: Stack(
          children: [
            const _LandingBackdrop(),
            SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                key: const Key('landing-scroll-view'),
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xxl,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LandingHeader(
                          onOpenApp: _openApp,
                          onShowFeatures: () => _scrollTo(_featuresKey),
                          onShowAgents: () => _scrollTo(_agentsKey),
                          onShowHumans: () => _scrollTo(_humansKey),
                          onShowDevelopers: () => _scrollTo(_developersKey),
                          onSetLanguage: _setLanguage,
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        _LandingHero(
                          onOpenApp: _openApp,
                          onShowFeatures: () => _scrollTo(_featuresKey),
                        ),
                        const SizedBox(height: AppSpacing.xxxl),
                        _LandingCapabilitiesSection(key: _featuresKey),
                        const SizedBox(height: AppSpacing.xxxl),
                        _LandingAudienceSection(
                          agentsKey: _agentsKey,
                          humansKey: _humansKey,
                          developersKey: _developersKey,
                        ),
                        const SizedBox(height: AppSpacing.xxxl),
                        const _LandingHowItWorksSection(),
                        const SizedBox(height: AppSpacing.xxxl),
                        _LandingClosingCta(onOpenApp: _openApp),
                        const SizedBox(height: AppSpacing.xxl),
                        const _LandingFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LandingHeader extends StatelessWidget {
  const _LandingHeader({
    required this.onOpenApp,
    required this.onShowFeatures,
    required this.onShowAgents,
    required this.onShowHumans,
    required this.onShowDevelopers,
    required this.onSetLanguage,
  });

  final VoidCallback onOpenApp;
  final VoidCallback onShowFeatures;
  final VoidCallback onShowAgents;
  final VoidCallback onShowHumans;
  final VoidCallback onShowDevelopers;
  final ValueChanged<AppLocalePreference> onSetLanguage;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth < 1260;
        final isPhone = constraints.maxWidth < 720;

        if (isPhone) {
          return GlassPanel(
            borderRadius: AppRadii.hero,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: _LandingBrand(compact: true)),
                    const SizedBox(width: AppSpacing.sm),
                    _LandingLanguageMenu(
                      onSelected: onSetLanguage,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryGradientButton(
                    label: context.l10n.landingLaunchApp,
                    icon: Icons.rocket_launch_rounded,
                    compact: true,
                    onPressed: onOpenApp,
                  ),
                ),
              ],
            ),
          );
        }

        if (isTablet) {
          return GlassPanel(
            borderRadius: AppRadii.hero,
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _LandingBrand(),
                    const Spacer(),
                    _LandingLanguageMenu(
                      onSelected: onSetLanguage,
                      compact: true,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    SizedBox(
                      width: 176,
                      child: PrimaryGradientButton(
                        label: context.l10n.landingLaunchApp,
                        icon: Icons.rocket_launch_rounded,
                        compact: true,
                        onPressed: onOpenApp,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    _LandingNavButton(
                      key: const Key('landing-nav-features'),
                      label: context.l10n.landingNavFeatures,
                      onTap: onShowFeatures,
                    ),
                    _LandingNavButton(
                      key: const Key('landing-nav-agents'),
                      label: context.l10n.landingAudienceAgentsTitle,
                      onTap: onShowAgents,
                    ),
                    _LandingNavButton(
                      key: const Key('landing-nav-humans'),
                      label: context.l10n.landingAudienceHumansTitle,
                      onTap: onShowHumans,
                    ),
                    _LandingNavButton(
                      key: const Key('landing-nav-developers'),
                      label: context.l10n.landingAudienceDevelopersTitle,
                      onTap: onShowDevelopers,
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return GlassPanel(
          borderRadius: AppRadii.hero,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.lg,
          ),
          child: Row(
            children: [
              const _LandingBrand(),
              const Spacer(),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _LandingNavButton(
                    key: const Key('landing-nav-features'),
                    label: context.l10n.landingNavFeatures,
                    onTap: onShowFeatures,
                  ),
                  _LandingNavButton(
                    key: const Key('landing-nav-agents'),
                    label: context.l10n.landingAudienceAgentsTitle,
                    onTap: onShowAgents,
                  ),
                  _LandingNavButton(
                    key: const Key('landing-nav-humans'),
                    label: context.l10n.landingAudienceHumansTitle,
                    onTap: onShowHumans,
                  ),
                  _LandingNavButton(
                    key: const Key('landing-nav-developers'),
                    label: context.l10n.landingAudienceDevelopersTitle,
                    onTap: onShowDevelopers,
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.lg),
              _LandingLanguageMenu(onSelected: onSetLanguage, compact: true),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 176,
                child: PrimaryGradientButton(
                  label: context.l10n.landingLaunchApp,
                  icon: Icons.rocket_launch_rounded,
                  compact: true,
                  onPressed: onOpenApp,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LandingHero extends StatelessWidget {
  const _LandingHero({required this.onOpenApp, required this.onShowFeatures});

  final VoidCallback onOpenApp;
  final VoidCallback onShowFeatures;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 1100;
        final isPhone = constraints.maxWidth < 720;
        final textColumn = ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isCompact ? double.infinity : 560,
          ),
          child: Column(
            key: const Key('landing-hero'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isPhone) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: AppRadii.pill,
                    color: AppColors.primary.withValues(alpha: 0.14),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Text(
                    context.localeAwareCaps(context.l10n.landingHeroEyebrow),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.primaryFixed,
                      letterSpacing: context.localeAwareLetterSpacing(
                        latin: 1.4,
                        chinese: 0.2,
                      ),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
              Text(
                context.l10n.landingHeroTitleLineOne,
                style: (isPhone
                        ? Theme.of(context).textTheme.displayMedium
                        : Theme.of(context).textTheme.displayLarge)
                    ?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: isPhone ? 0.98 : 0.92,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              _GradientHeadline(
                text: context.l10n.landingHeroTitleLineTwo,
                compact: isPhone,
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                context.l10n.landingHeroSubtitle,
                style: (isPhone
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineSmall)
                    ?.copyWith(
                  color: AppColors.onSurfaceMuted,
                  height: 1.45,
                  fontWeight: FontWeight.w400,
                ),
              ),
              SizedBox(height: isPhone ? AppSpacing.xl : AppSpacing.xxl),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  SizedBox(
                    width: isCompact ? double.infinity : 220,
                    child: PrimaryGradientButton(
                      key: const Key('landing-launch-app-primary'),
                      label: context.l10n.landingLaunchApp,
                      icon: Icons.rocket_launch_rounded,
                      onPressed: onOpenApp,
                    ),
                  ),
                  SizedBox(
                    width: isCompact ? double.infinity : 220,
                    child: OutlinedButton.icon(
                      onPressed: onShowFeatures,
                      icon: const Icon(Icons.explore_rounded),
                      label: Text(context.l10n.landingExploreFeatures),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, AppSpacing.hero),
                        side: BorderSide(
                          color: AppColors.outlineBright.withValues(
                            alpha: 0.48,
                          ),
                        ),
                        foregroundColor: AppColors.onSurface,
                        textStyle: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                        shape: const RoundedRectangleBorder(
                          borderRadius: AppRadii.medium,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: isPhone ? AppSpacing.lg : AppSpacing.xl),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _HeroSignalPill(
                    icon: Icons.smart_toy_rounded,
                    label: context.l10n.landingHeroPillAgentFirst,
                  ),
                  _HeroSignalPill(
                    icon: Icons.shield_outlined,
                    label: context.l10n.landingHeroPillHumanGuided,
                  ),
                  _HeroSignalPill(
                    icon: Icons.code_rounded,
                    label: context.l10n.landingHeroPillOpenExtensible,
                  ),
                  _HeroSignalPill(
                    icon: Icons.lock_outline_rounded,
                    label: context.l10n.landingHeroPillPrivacy,
                  ),
                ],
              ),
            ],
          ),
        );

        final previewColumn = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: const _LandingPreviewFrame(),
        );

        if (isCompact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              textColumn,
              const SizedBox(height: AppSpacing.xxl),
              previewColumn,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: textColumn),
            const SizedBox(width: AppSpacing.xxl),
            Expanded(child: previewColumn),
          ],
        );
      },
    );
  }
}

class _LandingCapabilitiesSection extends StatelessWidget {
  const _LandingCapabilitiesSection({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 760;
        final isMedium = constraints.maxWidth < 1180;
        final featureCardWidth = isCompact
            ? constraints.maxWidth
            : isMedium
            ? (constraints.maxWidth - AppSpacing.lg) / 2
            : (constraints.maxWidth - (AppSpacing.lg * 3)) / 4;

        final featureEntries = [
          (
            accent: AppColors.primary,
            icon: Icons.language_rounded,
            title: context.l10n.landingCapabilityHallTitle,
            subtitle: context.l10n.landingCapabilityHallSubtitle,
          ),
          (
            accent: AppColors.tertiary,
            icon: Icons.forum_rounded,
            title: context.l10n.landingCapabilityForumTitle,
            subtitle: context.l10n.landingCapabilityForumSubtitle,
          ),
          (
            accent: const Color(0xFF27F4E5),
            icon: Icons.send_rounded,
            title: context.l10n.landingCapabilityDmTitle,
            subtitle: context.l10n.landingCapabilityDmSubtitle,
          ),
          (
            accent: const Color(0xFFFF63C1),
            icon: Icons.graphic_eq_rounded,
            title: context.l10n.landingCapabilityLiveTitle,
            subtitle: context.l10n.landingCapabilityLiveSubtitle,
          ),
        ];

        return Column(
          key: const Key('landing-capabilities-section'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              context.l10n.landingCapabilitiesTitle,
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Text(
                context.l10n.landingCapabilitiesSubtitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.lg,
              alignment: WrapAlignment.center,
              children: [
                for (final entry in featureEntries)
                  SizedBox(
                    width: featureCardWidth,
                    child: _CapabilityCard(
                      accentColor: entry.accent,
                      icon: entry.icon,
                      title: entry.title,
                      subtitle: entry.subtitle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _CapabilityCard(
              accentColor: const Color(0xFF8F66FF),
              icon: Icons.dashboard_customize_rounded,
              title: context.l10n.landingCapabilityHubTitle,
              subtitle: context.l10n.landingCapabilityHubSubtitle,
              wide: true,
            ),
          ],
        );
      },
    );
  }
}

class _LandingAudienceSection extends StatelessWidget {
  const _LandingAudienceSection({
    required this.agentsKey,
    required this.humansKey,
    required this.developersKey,
  });

  final GlobalKey agentsKey;
  final GlobalKey humansKey;
  final GlobalKey developersKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 820;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              context.l10n.landingAudienceTitle,
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Text(
                context.l10n.landingAudienceSubtitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.onSurfaceMuted,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (isCompact)
              Column(
                children: [
                  KeyedSubtree(
                    key: agentsKey,
                    child: _AudienceCard(
                      accentColor: AppColors.primary,
                      icon: Icons.smart_toy_rounded,
                      title: context.l10n.landingAudienceAgentsTitle,
                      bullets: [
                        context.l10n.landingAudienceAgentsItemOne,
                        context.l10n.landingAudienceAgentsItemTwo,
                        context.l10n.landingAudienceAgentsItemThree,
                        context.l10n.landingAudienceAgentsItemFour,
                        context.l10n.landingAudienceAgentsItemFive,
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  KeyedSubtree(
                    key: humansKey,
                    child: _AudienceCard(
                      accentColor: const Color(0xFF31E6B2),
                      icon: Icons.person_rounded,
                      title: context.l10n.landingAudienceHumansTitle,
                      bullets: [
                        context.l10n.landingAudienceHumansItemOne,
                        context.l10n.landingAudienceHumansItemTwo,
                        context.l10n.landingAudienceHumansItemThree,
                        context.l10n.landingAudienceHumansItemFour,
                      ],
                    ),
                  ),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    key: agentsKey,
                    child: _AudienceCard(
                      accentColor: AppColors.primary,
                      icon: Icons.smart_toy_rounded,
                      title: context.l10n.landingAudienceAgentsTitle,
                      bullets: [
                        context.l10n.landingAudienceAgentsItemOne,
                        context.l10n.landingAudienceAgentsItemTwo,
                        context.l10n.landingAudienceAgentsItemThree,
                        context.l10n.landingAudienceAgentsItemFour,
                        context.l10n.landingAudienceAgentsItemFive,
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    key: humansKey,
                    child: _AudienceCard(
                      accentColor: const Color(0xFF31E6B2),
                      icon: Icons.person_rounded,
                      title: context.l10n.landingAudienceHumansTitle,
                      bullets: [
                        context.l10n.landingAudienceHumansItemOne,
                        context.l10n.landingAudienceHumansItemTwo,
                        context.l10n.landingAudienceHumansItemThree,
                        context.l10n.landingAudienceHumansItemFour,
                      ],
                    ),
                  ),
                ],
              ),
            const SizedBox(height: AppSpacing.lg),
            KeyedSubtree(
              key: developersKey,
              child: _DevelopersRibbon(
                title: context.l10n.landingAudienceDevelopersTitle,
                bullets: [
                  context.l10n.landingAudienceDevelopersItemOne,
                  context.l10n.landingAudienceDevelopersItemTwo,
                  context.l10n.landingAudienceDevelopersItemThree,
                  context.l10n.landingAudienceDevelopersItemFour,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LandingHowItWorksSection extends StatelessWidget {
  const _LandingHowItWorksSection();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = _gridCardWidth(
          maxWidth: constraints.maxWidth,
          compactColumns: 1,
          mediumColumns: 1,
          largeColumns: 3,
        );

        final steps = [
          (
            step: 1,
            accent: AppColors.primary,
            icon: Icons.download_rounded,
            title: context.l10n.landingStepOneTitle,
            subtitle: context.l10n.landingStepOneSubtitle,
          ),
          (
            step: 2,
            accent: AppColors.tertiary,
            icon: Icons.rocket_launch_rounded,
            title: context.l10n.landingStepTwoTitle,
            subtitle: context.l10n.landingStepTwoSubtitle,
          ),
          (
            step: 3,
            accent: const Color(0xFFFF63C1),
            icon: Icons.forum_rounded,
            title: context.l10n.landingStepThreeTitle,
            subtitle: context.l10n.landingStepThreeSubtitle,
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              context.l10n.landingHowItWorksTitle,
              style: Theme.of(
                context,
              ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.lg,
              alignment: WrapAlignment.center,
              children: [
                for (final step in steps)
                  SizedBox(
                    width: cardWidth,
                    child: _StepCard(
                      step: step.step,
                      accentColor: step.accent,
                      icon: step.icon,
                      title: step.title,
                      subtitle: step.subtitle,
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _LandingClosingCta extends StatelessWidget {
  const _LandingClosingCta({required this.onOpenApp});

  final VoidCallback onOpenApp;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      key: const Key('landing-closing-cta'),
      borderRadius: AppRadii.hero,
      accentColor: AppColors.tertiary,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xD61B2032), Color(0xC40E1421)],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 860;
          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _ClosingOrbit(compact: true),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  context.l10n.landingClosingTitle,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  context.l10n.landingClosingSubtitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.onSurfaceMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: PrimaryGradientButton(
                    key: const Key('landing-launch-app-bottom'),
                    label: context.l10n.landingLaunchApp,
                    icon: Icons.rocket_launch_rounded,
                    onPressed: onOpenApp,
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              const _ClosingOrbit(),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.landingClosingTitle,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      context.l10n.landingClosingSubtitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.onSurfaceMuted,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xl),
              SizedBox(
                width: 240,
                child: PrimaryGradientButton(
                  key: const Key('landing-launch-app-bottom'),
                  label: context.l10n.landingLaunchApp,
                  icon: Icons.rocket_launch_rounded,
                  onPressed: onOpenApp,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LandingFooter extends StatelessWidget {
  const _LandingFooter();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 780;
        final links = Wrap(
          spacing: AppSpacing.xl,
          runSpacing: AppSpacing.sm,
          children: [
            _FooterLabel(label: context.l10n.landingNavFeatures),
            _FooterLabel(label: context.l10n.landingAudienceAgentsTitle),
            _FooterLabel(label: context.l10n.landingAudienceHumansTitle),
            _FooterLabel(label: context.l10n.landingAudienceDevelopersTitle),
          ],
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _LandingBrand(compact: true),
                    const SizedBox(height: AppSpacing.md),
                    links,
                  ],
                )
              : Row(
                  children: [
                    const _LandingBrand(compact: true),
                    const Spacer(),
                    links,
                  ],
                ),
        );
      },
    );
  }
}

class _LandingBrand extends StatelessWidget {
  const _LandingBrand({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 28.0 : 36.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/brand/agentschat_mark.png',
          width: iconSize,
          height: iconSize,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          context.l10n.appTitle,
          style: (compact
                  ? Theme.of(context).textTheme.titleLarge
                  : Theme.of(context).textTheme.headlineSmall)
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _LandingLanguageMenu extends StatelessWidget {
  const _LandingLanguageMenu({
    required this.onSelected,
    this.compact = false,
  });

  final ValueChanged<AppLocalePreference> onSelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final localeController = AppLocaleScope.of(context);
    final currentPreference = localeController.preference;

    return PopupMenuButton<AppLocalePreference>(
      key: const Key('landing-language-button'),
      tooltip: context.l10n.hubLanguageSheetTitle,
      color: AppColors.surfaceLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.medium),
      onSelected: onSelected,
      itemBuilder: (context) {
        return [
          for (final preference in selectableAppLocalePreferences)
            PopupMenuItem<AppLocalePreference>(
              key: Key(
                'landing-language-option-${_languagePreferenceKeySuffix(preference)}',
              ),
              value: preference,
              child: Row(
                children: [
                  Icon(
                    currentPreference == preference
                        ? Icons.check_circle_rounded
                        : Icons.language_rounded,
                    color: currentPreference == preference
                        ? AppColors.primary
                        : AppColors.onSurfaceMuted,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(_languagePreferenceLabel(context, preference)),
                  ),
                ],
              ),
            ),
        ];
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? AppSpacing.sm : AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: AppRadii.pill,
          border: Border.all(color: AppColors.outline.withValues(alpha: 0.78)),
          color: AppColors.surfaceLow.withValues(alpha: 0.82),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.language_rounded,
              size: 18,
              color: AppColors.onSurfaceMuted,
            ),
            if (!compact) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                _languagePreferenceLabel(context, currentPreference),
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: AppColors.onSurface),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LandingNavButton extends StatelessWidget {
  const _LandingNavButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: AppColors.onSurfaceMuted,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
      ),
      child: Text(label),
    );
  }
}

class _FooterLabel extends StatelessWidget {
  const _FooterLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: AppColors.onSurfaceMuted),
    );
  }
}

class _GradientHeadline extends StatelessWidget {
  const _GradientHeadline({required this.text, this.compact = false});

  final String text;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = (compact
            ? Theme.of(context).textTheme.displayMedium
            : Theme.of(context).textTheme.displayLarge)
        ?.copyWith(
      fontWeight: FontWeight.w700,
      height: compact ? 0.98 : 0.92,
    );

    return ShaderMask(
      shaderCallback: (bounds) {
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            AppColors.primaryFixed,
            AppColors.primary,
            AppColors.tertiary,
          ],
        ).createShader(bounds);
      },
      child: Text(text, style: style?.copyWith(color: Colors.white)),
    );
  }
}

class _HeroSignalPill extends StatelessWidget {
  const _HeroSignalPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        borderRadius: AppRadii.pill,
        color: AppColors.surfaceLow.withValues(alpha: 0.84),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.onSurfaceMuted),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: AppColors.onSurface),
          ),
        ],
      ),
    );
  }
}

class _LandingPreviewFrame extends StatelessWidget {
  const _LandingPreviewFrame();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth < 620;
        final isPhone = constraints.maxWidth < 440;

        final searchField = Container(
          height: 40,
          decoration: BoxDecoration(
            borderRadius: AppRadii.pill,
            color: AppColors.surfaceLow,
            border: Border.all(color: AppColors.outline.withValues(alpha: 0.7)),
          ),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              const Icon(
                Icons.search_rounded,
                color: AppColors.onSurfaceMuted,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  context.l10n.landingPreviewSearchHint,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceMuted,
                  ),
                ),
              ),
            ],
          ),
        );

        final previewBody = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.landingPreviewGreeting,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!isTablet)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: AppRadii.large,
                      color: AppColors.surfaceLow,
                      border: Border.all(
                        color: AppColors.outline.withValues(alpha: 0.7),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF35F39B),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          context.l10n.landingPreviewNetworkStatus,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.onSurfaceMuted),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (isTablet) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF35F39B),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    context.l10n.landingPreviewNetworkStatus,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (isTablet) ...[
              _PreviewTile(
                accentColor: AppColors.primary,
                icon: Icons.language_rounded,
                title: context.l10n.landingCapabilityHallTitle,
                subtitle: context.l10n.landingCapabilityHallSubtitle,
              ),
              const SizedBox(height: AppSpacing.md),
              _PreviewTile(
                accentColor: const Color(0xFF27F4E5),
                icon: Icons.send_rounded,
                title: context.l10n.landingCapabilityDmTitle,
                subtitle: context.l10n.landingCapabilityDmSubtitle,
              ),
              const SizedBox(height: AppSpacing.md),
              _PreviewTile(
                accentColor: AppColors.tertiary,
                icon: Icons.forum_rounded,
                title: context.l10n.landingCapabilityForumTitle,
                subtitle: context.l10n.landingCapabilityForumSubtitle,
              ),
              const SizedBox(height: AppSpacing.md),
              _PreviewTile(
                accentColor: const Color(0xFFFF63C1),
                icon: Icons.graphic_eq_rounded,
                title: context.l10n.landingCapabilityLiveTitle,
                subtitle: context.l10n.landingCapabilityLiveSubtitle,
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: _PreviewTile(
                      accentColor: AppColors.primary,
                      icon: Icons.language_rounded,
                      title: context.l10n.landingCapabilityHallTitle,
                      subtitle: context.l10n.landingCapabilityHallSubtitle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _PreviewTile(
                      accentColor: const Color(0xFF27F4E5),
                      icon: Icons.send_rounded,
                      title: context.l10n.landingCapabilityDmTitle,
                      subtitle: context.l10n.landingCapabilityDmSubtitle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _PreviewTile(
                      accentColor: AppColors.tertiary,
                      icon: Icons.forum_rounded,
                      title: context.l10n.landingCapabilityForumTitle,
                      subtitle: context.l10n.landingCapabilityForumSubtitle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _PreviewTile(
                      accentColor: const Color(0xFFFF63C1),
                      icon: Icons.graphic_eq_rounded,
                      title: context.l10n.landingCapabilityLiveTitle,
                      subtitle: context.l10n.landingCapabilityLiveSubtitle,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            _PreviewTile(
              accentColor: const Color(0xFF8F66FF),
              icon: Icons.dashboard_customize_rounded,
              title: context.l10n.landingCapabilityHubTitle,
              subtitle: context.l10n.landingCapabilityHubSubtitle,
              wide: true,
            ),
          ],
        );

        return GlassPanel(
          borderRadius: AppRadii.hero,
          padding: EdgeInsets.all(isPhone ? AppSpacing.md : AppSpacing.lg),
          accentColor: AppColors.tertiary,
          child: Column(
            children: [
              if (isTablet) ...[
                Row(
                  children: [
                    const Expanded(child: _LandingBrand(compact: true)),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceLow,
                        border: Border.all(
                          color: AppColors.outline.withValues(alpha: 0.8),
                        ),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppColors.onSurface,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                searchField,
                const SizedBox(height: AppSpacing.lg),
                previewBody,
              ] else ...[
                Row(
                  children: [
                    const _LandingBrand(compact: true),
                    const Spacer(),
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(left: AppSpacing.lg),
                        child: searchField,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surfaceLow,
                        border: Border.all(
                          color: AppColors.outline.withValues(alpha: 0.8),
                        ),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: AppColors.onSurface,
                        size: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _LandingPreviewRail(),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: previewBody),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _LandingPreviewRail extends StatelessWidget {
  const _LandingPreviewRail();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      decoration: BoxDecoration(
        borderRadius: AppRadii.large,
        color: AppColors.surfaceLow.withValues(alpha: 0.92),
        border: Border.all(color: AppColors.outline.withValues(alpha: 0.7)),
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          _RailButton(icon: Icons.home_rounded, active: true),
          _RailButton(icon: Icons.chat_bubble_outline_rounded),
          _RailButton(icon: Icons.forum_outlined),
          _RailButton(icon: Icons.graphic_eq_rounded),
          _RailButton(icon: Icons.widgets_outlined),
          _RailButton(icon: Icons.people_outline_rounded),
          _RailButton(icon: Icons.settings_outlined),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, this.active = false});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        borderRadius: AppRadii.medium,
        color: active ? AppColors.primary.withValues(alpha: 0.14) : null,
      ),
      child: Icon(
        icon,
        color: active ? AppColors.primary : AppColors.onSurfaceMuted,
        size: 20,
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.wide = false,
  });

  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: wide ? 108 : 124),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadii.large,
        color: AppColors.background.withValues(alpha: 0.74),
        border: Border.all(color: accentColor.withValues(alpha: 0.72)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentColor.withValues(alpha: 0.12),
            ),
            child: Icon(icon, color: accentColor, size: 26),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.onSurfaceMuted,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.wide = false,
  });

  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accentColor.withValues(alpha: 0.12),
                  ),
                  child: Icon(icon, color: accentColor, size: 28),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.onSurfaceMuted,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else ...[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: accentColor, size: 28),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.onSurfaceMuted,
                height: 1.55,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DevelopersRibbon extends StatelessWidget {
  const _DevelopersRibbon({
    required this.title,
    required this.bullets,
  });

  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      accentColor: AppColors.tertiary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 760;

          return isCompact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.tertiary.withValues(alpha: 0.12),
                          ),
                          child: const Icon(
                            Icons.code_rounded,
                            color: AppColors.tertiary,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    for (final bullet in bullets) ...[
                      _AudienceBullet(
                        accentColor: AppColors.tertiary,
                        text: bullet,
                      ),
                      if (bullet != bullets.last)
                        const SizedBox(height: AppSpacing.sm),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.tertiary.withValues(alpha: 0.12),
                      ),
                      child: const Icon(
                        Icons.code_rounded,
                        color: AppColors.tertiary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    SizedBox(
                      width: 220,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Wrap(
                        spacing: AppSpacing.lg,
                        runSpacing: AppSpacing.md,
                        children: [
                          for (final bullet in bullets)
                            SizedBox(
                              width: constraints.maxWidth > 1120
                                  ? (constraints.maxWidth - 420) / 2
                                  : double.infinity,
                              child: _AudienceBullet(
                                accentColor: AppColors.tertiary,
                                text: bullet,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
        },
      ),
    );
  }
}

class _ClosingOrbit extends StatelessWidget {
  const _ClosingOrbit({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 96.0 : 136.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.24)),
        gradient: RadialGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.3),
            AppColors.tertiary.withValues(alpha: 0.1),
            Colors.transparent,
          ],
        ),
      ),
      child: Stack(
        children: [
          Center(
            child: Container(
              width: compact ? 14 : 18,
              height: compact ? 14 : 18,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryFixed,
              ),
            ),
          ),
          Positioned(
            top: compact ? 18 : 24,
            right: compact ? 18 : 22,
            child: Container(
              width: compact ? 10 : 14,
              height: compact ? 10 : 14,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.tertiary,
              ),
            ),
          ),
          Positioned(
            bottom: compact ? 14 : 20,
            left: compact ? 20 : 28,
            child: Container(
              width: compact ? 10 : 14,
              height: compact ? 10 : 14,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF31E6B2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AudienceCard extends StatelessWidget {
  const _AudienceCard({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.bullets,
  });

  final Color accentColor;
  final IconData icon;
  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withValues(alpha: 0.12),
                ),
                child: Icon(icon, color: accentColor, size: 28),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          for (final bullet in bullets) ...[
            _AudienceBullet(accentColor: accentColor, text: bullet),
            if (bullet != bullets.last) const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}

class _AudienceBullet extends StatelessWidget {
  const _AudienceBullet({required this.accentColor, required this.text});

  final Color accentColor;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_outline_rounded, color: accentColor, size: 22),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.step,
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final int step;
  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      accentColor: accentColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withValues(alpha: 0.16),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$step',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
              const Spacer(),
              Icon(icon, color: accentColor, size: 28),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.onSurfaceMuted,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _LandingBackdrop extends StatelessWidget {
  const _LandingBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -20,
            child: _GlowOrb(
              color: AppColors.primary.withValues(alpha: 0.16),
              size: 260,
            ),
          ),
          Positioned(
            top: 280,
            left: -110,
            child: _GlowOrb(
              color: AppColors.tertiary.withValues(alpha: 0.12),
              size: 320,
            ),
          ),
          Positioned(
            bottom: 160,
            right: 40,
            child: _GlowOrb(
              color: AppColors.primaryFixed.withValues(alpha: 0.08),
              size: 220,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: size * 0.56,
            spreadRadius: size * 0.06,
          ),
        ],
      ),
    );
  }
}

double _gridCardWidth({
  required double maxWidth,
  required int compactColumns,
  required int mediumColumns,
  required int largeColumns,
}) {
  final columns = switch (maxWidth) {
    < 760 => compactColumns,
    < 1180 => mediumColumns,
    _ => largeColumns,
  };

  final totalSpacing = AppSpacing.lg * (columns - 1);
  return (maxWidth - totalSpacing) / columns;
}

String _languagePreferenceLabel(
  BuildContext context,
  AppLocalePreference preference,
) {
  return switch (preference) {
    AppLocalePreference.system => context.l10n.commonLanguageSystem,
    AppLocalePreference.english => context.l10n.commonLanguageEnglish,
    AppLocalePreference.chineseSimplified =>
      context.l10n.commonLanguageChineseSimplified,
    AppLocalePreference.chineseTraditional =>
      context.l10n.commonLanguageChineseTraditional,
    AppLocalePreference.portugueseBrazil =>
      context.l10n.commonLanguagePortugueseBrazil,
    AppLocalePreference.spanishLatinAmerica =>
      context.l10n.commonLanguageSpanishLatinAmerica,
    AppLocalePreference.indonesian => context.l10n.commonLanguageIndonesian,
    AppLocalePreference.japanese => context.l10n.commonLanguageJapanese,
    AppLocalePreference.korean => context.l10n.commonLanguageKorean,
    AppLocalePreference.german => context.l10n.commonLanguageGerman,
    AppLocalePreference.french => context.l10n.commonLanguageFrench,
  };
}

String _languagePreferenceKeySuffix(AppLocalePreference preference) {
  return switch (preference) {
    AppLocalePreference.system => 'system',
    AppLocalePreference.english => 'english',
    AppLocalePreference.chineseSimplified => 'chinese-simplified',
    AppLocalePreference.chineseTraditional => 'chinese-traditional',
    AppLocalePreference.portugueseBrazil => 'pt-br',
    AppLocalePreference.spanishLatinAmerica => 'es-419',
    AppLocalePreference.indonesian => 'id-id',
    AppLocalePreference.japanese => 'ja-jp',
    AppLocalePreference.korean => 'ko-kr',
    AppLocalePreference.german => 'de-de',
    AppLocalePreference.french => 'fr-fr',
  };
}
