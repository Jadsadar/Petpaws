import { checkPasswordRules } from './password-policy.js';

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
  const html = `<!doctype html><html lang="th"><body style="margin:0;background:#fff6f0;font-family:system-ui,-apple-system,'Segoe UI',Tahoma,Arial,sans-serif;line-height:1.6;color:#4a2f1c">
<div style="max-width:480px;margin:24px auto;background:#ffffff;border-radius:16px;padding:28px">
<h2 style="margin:0 0 12px;color:#f48eb8">🐾 Petpaws</h2>
<p>สวัสดี <b>${name}</b></p>
<p>กดปุ่มด้านล่างเพื่อยืนยันอีเมลและเริ่มใช้งาน</p>
<p style="text-align:center;margin:28px 0"><a href="${link}" style="background:#f48eb8;color:#ffffff;text-decoration:none;padding:14px 28px;border-radius:10px;font-weight:600;display:inline-block">ยืนยันอีเมล</a></p>
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
<body style="margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#fff6f0;font-family:system-ui,-apple-system,'Segoe UI',Tahoma,Arial,sans-serif;line-height:1.6;color:#4a2f1c">
<div style="max-width:420px;margin:24px;background:#ffffff;border-radius:16px;padding:36px 28px;text-align:center;border:1px solid #e6ccb2">
<div style="font-size:36px">${p.icon}</div>
<h1 style="font-size:22px;font-weight:600;line-height:1.4;margin:12px 0 8px">${p.title}</h1>
<p style="color:#7a5a45;line-height:1.6">${p.body}</p>
<p style="margin-top:24px;color:#f48eb8;font-weight:600">🐾 Petpaws</p>
</div></body></html>`;
}

// ---------------------------------------------------------------------------
// ลืมรหัสผ่าน: อีเมลลิงก์ตั้งรหัสใหม่ + หน้าเว็บที่ลิงก์พาไป
// ---------------------------------------------------------------------------

export type ResetOutcome = 'ok' | 'invalid' | 'expired' | 'used';

/** อีเมลลิงก์ตั้งรหัสผ่านใหม่ (หน้าเว็บอยู่ที่ GET /auth/reset-password) */
export function passwordResetEmail(opts: { username: string; link: string; ttlMinutes: number }) {
  const name = escapeHtml(opts.username);
  const link = escapeHtml(opts.link);
  const subject = 'ตั้งรหัสผ่านใหม่สำหรับ Petpaws';
  const text =
    `สวัสดี ${opts.username}\n\n` +
    `มีคำขอตั้งรหัสผ่านใหม่สำหรับบัญชี Petpaws ของคุณ กดลิงก์ด้านล่างเพื่อตั้งรหัสผ่านใหม่ (ลิงก์ใช้ได้ ${opts.ttlMinutes} นาที และใช้ได้ครั้งเดียว)\n\n` +
    `${opts.link}\n\n` +
    `ถ้าคุณไม่ได้ขอ ไม่ต้องทำอะไร ข้ามอีเมลนี้ได้เลย รหัสผ่านเดิมของคุณยังใช้ได้ตามปกติ`;
  const html = `<!doctype html><html lang="th"><body style="margin:0;background:#fff6f0;font-family:system-ui,-apple-system,'Segoe UI',Tahoma,Arial,sans-serif;line-height:1.6;color:#4a2f1c">
<div style="max-width:480px;margin:24px auto;background:#ffffff;border-radius:16px;padding:28px">
<h2 style="margin:0 0 12px;color:#f48eb8">🐾 Petpaws</h2>
<p>สวัสดี <b>${name}</b></p>
<p>มีคำขอตั้งรหัสผ่านใหม่สำหรับบัญชีของคุณ กดปุ่มด้านล่างเพื่อตั้งรหัสผ่านใหม่</p>
<p style="text-align:center;margin:28px 0"><a href="${link}" style="background:#f48eb8;color:#ffffff;text-decoration:none;padding:14px 28px;border-radius:10px;font-weight:600;display:inline-block">ตั้งรหัสผ่านใหม่</a></p>
<p style="font-size:13px;color:#7a5a45">ลิงก์ใช้ได้ ${opts.ttlMinutes} นาที และใช้ได้ครั้งเดียว ถ้ากดปุ่มไม่ได้ ให้คัดลอกลิงก์นี้ไปเปิดในเบราว์เซอร์:<br><span style="word-break:break-all">${link}</span></p>
<p style="font-size:13px;color:#7a5a45">ถ้าคุณไม่ได้ขอ ไม่ต้องทำอะไร ข้ามอีเมลนี้ได้เลย รหัสผ่านเดิมของคุณยังใช้ได้ตามปกติ</p>
</div></body></html>`;
  return { subject, text, html };
}

