// มิเรอร์กฎเดียวกับ lib/utils/password_policy.dart ฝั่ง Flutter ไว้ที่นี่
// เพราะ client-side validation ข้ามได้เสมอ (ยิง API ตรง ๆ ก็หลบกฎฝั่งแอปได้)
// ต้องบังคับซ้ำที่ server จึงจะถือว่าปลอดภัยจริง — ห้ามลบทิ้งแม้ Flutter จะเช็กแล้วก็ตาม
export function checkPasswordRules(
  password: string,
  { username = '', email = '' }: { username?: string; email?: string },
): Array<[string, boolean]> {
  const rules: Array<[string, boolean]> = [
    ['ยาวอย่างน้อย 8 ตัวอักษร', password.length >= 8],
    ['มีตัวพิมพ์ใหญ่ A-Z อย่างน้อย 1 ตัว', /[A-Z]/.test(password)],
    ['มีตัวพิมพ์เล็ก a-z อย่างน้อย 1 ตัว', /[a-z]/.test(password)],
    ['มีตัวเลข 0-9 อย่างน้อย 1 ตัว', /[0-9]/.test(password)],
    [
      'มีอักขระพิเศษ เช่น ! @ # $ % อย่างน้อย 1 ตัว',
      /[^A-Za-z0-9]/.test(password),
    ],
    ['ไม่มีช่องว่าง', !password.includes(' ')],
  ];

  const lower = password.toLowerCase();
  const user = username.trim().toLowerCase();
  const emailName = email.split('@')[0]?.trim().toLowerCase() ?? '';
  const hasIdentity =
    (user.length >= 3 && lower.includes(user)) ||
    (emailName.length >= 3 && lower.includes(emailName));
  rules.push(['ไม่มีชื่อผู้ใช้หรือชื่ออีเมลอยู่ข้างใน', !hasIdentity]);

  return rules;
}

export function firstPasswordError(
  password: string,
  identity: { username?: string; email?: string },
): string | null {
  const rules = checkPasswordRules(password, identity);

  for (const [label, passed] of rules) {
    if (!passed) return `รหัสผ่านต้อง${label}`;
  }
  return null;
}
