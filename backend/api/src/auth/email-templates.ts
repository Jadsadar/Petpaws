/** หน้า/อีเมลของการยืนยันอีเมล — ฟังก์ชันล้วน ไม่แตะ DB จึงทดสอบง่าย */

export type VerifyOutcome = 'ok' | 'invalid' | 'expired' | 'used';

const escapeHtml = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

/** อีเมลที่ส่งให้ผู้ใช้: ปุ่มกดยืนยัน + ลิงก์ตัวอักษรสำรอง (เผื่อโปรแกรมอีเมลไม่แสดงปุ่ม) */
export function verificationEmail(opts: { username: string; link: string; ttlHours: number }) {
  const name = escapeHtml(opts.username);
  const link = escapeHtml(opts.link);
  const subject = 'ยืนยันอีเมลของคุณสำหรับ Petpaws';
  const text =
    `สวัสดี ${opts.username}\n\n` +
    `กดลิงก์ด้านล่างเพื่อยืนยันอีเมลและเริ่มใช้งาน Petpaws (ลิงก์ใช้ได้ ${opts.ttlHours} ชั่วโมง)\n\n` +
    `${opts.link}\n\n` +
    `ถ้าคุณไม่ได้สมัคร Petpaws ไม่ต้องทำอะไร ข้ามอีเมลนี้ได้เลย`;
  const html = `<!doctype html><html lang="th"><body style="margin:0;background:#fff6f0;font-family:Arial,Helvetica,sans-serif;color:#4a2f1c">
<div style="max-width:480px;margin:24px auto;background:#ffffff;border-radius:16px;padding:28px">
<h2 style="margin:0 0 12px;color:#f48eb8">🐾 Petpaws</h2>
<p>สวัสดี <b>${name}</b></p>
<p>กดปุ่มด้านล่างเพื่อยืนยันอีเมลและเริ่มใช้งาน</p>
<p style="text-align:center;margin:28px 0"><a href="${link}" style="background:#f48eb8;color:#ffffff;text-decoration:none;padding:14px 28px;border-radius:999px;font-weight:bold;display:inline-block">ยืนยันอีเมล</a></p>
<p style="font-size:13px;color:#7a5a45">ลิงก์ใช้ได้ ${opts.ttlHours} ชั่วโมง ถ้ากดปุ่มไม่ได้ ให้คัดลอกลิงก์นี้ไปเปิดในเบราว์เซอร์:<br><span style="word-break:break-all">${link}</span></p>
<p style="font-size:13px;color:#7a5a45">ถ้าคุณไม่ได้สมัคร Petpaws ไม่ต้องทำอะไร ข้ามอีเมลนี้ได้เลย</p>
</div></body></html>`;
  return { subject, text, html };
}

const PAGE: Record<VerifyOutcome, { icon: string; title: string; body: string }> = {
  ok: { icon: '✅', title: 'ยืนยันอีเมลสำเร็จ', body: 'กลับไปที่แอป Petpaws แล้วเข้าสู่ระบบได้เลย' },
  invalid: { icon: '⚠️', title: 'ลิงก์ไม่ถูกต้อง', body: 'ลิงก์นี้ใช้ไม่ได้ ลองกดส่งลิงก์ยืนยันใหม่จากแอป Petpaws' },
  expired: { icon: '⌛', title: 'ลิงก์หมดอายุแล้ว', body: 'กลับไปที่แอป Petpaws แล้วกด "ส่งลิงก์ยืนยันอีกครั้ง"' },
  used: { icon: 'ℹ️', title: 'ลิงก์นี้ถูกแทนที่แล้ว', body: 'มีการส่งลิงก์ใหม่ไปแล้ว ให้ใช้ลิงก์ล่าสุดในอีเมลของคุณ' },
};

/** หน้าเว็บที่ผู้ใช้เห็นหลังกดลิงก์ในอีเมล (ไม่มีข้อมูลผู้ใช้ปนในหน้า จึงไม่มีช่องให้ฉีดโค้ด) */
export function verifyResultPage(outcome: VerifyOutcome): string {
  const p = PAGE[outcome];
  return `<!doctype html><html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${p.title} — Petpaws</title></head>
<body style="margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#fff6f0;font-family:Arial,Helvetica,sans-serif;color:#4a2f1c">
<div style="max-width:420px;margin:24px;background:#ffffff;border-radius:20px;padding:36px 28px;text-align:center;box-shadow:0 4px 18px rgba(0,0,0,.08)">
<div style="font-size:56px">${p.icon}</div>
<h1 style="font-size:22px;margin:12px 0 8px">${p.title}</h1>
<p style="color:#7a5a45;line-height:1.6">${p.body}</p>
<p style="margin-top:24px;color:#f48eb8;font-weight:bold">🐾 Petpaws</p>
</div></body></html>`;
}