/** แจ้งเตือนหลังเปลี่ยนรหัสผ่านสำเร็จ — ถ้าไม่ใช่เจ้าของทำ จะได้รู้ทันที */
export function passwordChangedEmail(opts: { username: string }) {
  const name = escapeHtml(opts.username);
  const subject = 'รหัสผ่าน Petpaws ของคุณถูกเปลี่ยนแล้ว';
  const text =
    `สวัสดี ${opts.username}\n\n` +
    `รหัสผ่านของบัญชี Petpaws ถูกเปลี่ยนแล้ว และทุกอุปกรณ์ถูกออกจากระบบ ต้องเข้าสู่ระบบใหม่ด้วยรหัสผ่านใหม่\n\n` +
    `ถ้าคุณไม่ได้เป็นคนเปลี่ยน กรุณาติดต่อผู้ดูแลระบบทันที`;
  const html = `<!doctype html><html lang="th"><body style="margin:0;background:#fff6f0;font-family:system-ui,-apple-system,'Segoe UI',Tahoma,Arial,sans-serif;line-height:1.6;color:#4a2f1c">
<div style="max-width:480px;margin:24px auto;background:#ffffff;border-radius:16px;padding:28px">
<h2 style="margin:0 0 12px;color:#f48eb8">🐾 Petpaws</h2>
<p>สวัสดี <b>${name}</b></p>
<p>รหัสผ่านของบัญชีคุณถูกเปลี่ยนแล้ว และทุกอุปกรณ์ถูกออกจากระบบ ต้องเข้าสู่ระบบใหม่ด้วยรหัสผ่านใหม่</p>
<p style="font-size:13px;color:#7a5a45">ถ้าคุณไม่ได้เป็นคนเปลี่ยน กรุณาติดต่อผู้ดูแลระบบทันที</p>
</div></body></html>`;
  return { subject, text, html };
}

const RESET_PAGE: Record<Exclude<ResetOutcome, 'ok'>, { icon: string; title: string; body: string }> = {
  invalid: { icon: '⚠️', title: 'ลิงก์ไม่ถูกต้อง', body: 'ลิงก์นี้ใช้ไม่ได้ ลองกด "ลืมรหัสผ่าน" ในแอป Petpaws เพื่อขอลิงก์ใหม่' },
  expired: { icon: '⌛', title: 'ลิงก์หมดอายุแล้ว', body: 'ลิงก์ตั้งรหัสผ่านมีอายุจำกัด กลับไปที่แอป Petpaws แล้วกด "ลืมรหัสผ่าน" เพื่อขอลิงก์ใหม่' },
  used: { icon: 'ℹ️', title: 'ลิงก์นี้ถูกใช้ไปแล้ว', body: 'ลิงก์ใช้ได้ครั้งเดียว ถ้ายังต้องการตั้งรหัสผ่านใหม่ ให้ขอลิงก์ใหม่จากแอป Petpaws' },
};

const pageShell = (title: string, inner: string) => `<!doctype html><html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>${title} — Petpaws</title></head>
<body style="margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#fff6f0;font-family:system-ui,-apple-system,'Segoe UI',Tahoma,Arial,sans-serif;line-height:1.6;color:#4a2f1c">
<div style="width:100%;max-width:420px;margin:24px;box-sizing:border-box;background:#ffffff;border-radius:16px;padding:32px 24px;border:1px solid #e6ccb2">
${inner}
<p style="margin:24px 0 0;text-align:center;color:#f48eb8;font-weight:600">🐾 Petpaws</p>
</div></body></html>`;

