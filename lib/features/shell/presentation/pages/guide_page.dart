import 'package:flutter/material.dart';
import 'package:shuttle/features/sharing/presentation/bloc/sharing_bloc.dart';
import 'package:shuttle/features/usb/presentation/bloc/usb_cubit.dart';
import 'package:shuttle/core/theme/app_theme.dart';
import 'package:shuttle/core/widgets/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// How the app works, in full.
///
/// Worth a whole screen because the mental model is the part people get
/// wrong, not the buttons: one device runs the server and the other joins it
/// by address, which means the same URL means different things depending on
/// which screen you are looking at. Every route is spelled out with both ends
/// named, because "your Mac" and "the other device" are the same machine
/// depending on where you are standing.
class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    final url = context.select(
      (SharingBloc b) => b.state.status.primaryUrl ?? 'http://…',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('How it works'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppTheme.space4,
          0,
          AppTheme.space4,
          AppTheme.space10,
        ),
        children: [
          _Intro(url: url),
          const SizedBox(height: AppTheme.space6),
          const SectionLabel('The three ways across'),
          _Route(
            number: '1',
            title: 'Browser — no app on the other device',
            subtitle: 'The one you will use most',
            steps: [
              'This device is already running a small web server.',
              'On the *other* device — your phone, a friend\'s laptop, a '
                  'tablet — open a browser and go to $url',
              'That page has two halves: pull anything this device is '
                  'sharing, or drop files onto it.',
              'Files sent to this device land in the Received list.',
            ],
            note:
                'Nothing to install on the other end. Both devices must be '
                'on the same Wi-Fi.',
          ),
          _Route(
            number: '2',
            title: 'App on both devices',
            subtitle: 'For two machines you own',
            steps: [
              'Install and open this app on both.',
              'Each finds the other automatically and lists it under Nearby '
                  'devices, on the Receive tab.',
              'Tap the other device to open it. The screen says whether the '
                  'two are connected and lists everything that has passed '
                  'between them.',
              'Send files to it with the button at the top, or take what it '
                  'is sharing from the list below.',
            ],
            note:
                'This is the only route where the Nearby devices list does '
                'anything. A browser cannot appear there — it has nothing to '
                'announce.',
          ),
          if (UsbCubit.isSupportedPlatform)
            const _Route(
              number: '3',
              title: 'USB cable',
              subtitle: 'No Wi-Fi at all',
              steps: [
                'Plug the phone into this computer and unlock it.',
                'Open the USB tab — the phone\'s storage is browsable '
                    'directly.',
                'Select files and copy them across, or send files back.',
              ],
              note:
                  'Plugging in as "file transfer" (MTP) is enough. A cable '
                  'on its own does not create a network, so the Browser route '
                  'above will not work over USB unless you turn on tethering.',
            ),
          const SizedBox(height: AppTheme.space6),
          const SectionLabel('Answers'),
          const _Faq(
            question: 'Why is the download list empty?',
            answer:
                'Nothing is shared until you add it. Go to Share → Add '
                'files on the device you want to copy *from*. The rest of that '
                'device stays private — this is not a file browser of the '
                'whole disk, and it deliberately cannot be.',
          ),
          const _Faq(
            question: 'I opened the address and it says I am on this device',
            answer:
                'You pasted it into a browser on the same machine that is '
                'serving it, so there is nothing to transfer. Type it on the '
                'other device instead.',
          ),
          const _Faq(
            question: 'My phone is not in Nearby devices',
            answer:
                'That list only finds other copies of this app. If the '
                'phone is just running a browser, it will never appear — and '
                'it does not need to. Use the address.',
          ),
          const _Faq(
            question: 'Where do received files go?',
            answer:
                'Downloads/Shuttle on a computer, and the '
                'app\'s own folder on a phone. The exact path is shown at the '
                'bottom of the Receive tab.',
          ),
          const _Faq(
            question: 'Is any of this going over the internet?',
            answer:
                'No. Files move directly between the two devices on your '
                'local network, or down the cable. There is no server in the '
                'middle and no account.',
          ),
          const _Faq(
            question: 'Can other people on this Wi-Fi see my files?',
            answer:
                'Anyone on the network who finds the address can download '
                'whatever is in the share list, and send files to you. Only '
                'what you add is exposed — but on a public or shared network, '
                'clear the list when you are done.',
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return SurfaceCard(
      padding: const EdgeInsets.all(AppTheme.space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('The idea', style: context.type.titleMedium),
          const SizedBox(height: AppTheme.space2),
          Text(
            'One device hands files out. The other one comes and gets them. '
            'Whichever device you are holding, this app turns it into the '
            'one handing out — and gives you an address the other device can '
            'use to reach it.',
            style: context.type.bodyMedium?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: AppTheme.space4),
          Container(
            padding: const EdgeInsets.all(AppTheme.space4),
            decoration: BoxDecoration(
              color: palette.surfaceHigh,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Row(
              children: [
                _Node(label: 'This device', icon: Icons.computer_rounded),
                Expanded(
                  child: Column(
                    children: [
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: palette.mint,
                      ),
                      Text(
                        'shares',
                        style: context.type.labelSmall?.copyWith(
                          color: palette.mint,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Icon(
                        Icons.arrow_back_rounded,
                        size: 16,
                        color: palette.accent,
                      ),
                      Text(
                        'sends',
                        style: context.type.labelSmall?.copyWith(
                          color: palette.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                _Node(label: 'Other device', icon: Icons.smartphone_rounded),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      width: 84,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              border: Border.all(color: palette.border),
            ),
            child: Icon(icon, size: 20, color: palette.textPrimary),
          ),
          const SizedBox(height: AppTheme.space2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: context.type.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Route extends StatelessWidget {
  const _Route({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.steps,
    required this.note,
  });

  final String number;
  final String title;
  final String subtitle;
  final List<String> steps;
  final String note;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space3),
      child: SurfaceCard(
        padding: const EdgeInsets.all(AppTheme.space5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: palette.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    number,
                    style: context.type.labelSmall?.copyWith(
                      color: palette.accent,
                    ),
                  ),
                ),
                const SizedBox(width: AppTheme.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: context.type.titleSmall),
                      Text(subtitle, style: context.type.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.space4),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: AppTheme.space3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 7, right: 12),
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: palette.textMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        steps[i].replaceAll('*', ''),
                        style: context.type.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.all(AppTheme.space3),
              decoration: BoxDecoration(
                color: palette.surfaceHigh,
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: palette.textMuted,
                  ),
                  const SizedBox(width: AppTheme.space2),
                  Expanded(child: Text(note, style: context.type.bodySmall)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  const _Faq({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space2),
      child: SurfaceCard(
        child: Theme(
          // The default divider on an ExpansionTile fights the card's border.
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(question, style: context.type.titleSmall),
            shape: const Border(),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppTheme.space4,
              0,
              AppTheme.space4,
              AppTheme.space4,
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(answer, style: context.type.bodyMedium),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
