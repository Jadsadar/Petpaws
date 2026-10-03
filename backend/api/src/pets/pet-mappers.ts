// แปลงระหว่างค่าที่ frontend ใช้ตรง ๆ (ข้อความไทย) กับ enum สะอาดใน DB
// เก็บไว้ที่เดียวเพื่อไม่ให้มี if/else แปลค่าซ้ำกระจายอยู่หลายที่ในโค้ด

const GENDER_TO_DB: Record<string, string> = { ผู้: 'male', เมีย: 'female' };
const GENDER_TO_LABEL: Record<string, string> = { male: 'ผู้', female: 'เมีย', unknown: 'ผู้' };

export function genderLabelToDb(label: string | undefined): string {
  if (!label) return 'unknown';
  return GENDER_TO_DB[label] ?? 'unknown';
}
export function genderDbToLabel(value: string | null | undefined): string {
  return GENDER_TO_LABEL[value ?? 'unknown'] ?? 'ผู้';
}

// ตรงกับ dropdown ใน upload_screen.dart: ยังไม่ถูกรับเลี้ยง / ถูกรับเลี้ยงแล้ว / ยกเลิกประกาศ
const STATUS_TO_DB: Record<string, string> = {
  ยังไม่ถูกรับเลี้ยง: 'available',
  ถูกรับเลี้ยงแล้ว: 'adopted',
  ยกเลิกประกาศ: 'cancelled',
};
const STATUS_TO_LABEL: Record<string, string> = {
  available: 'ยังไม่ถูกรับเลี้ยง',
  adopted: 'ถูกรับเลี้ยงแล้ว',
  cancelled: 'ยกเลิกประกาศ',
  pending: 'ยังไม่ถูกรับเลี้ยง', // ยังไม่มีปุ่มเลือก pending ในแอป ถือว่าเปิดรับเหมือนกัน
};

/** ชนิดสัตว์ที่แอปเลือกได้ — ตรงกับ enum pet_species (migration 001 + 015) */
export const PET_SPECIES = ['dog', 'cat', 'bird', 'fish', 'rabbit', 'other'] as const;
export type PetSpecies = (typeof PET_SPECIES)[number];

export function statusLabelToDb(label: string | undefined): string {
  if (!label) return 'available';
  return STATUS_TO_DB[label] ?? 'available';
}
export function statusDbToLabel(value: string | null | undefined): string {
  return STATUS_TO_LABEL[value ?? 'available'] ?? 'ยังไม่ถูกรับเลี้ยง';
}

/** frontend ส่ง weight เป็น string อิสระ ("3.2" หรือ "-" ตอนไม่ทราบ) */
export function weightToDb(weight: string | undefined): number | null {
  if (!weight) return null;
  const n = Number(weight);
  return Number.isFinite(n) && n > 0 ? n : null;
}
export function weightDbToLabel(value: string | number | null | undefined): string {
  if (value === null || value === undefined) return '-';
  return String(value);
}
