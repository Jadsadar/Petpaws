/// เหตุผลรายงานที่ backend รับ (ต้องตรงกับ REPORT_REASONS ใน
/// backend/api/src/moderation/dto/create-report.dto.ts เป๊ะ — ส่งค่าอื่นจะโดน 400)
/// ใช้ร่วมกันทั้งฝั่งผู้ใช้ที่ส่งรายงาน (report_dialog) และฝั่งแอดมินที่อ่านรายงาน
const Map<String, String> reportReasonLabels = {
  'fake_info': 'ข้อมูลเป็นเท็จ',
  'spam': 'สแปมหรือโฆษณา',
  'inappropriate': 'เนื้อหาไม่เหมาะสม',
  'scam': 'สงสัยว่าเป็นการหลอกลวง',
  'animal_abuse': 'ทารุณสัตว์',
  'other': 'อื่น ๆ',
};

String reportReasonLabel(String reason) => reportReasonLabels[reason] ?? reason;