/** หน้าผลลัพธ์ (สำเร็จ หรือลิงก์ใช้ไม่ได้) — ไม่มีข้อมูลผู้ใช้ปนในหน้า */
export function resetResultPage(outcome: ResetOutcome): string {
  if (outcome === 'ok') {
    return pageShell(
      'ตั้งรหัสผ่านใหม่สำเร็จ',
      `<div style="text-align:center"><div style="font-size:36px">✅</div>
<h1 style="font-size:22px;font-weight:600;line-height:1.4;margin:12px 0 8px">ตั้งรหัสผ่านใหม่สำเร็จ</h1>
<p style="color:#7a5a45;line-height:1.6">กลับไปที่แอป Petpaws แล้วเข้าสู่ระบบด้วยรหัสผ่านใหม่ได้เลย (ทุกอุปกรณ์เดิมถูกออกจากระบบแล้ว)</p></div>`,
    );
  }
  const p = RESET_PAGE[outcome];
  return pageShell(
    p.title,
    `<div style="text-align:center"><div style="font-size:36px">${p.icon}</div>
<h1 style="font-size:22px;font-weight:600;line-height:1.4;margin:12px 0 8px">${p.title}</h1>
<p style="color:#7a5a45;line-height:1.6">${p.body}</p></div>`,
  );
}

/**
 * ฟอร์ม POST ทำงานได้แม้ปิด JavaScript; JavaScript เพิ่มปุ่มดูรหัสและรายการเงื่อนไขขณะพิมพ์
 * token ใส่ในช่อง hidden เพื่อส่งกลับมากับฟอร์ม (escape กัน HTML แทรก)
 */
