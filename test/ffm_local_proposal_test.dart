import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:ffm_manager/features/assistant/data/ffm_local_proposal.dart';

void main() {
  group('FfmLocalProposalParser', () {
    test(
      'membaca proposal valid dan tetap menandainya sebagai draft review',
      () {
        final result = FfmLocalProposalParser.parse(
          jsonEncode({
            'formatVersion': 'ffm-local-proposal-v2',
            'proposalType': 'expense',
            'merchantName': 'Warung Amanah',
            'transactionDate': '2026-08-22',
            'timezone': 'Asia/Jakarta',
            'totalAmount': 30000,
            'currency': 'IDR',
            'suggestedCategory': 'Belanja harian',
            'suggestedAccount': 'Tunai',
            'items': [
              {
                'name': 'Beras',
                'quantity': 1,
                'unitPrice': 20000,
                'totalPrice': 20000,
                'itemConfidence': .95,
              },
              {
                'name': 'Telur',
                'quantity': 1,
                'unitPrice': 10000,
                'totalPrice': 10000,
                'itemConfidence': .9,
              },
            ],
            'fieldConfidence': {
              'merchantName': .95,
              'transactionDate': .9,
              'totalAmount': .95,
              'suggestedCategory': .7,
              'suggestedAccount': .7,
            },
            'warnings': [],
            'needsClarification': false,
            'clarificationQuestion': null,
          }),
        );

        expect(result.proposal.totalAmount, 30000);
        expect(result.proposal.items, hasLength(2));
        expect(result.proposal.needsReview, isFalse);
        expect(result.proposal.toJson()['totalAmount'], 30000);
      },
    );

    test('JSON rusak menghasilkan proposal perlu dicek tanpa exception', () {
      final result = FfmLocalProposalParser.parse('bukan JSON dari model');

      expect(result.rawJson, isNull);
      expect(result.needsReview, isTrue);
      expect(result.proposal.issues, contains('invalid_json'));
    });

    test('nominal desimal tidak diterima sebagai integer rupiah', () {
      final result = FfmLocalProposalParser.parse(
        jsonEncode({
          'formatVersion': 'ffm-local-proposal-v2',
          'proposalType': 'expense',
          'transactionDate': '2026-08-22',
          'totalAmount': 10000.5,
          'items': [],
          'fieldConfidence': {},
          'warnings': [],
          'needsClarification': false,
        }),
      );

      expect(result.proposal.totalAmount, isNull);
      expect(result.proposal.issues, contains('invalid_total_amount'));
      expect(result.needsReview, isTrue);
    });

    test('validator menghitung ulang item dan menambah warning mismatch', () {
      final result = FfmLocalProposalParser.parse(
        jsonEncode({
          'formatVersion': 'ffm-local-proposal-v2',
          'proposalType': 'expense',
          'transactionDate': '2026-08-22',
          'totalAmount': 30000,
          'items': [
            {
              'name': 'Barang',
              'quantity': 1,
              'unitPrice': 20000,
              'totalPrice': 20000,
              'itemConfidence': .9,
            },
          ],
          'fieldConfidence': {'totalAmount': .9},
          'warnings': [],
          'needsClarification': false,
        }),
      );

      expect(result.proposal.issues, contains('sum_mismatch'));
      expect(
        result.proposal.warnings.map((warning) => warning.code),
        contains('sum_mismatch'),
      );
      expect(result.needsReview, isTrue);
    });

    test('confidence rendah membuat proposal perlu dicek', () {
      final result = FfmLocalProposalParser.parse(
        jsonEncode({
          'formatVersion': 'ffm-local-proposal-v2',
          'proposalType': 'expense',
          'transactionDate': '2026-08-22',
          'totalAmount': 10000,
          'items': [],
          'fieldConfidence': {'totalAmount': .5},
          'warnings': [],
          'needsClarification': false,
        }),
      );

      expect(result.proposal.issues, contains('low_confidence:totalAmount'));
      expect(result.needsReview, isTrue);
    });

    test('response navigation mempertahankan target terstruktur tanpa field transaksi', () {
      final result = FfmLocalProposalParser.parse(
        jsonEncode({
          'formatVersion': 'ffm-local-proposal-v2',
          'proposalType': 'navigation',
          'actionTarget': 'budget',
          'needsClarification': false,
        }),
      );

      expect(result.proposal.proposalType, 'navigation');
      expect(result.proposal.actionTarget, 'budget');
      expect(result.proposal.needsReview, isFalse);
    });

    test('response read_query dan help tidak dianggap sebagai transaksi', () {
      for (final type in const ['read_query', 'help']) {
        final result = FfmLocalProposalParser.parse(
          jsonEncode({
            'formatVersion': 'ffm-local-proposal-v2',
            'proposalType': type,
            'actionTarget': type == 'read_query' ? 'monthly_summary' : null,
            'needsClarification': false,
          }),
        );

        expect(result.proposal.proposalType, type);
        expect(result.proposal.needsReview, isFalse);
        expect(result.proposal.totalAmount, isNull);
      }
    });

    test(
      'observasi screenshot memakai help dan assistantMessage yang dibatasi',
      () {
        final result = FfmLocalProposalParser.parse(
          jsonEncode({
            'formatVersion': 'ffm-local-proposal-v2',
            'proposalType': 'help',
            'assistantMessage': 'Gambar menampilkan layar error Flutter dengan teks Invalid argument(s): 380.0.',
            'needsClarification': false,
          }),
        );

        expect(result.proposal.needsReview, isFalse);
        expect(result.proposal.assistantMessage, contains('380.0'));
      },
    );

    test('out_of_domain valid agar respons gambar tidak dibuang parser', () {
      final result = FfmLocalProposalParser.parse(
        jsonEncode({
          'formatVersion': 'ffm-local-proposal-v2',
          'proposalType': 'out_of_domain',
          'assistantMessage': 'Gambar menampilkan pesan error aplikasi.',
          'needsClarification': false,
        }),
      );

      expect(result.proposal.needsReview, isFalse);
      expect(result.proposal.proposalType, 'out_of_domain');
    });

    test(
      'proposalType dan target kosong tetap ditolak sebagai response model',
      () {
        final result = FfmLocalProposalParser.parse(
          jsonEncode({
            'formatVersion': 'ffm-local-proposal-v2',
            'proposalType': 'delete_everything',
            'actionTarget': 'arbitrary_route',
          }),
        );

        expect(result.proposal.issues, contains('invalid_proposal_type'));
        expect(result.needsReview, isTrue);
      },
    );
  });
}
