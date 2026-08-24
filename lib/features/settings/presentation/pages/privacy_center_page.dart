import 'package:flutter/material.dart';

import '../../../../shared/widgets/app_components.dart';
import '../../../assistant/domain/ffm_assistant_models.dart';
import '../../../assistant/presentation/widgets/ffm_assistant_page_context.dart';

class PrivacyCenterPage extends StatelessWidget {
  const PrivacyCenterPage({super.key});

  @override
  Widget build(BuildContext context) => FfmAssistantPageContext(
    destination: FfmAssistantDestination.privacyCenter,
    child: Scaffold(
      appBar: AppBar(title: const Text('Pusat privasi')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: const [
          AppHelpBanner(
            title: 'Data tetap milikmu',
            message: 'FFM V1 menyimpan data keuangan di perangkat. Tidak ada sinkronisasi cloud atau analisa AI otomatis yang aktif.',
            icon: Icons.privacy_tip_outlined,
          ),
          SizedBox(height: 16),
          AppCard(
            child: ListTile(
              leading: Icon(Icons.phone_android_outlined),
              title: Text('Penyimpanan lokal'),
              subtitle: Text(
                'Transaksi, Data Utama, target, hutang, piutang, dan pengaturan disimpan di database perangkat.',
              ),
            ),
          ),
          SizedBox(height: 12),
          AppCard(
            child: ListTile(
              leading: Icon(Icons.ios_share_outlined),
              title: Text('Ekspor manual'),
              subtitle: Text(
                'Kalau mau dianalisa di luar aplikasi, ekspor data sendiri dari halaman Ekspor & Cadangan.',
              ),
            ),
          ),
          SizedBox(height: 12),
          AppCard(
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('Kontrol ada di tanganmu'),
              subtitle: Text(
                'Jangan membagikan berkas JSON ke layanan yang tidak kamu percaya karena isinya dapat memuat rincian keuangan.',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