export function resetFormPage(opts: {
  token: string;
  error?: string;
  username?: string;
  email?: string;
}): string {
  const err = opts.error
    ? `<p role="alert" style="background:#fdecec;color:#b3261e;border-radius:12px;padding:10px 14px;font-size:14px;line-height:1.5">${escapeHtml(opts.error)}</p>`
    : '';
  const input = (name: string, label: string) =>
    `<label for="${name}" style="display:block;margin:14px 0 4px;font-size:14px;font-weight:600">${label}</label>
<div style="position:relative">
<input id="${name}" type="password" name="${name}" required minlength="8" maxlength="128" autocomplete="new-password"
 style="width:100%;box-sizing:border-box;padding:12px 56px 12px 14px;border:1px solid #e6ccb2;border-radius:10px;font:inherit;font-size:16px">
<button hidden type="button" data-password-toggle="${name}" aria-controls="${name}" aria-label="แสดง${label}" aria-pressed="false" title="แสดง${label}"
 style="position:absolute;right:4px;top:2px;width:44px;height:40px;background:transparent;border:0;border-radius:8px;color:#7a5a45;cursor:pointer">
<svg aria-hidden="true" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/><path data-eye-slash style="display:none" d="M3 3l18 18"/></svg></button>
</div>`;
  return pageShell(
    'ตั้งรหัสผ่านใหม่',
    `<h1 style="font-size:22px;font-weight:600;line-height:1.4;margin:0 0 6px;text-align:center">ตั้งรหัสผ่านใหม่</h1>
<p style="color:#7a5a45;font-size:14px;line-height:1.6;margin:0 0 8px">รหัสผ่านต้องยาวอย่างน้อย 8 ตัว มีตัวพิมพ์ใหญ่ ตัวพิมพ์เล็ก ตัวเลข และอักขระพิเศษ อย่างละ 1 ตัวขึ้นไป ไม่มีช่องว่าง และไม่มีชื่อผู้ใช้หรือชื่ออีเมลอยู่ข้างใน</p>
${err}
<form id="reset-password-form" method="post" action="/auth/reset-password/form" data-username="${escapeHtml(opts.username ?? '')}" data-email="${escapeHtml(opts.email ?? '')}">
<input type="hidden" name="token" value="${escapeHtml(opts.token)}">
${input('newPassword', 'รหัสผ่านใหม่')}
<div id="password-checklist" hidden style="margin-top:10px;padding:12px;background:#fff6f0;border-radius:12px;font-size:12px">
<div style="display:flex;gap:10px;align-items:center"><progress id="password-strength" max="7" value="0" aria-label="ความแข็งแรงของรหัสผ่าน" style="flex:1;min-width:0;accent-color:#b3261e"></progress><span id="password-strength-label"></span></div>
<ul id="password-rules" style="list-style:none;padding:0;margin:8px 0 0"></ul>
</div>
${input('confirmPassword', 'ยืนยันรหัสผ่านใหม่')}
<button type="submit" style="margin-top:22px;width:100%;background:#f48eb8;color:#ffffff;border:0;border-radius:10px;padding:14px;font:inherit;font-size:16px;font-weight:600;cursor:pointer">บันทึกรหัสผ่านใหม่</button>
</form>
<script>
// ใช้ฟังก์ชันเดียวกับ server เพื่อให้รายการเงื่อนไขและการรับรหัสตรงกัน
const checkPasswordRules = ${checkPasswordRules.toString()};
const form = document.getElementById('reset-password-form');
const password = document.getElementById('newPassword');
const confirmPassword = document.getElementById('confirmPassword');
const checklist = document.getElementById('password-checklist');
const rulesList = document.getElementById('password-rules');
const strength = document.getElementById('password-strength');
const strengthLabel = document.getElementById('password-strength-label');
document.querySelectorAll('[data-password-toggle]').forEach((button) => {
  button.hidden = false;
  const input = document.getElementById(button.dataset.passwordToggle);
  const label = document.querySelector('label[for="' + input.id + '"]').textContent;
  button.addEventListener('click', () => {
    const visible = input.type === 'password';
    input.type = visible ? 'text' : 'password';
    button.setAttribute('aria-pressed', String(visible));
    button.setAttribute('aria-label', (visible ? 'ซ่อน' : 'แสดง') + label);
    button.title = (visible ? 'ซ่อน' : 'แสดง') + label;
    button.querySelector('[data-eye-slash]').style.display = visible ? '' : 'none';
  });
});
function updateValidation() {
  const rules = checkPasswordRules(password.value, { username: form.dataset.username, email: form.dataset.email });
  const failed = rules.find((rule) => !rule[1]);
  password.setCustomValidity(password.value && failed ? 'รหัสผ่านต้อง' + failed[0] : '');
  confirmPassword.setCustomValidity(confirmPassword.value && confirmPassword.value !== password.value ? 'รหัสผ่านทั้งสองช่องไม่ตรงกัน' : '');
  checklist.hidden = !password.value;
  const passed = rules.filter((rule) => rule[1]).length;
  const color = passed < 4 ? '#b3261e' : (passed < rules.length ? '#9a6700' : '#287d3c');
  strength.value = password.value ? passed : 0;
  strength.max = rules.length;
  strength.style.accentColor = color;
  strengthLabel.textContent = passed < 4 ? 'อ่อน' : (passed < rules.length ? 'พอใช้' : 'แข็งแรง');
  strengthLabel.style.color = color;
  rulesList.replaceChildren(...rules.map(([label, ok]) => {
    const item = document.createElement('li');
    item.textContent = (ok ? '✓ ' : '○ ') + label;
    item.style.color = ok ? '#287d3c' : '#4a2f1c';
    item.style.marginBottom = '4px';
    return item;
  }));
}
password.addEventListener('input', updateValidation);
confirmPassword.addEventListener('input', updateValidation);
form.addEventListener('submit', (event) => {
  updateValidation();
  if (!form.reportValidity()) event.preventDefault();
});
updateValidation();
</script>`,
  );
}
