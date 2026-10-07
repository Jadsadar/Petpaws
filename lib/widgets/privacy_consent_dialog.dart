import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// หนังสือแจ้งและขอความยินยอมเก็บข้อมูลส่วนบุคคล (ตาม พ.ร.บ. คุ้มครองข้อมูลส่วนบุคคล 2562)
/// เด้งตอนเข้าหน้าสมัครสมาชิก — ต้องเลื่อนอ่านจนสุดก่อน จึงจะติ๊กและกด "ยินยอม" ได้
/// คืนค่า true = ยินยอม, false = ไม่ยินยอม, null = ปิดกล่องโดยไม่เลือก
Future<bool?> showPrivacyConsentDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _PrivacyConsentDialog(),
  );
}

class _PrivacyConsentDialog extends StatefulWidget {
  const _PrivacyConsentDialog();

  @override
  State<_PrivacyConsentDialog> createState() => _PrivacyConsentDialogState();
}

class _PrivacyConsentDialogState extends State<_PrivacyConsentDialog> {
  final _scroll = ScrollController();
  bool _readToEnd = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_checkEnd);
    // ข้อความสั้นจนไม่ต้องเลื่อน (จอใหญ่มาก) ถือว่าอ่านครบแล้ว
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkEnd());
  }

  void _checkEnd() {
    if (_readToEnd || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 24) {
      setState(() => _readToEnd = true);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // กล่องเลื่อนเอกสารสูงตามจอ (160–420) ส่วนที่เหลือ (ชื่อเรื่อง/ช่องติ๊ก/ปุ่ม) ถ้าจอเตี้ยมาก
    // กล่องทั้งใบเลื่อนได้ (scrollable) แทนการล้นจอ
    final policyHeight = (MediaQuery.sizeOf(context).height * 0.38)
        .clamp(160.0, 420.0)
        .toDouble();
    return AlertDialog(
      scrollable: true,
      title: const Text('การยินยอมให้เก็บและใช้ข้อมูลส่วนบุคคล'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: policyHeight,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.section,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: AppColors.sand),
                ),
                child: Scrollbar(
                  controller: _scroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    key: const ValueKey('consent-scroll'),
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    child: const _PolicyText(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (!_readToEnd)
              const Row(
                children: [
                  Icon(Icons.keyboard_double_arrow_down,
                      size: 18, color: AppColors.brown),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text('กรุณาเลื่อนอ่านให้จบก่อน จึงจะยินยอมได้',
                        style: TextStyle(fontSize: 13, color: AppColors.brown)),
                  ),
                ],
              ),
            CheckboxListTile(
              key: const ValueKey('consent-check'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.primary,
              value: _checked,
              enabled: _readToEnd,
              onChanged: (v) => setState(() => _checked = v ?? false),
              title: const Text(
                'ฉันได้อ่านและเข้าใจ และยินยอมให้ PetPaws เก็บและใช้ข้อมูลส่วนบุคคลตามที่ระบุข้างต้น',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('consent-decline'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('ไม่ยินยอม'),
        ),
        ElevatedButton(
          key: const ValueKey('consent-accept'),
          onPressed: _readToEnd && _checked
              ? () => Navigator.pop(context, true)
              : null,
          child: const Text('ยินยอม'),
        ),
      ],
    );
  }
}

class _PolicyText extends StatelessWidget {
  const _PolicyText();

  static const _sections = <(String, List<String>)>[
    (
      '1. ข้อมูลที่เราเก็บ',
      [
        'ข้อมูลบัญชี: ชื่อผู้ใช้ อีเมล และรหัสผ่าน (เก็บแบบเข้ารหัสทางเดียว ไม่มีใครอ่านรหัสผ่านจริงได้)',
        'ข้อมูลโปรไฟล์: ชื่อเล่น รูปโปรไฟล์ จังหวัด เบอร์โทรศัพท์ LINE ID ชื่อ Facebook ประเภทที่พักอาศัย และไลฟ์สไตล์/นิสัยที่คุณเลือก',
        'ข้อมูลประกาศสัตว์เลี้ยง: รูป ชื่อ ชนิด สายพันธุ์ อายุ เพศ น้ำหนัก จังหวัด เรื่องราว และสถานะการรับเลี้ยง',
        'ข้อมูลการใช้งาน: การกดถูกใจ/ข้าม ข้อความ รูปและวิดีโอในแชท การรายงาน และการบล็อกผู้ใช้',
        'ข้อมูลทางเทคนิค: หมายเลข IP และเวลาที่เข้าใช้ (ใช้ป้องกันการเดารหัสผ่านและการใช้งานผิดปกติ) และโทเคนสำหรับการแจ้งเตือน (ถ้าเปิดใช้)',
        'ข้อมูลที่เก็บในเครื่องของคุณ: โทเคนเข้าสู่ระบบ เพื่อให้ไม่ต้องล็อกอินใหม่ทุกครั้ง',
      ]
    ),
    (
      '2. วัตถุประสงค์ในการใช้ข้อมูล',
      [
        'สร้างและยืนยันตัวตนบัญชีของคุณ',
        'แสดงประกาศและจับคู่สัตว์เลี้ยงกับผู้ที่สนใจรับเลี้ยง โดยใช้จังหวัดและไลฟ์สไตล์',
        'ให้ผู้รับเลี้ยงและเจ้าของติดต่อพูดคุยกันผ่านแชท',
        'คัดกรองผู้รับเลี้ยงให้เหมาะกับสัตว์ (เช่น ประเภทที่พักอาศัย)',
        'ตรวจสอบรายงาน ป้องกันการหลอกลวง สแปม และการใช้งานที่ไม่เหมาะสม',
        'รักษาความปลอดภัยของระบบ และสำรองข้อมูลเพื่อป้องกันข้อมูลสูญหาย',
      ]
    ),
    (
      '3. ใครเห็นข้อมูลของคุณบ้าง',
      [
        'ผู้ใช้อื่นเห็น: ชื่อเล่น รูปโปรไฟล์ จังหวัด ไลฟ์สไตล์ LINE ID ชื่อ Facebook และประกาศของคุณ',
        'ผู้ใช้อื่นไม่เห็น: อีเมล รหัสผ่าน และเบอร์โทรศัพท์',
        'ข้อความแชทเห็นเฉพาะคู่สนทนา ยกเว้นข้อความที่ถูกรายงานซึ่งผู้ดูแลระบบจะตรวจสอบได้',
        'ผู้ดูแลระบบเข้าถึงข้อมูลได้เท่าที่จำเป็นต่อการดูแลระบบและตรวจสอบรายงาน',
        'เราไม่ขายหรือส่งต่อข้อมูลของคุณให้บุคคลภายนอกเพื่อการตลาด',
      ]
    ),
    (
      '4. การจัดเก็บและระยะเวลา',
      [
        'ข้อมูลเก็บบนเซิร์ฟเวอร์ในประเทศไทย และสำรองข้อมูลอัตโนมัติทุกวัน',
        'เราเก็บข้อมูลตลอดที่บัญชียังใช้งานอยู่ เมื่อขอลบบัญชี ข้อมูลจะถูกลบหรือทำให้ระบุตัวตนไม่ได้ภายในระยะเวลาที่เหมาะสม',
        'รูปที่ไม่ได้ใช้งานแล้วจะถูกลบออกจากระบบโดยอัตโนมัติ',
      ]
    ),
    (
      '5. สิทธิของคุณ',
      [
        'ขอเข้าถึง ขอสำเนา และแก้ไขข้อมูลของตนเอง (แก้ไขได้เองในหน้าโปรไฟล์)',
        'ขอให้ลบบัญชีและข้อมูล หรือคัดค้าน/ระงับการใช้ข้อมูลบางส่วน',
        'ถอนความยินยอมเมื่อใดก็ได้ ซึ่งอาจทำให้ใช้บริการบางส่วนไม่ได้',
        'ร้องเรียนต่อสำนักงานคณะกรรมการคุ้มครองข้อมูลส่วนบุคคล หากเห็นว่ามีการใช้ข้อมูลไม่ถูกต้อง',
      ]
    ),
    (
      '6. ติดต่อเรา',
      [
        'หากต้องการใช้สิทธิหรือมีคำถามเกี่ยวกับข้อมูลส่วนบุคคล ติดต่อทีมผู้พัฒนา PetPaws ผ่านช่องทางที่ระบุในแอป',
      ]
    ),
  ];

  @override
  Widget build(BuildContext context) {
    const body =
        TextStyle(fontSize: 14, height: 1.5, color: AppColors.textDark);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PetPaws ให้ความสำคัญกับข้อมูลส่วนบุคคลของคุณ เอกสารนี้อธิบายว่าเราเก็บข้อมูลอะไร '
          'ใช้เพื่ออะไร และคุณมีสิทธิอะไรบ้าง ตามพระราชบัญญัติคุ้มครองข้อมูลส่วนบุคคล พ.ศ. 2562',
          style: body,
        ),
        for (final (title, items) in _sections) ...[
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDark)),
          const SizedBox(height: 4),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  ', style: body),
                  Expanded(child: Text(item, style: body)),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
        const Text('— จบเอกสาร —',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
      ],
    );
  }
}
